import Foundation
import CryptoKit

struct NativeVMCap:Sendable {let bytes:UInt64;let sampledAt:Int64}
struct NativeVMLivenessProof:Sendable {
    let sampledAt:Int64
    let bootHash:String
    init(sample:VMKernelSample,expectedBootHash:String,now:Int64)throws {
        guard sample.total>0,sample.total<=UInt64(ActivityPolicy.maximumTimestamp),sample.free<=sample.total,
              sample.bootHash==expectedBootHash,sample.bootHash.utf8.count==64,
              sample.bootHash.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
              sample.sampledAt>=0,now>=sample.sampledAt,now<=ActivityPolicy.maximumTimestamp,now-sample.sampledAt<=1000 else {throw RuntimeError.identity}
        sampledAt=sample.sampledAt;bootHash=sample.bootHash
    }
}
protocol NativeVMCapReading:Sendable {func capture(liveness:NativeVMLivenessProof)throws->NativeVMCap}
struct VerifiedVMCap:NativeVMCapReading {
    let executable:VerifiedExecutable
    let home:String
    func capture(liveness:NativeVMLivenessProof)throws->NativeVMCap {
        let began=ProcessInfo.processInfo.systemUptime,sampledAt=HostResources.nowMilliseconds()
        // Fresh verified global-kernel observation proves this exact VM is
        // already running; do not spawn a redundant status CLI or start it.
        guard sampledAt>=liveness.sampledAt,sampledAt-liveness.sampledAt<=1000 else {throw RuntimeError.identity}
        let environment=["HOME":home]
        let result=try executable.run(arguments:["config","get","memory_mib"],timeout:1,maximumOutput:64,environment:environment)
        guard result.status==0,let text=String(data:result.output,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines),
              !text.isEmpty,text.utf8.count<=8,text.first != "0",text.utf8.allSatisfy({(48...57).contains($0)}),
              let mib=UInt64(text),mib<=UInt64(ActivityPolicy.maximumTimestamp)/(1<<20),
              ProcessInfo.processInfo.systemUptime-began<=3 else {throw RuntimeError.invalid}
        return NativeVMCap(bytes:mib*(1<<20),sampledAt:sampledAt)
    }
}

// A separately reviewed architecture/profile authority, NEVER task JSON or
// an inference permission. Reviewer must establish that ALL VM consumers,
// including machines/system services, share this exact global procfs kernel.
// The installed-only resource factory binds this review to a root policy and
// authenticated kernel sample; public startup is not wired. No empty-machine
// inventory is fabricated.
struct SharedVMKernelPermission:Sendable {
    let nativeProfileHash:String
    let bootHash:String
    let reviewDigest:String
    init(nativeProfileHash:String,bootHash:String,reviewDigest:String)throws {
        func hash(_ value:String)->Bool {value.utf8.count==64 && value.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})}
        guard hash(nativeProfileHash),hash(bootHash),hash(reviewDigest) else {throw RuntimeError.identity}
        self.nativeProfileHash=nativeProfileHash;self.bootHash=bootHash;self.reviewDigest=reviewDigest
    }
}

// Uses actual whole-kernel free pages, not cgroup sums/host footprint/reclaim.
// Kernel observations remain 2s; configuration may be reused for <3s only,
// always carrying its ORIGINAL time into independent 5s admission freshness.
// All work remains one operation in SandboxExecutor's shared two-slot budget.
final class SharedKernelVMReader:VMResourceReading,@unchecked Sendable {
    private let kernel:any VMResourceReading
    private let cap:any NativeVMCapReading
    private let permission:SharedVMKernelPermission
    private let physical:UInt64
    private let now:@Sendable()->Int64
    private let uptime:@Sendable()->TimeInterval
    private let lock=NSLock()
    private var cached:(value:NativeVMCap,uptime:TimeInterval)?
    private var previousNow:Int64 = -1
    private var fenced=false
    init(kernel:any VMResourceReading,cap:any NativeVMCapReading,permission:SharedVMKernelPermission,physical:UInt64,
         now:@escaping @Sendable()->Int64=HostResources.nowMilliseconds,
         uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {
        self.kernel=kernel;self.cap=cap;self.permission=permission;self.physical=physical;self.now=now;self.uptime=uptime
    }
    // The configuration cache is global/profile-bound, not parent-owned.
    // Do not wait for off-loop native I/O on the lifecycle/controller thread.
    func releaseAfterVerifiedAbsence(id:String) {kernel.releaseAfterVerifiedAbsence(id:id)}
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        lock.lock();defer{lock.unlock()}
        let began=uptime(),stamp=now()
        guard !fenced,stamp>=0,stamp<=ActivityPolicy.maximumTimestamp,stamp>=previousNow,began.isFinite,began>=0 else {fenced=true;cached=nil;throw RuntimeError.identity}
        previousNow=stamp
        guard physical>0,physical<=UInt64(ActivityPolicy.maximumTimestamp),leaseUntil<=ActivityPolicy.maximumTimestamp,
              leaseUntil>stamp,leaseUntil-stamp>=5000 else {cached=nil;throw RuntimeError.deadline}
        do {
            var sample=try kernel.read(configuration:configuration,id:id,leaseUntil:leaseUntil)
            guard sample.bootHash==permission.bootHash else {fenced=true;throw RuntimeError.identity}
            let limit:NativeVMCap
            if let cached,began>=cached.uptime,began-cached.uptime<3 {limit=cached.value}
            else {
                let proof=try NativeVMLivenessProof(sample:sample,expectedBootHash:permission.bootHash,now:now())
                limit=try cap.capture(liveness:proof);cached=(limit,began)
            }
            let completed=now(),elapsed=uptime()-began
            if completed<stamp {fenced=true}
            previousNow=max(previousNow,completed)
            guard completed>=stamp,completed<leaseUntil,elapsed>=0,elapsed<=5,
                  physical>0,physical<=UInt64(ActivityPolicy.maximumTimestamp),limit.bytes>0,limit.bytes<=physical,
                  sample.total>0,sample.total<=physical,sample.free<=sample.total,
                  sample.sampledAt>=0,limit.sampledAt>=0,
                  sample.sampledAt<=ActivityPolicy.maximumTimestamp,limit.sampledAt<=ActivityPolicy.maximumTimestamp,
                  completed<=ActivityPolicy.maximumTimestamp,
                  (-1000...5000).contains(completed-sample.sampledAt),(-1000...5000).contains(completed-limit.sampledAt) else {throw RuntimeError.identity}
            let identity=["fios-shared-vm-kernel-v1",permission.nativeProfileHash,permission.reviewDigest,permission.bootHash,String(limit.bytes),String(physical)]
            let hash=SHA256.hash(data:Data(identity.joined(separator:"\0").utf8)).map {String(format:"%02x",$0)}.joined()
            let value=VMResourceObservation(runtimeHash:hash,sampledAt:min(sample.sampledAt,limit.sampledAt),configuredCap:limit.bytes,
                total:sample.total,free:sample.free,allVMConsumersCovered:true)
            guard VMResources.remaining(value,expectedRuntimeHash:hash,now:completed) != nil else {throw RuntimeError.identity}
            sample.envelope=value;return sample
        }catch {cached=nil;throw error}
    }
}
