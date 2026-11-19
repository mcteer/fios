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
protocol NativeVMCapReading:Sendable {
    func capture(liveness:NativeVMLivenessProof,checkpoint:()throws->Void)throws->NativeVMCap
}
struct VerifiedVMCap:NativeVMCapReading {
    let executable:VerifiedExecutable
    let home:String
    func capture(liveness:NativeVMLivenessProof,checkpoint:()throws->Void)throws->NativeVMCap {
        let began=ProcessInfo.processInfo.systemUptime,sampledAt=HostResources.nowMilliseconds()
        // Fresh verified global-kernel observation proves this exact VM is
        // already running; do not spawn a redundant status CLI or start it.
        guard sampledAt>=liveness.sampledAt,sampledAt-liveness.sampledAt<=1000 else {throw RuntimeError.identity}
        let environment=["HOME":home]
        let result=try executable.runChecked(arguments:["config","get","memory_mib"],timeout:1,maximumOutput:64,environment:environment,checkpoint:{
            try checkpoint()
            let wall=HostResources.nowMilliseconds()
            guard wall>=sampledAt,wall-liveness.sampledAt<=1000 else {throw RuntimeError.deadline}
        })
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
    private var previousUptime:TimeInterval = 0
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
        try read(configuration:configuration,id:id,leaseUntil:leaseUntil,first:nil)
    }
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64,
              first:(sample:VMKernelSample,wall:Int64,tick:TimeInterval)?)throws->VMKernelSample {
        lock.lock();defer{lock.unlock()}
        // Only the bound profile's first call can carry its already-read
        // authenticated sample and original wall/monotonic window.
        guard first==nil || previousNow == -1 else {throw RuntimeError.identity}
        let began=first?.tick ?? uptime(),stamp=first?.wall ?? now()
        guard !fenced,stamp>=0,stamp<=ActivityPolicy.maximumTimestamp,stamp>=previousNow,
              began.isFinite,began>=previousUptime else {fenced=true;cached=nil;throw RuntimeError.identity}
        previousNow=stamp;previousUptime=began
        guard physical>0,physical<=UInt64(ActivityPolicy.maximumTimestamp),leaseUntil<=ActivityPolicy.maximumTimestamp,
              leaseUntil>stamp,leaseUntil-stamp>=5000 else {cached=nil;throw RuntimeError.deadline}
        do {
            var sample=try first?.sample ?? kernel.read(configuration:configuration,id:id,leaseUntil:leaseUntil)
            guard sample.bootHash==permission.bootHash else {fenced=true;throw RuntimeError.identity}
            let readCompleted=now(),readUptime=uptime()
            guard readCompleted>=stamp,readCompleted<=ActivityPolicy.maximumTimestamp,
                  readUptime.isFinite,readUptime>=began else {fenced=true;throw RuntimeError.identity}
            previousNow=readCompleted;previousUptime=readUptime
            guard readUptime-began<=5,(stamp...readCompleted).contains(sample.sampledAt) else {throw RuntimeError.identity}
            guard readCompleted<leaseUntil else {throw RuntimeError.deadline}
            let limit:NativeVMCap
            let reusedAt:TimeInterval?
            if let cached,readUptime-cached.uptime<3 {limit=cached.value;reusedAt=cached.uptime}
            else {
                reusedAt=nil
                let proof=try NativeVMLivenessProof(sample:sample,expectedBootHash:permission.bootHash,now:readCompleted)
                limit=try cap.capture(liveness:proof,checkpoint:{
                    let wall=now(),tick=uptime()
                    guard (previousNow...ActivityPolicy.maximumTimestamp).contains(wall),tick.isFinite,tick>=previousUptime else {
                        fenced=true;throw RuntimeError.identity
                    }
                    previousNow=wall;previousUptime=tick
                    guard wall<leaseUntil,tick-began<=5,wall-proof.sampledAt<=1000 else {throw RuntimeError.deadline}
                });cached=(limit,began)
            }
            let completed=now(),completedUptime=uptime()
            guard completed>=previousNow,completed<=ActivityPolicy.maximumTimestamp,
                  completedUptime.isFinite,completedUptime>=previousUptime else {fenced=true;throw RuntimeError.identity}
            previousNow=completed;previousUptime=completedUptime
            guard completed<leaseUntil,completedUptime-began<=5,
                  reusedAt.map({completedUptime-$0<3}) ?? true,
                  physical>0,physical<=UInt64(ActivityPolicy.maximumTimestamp),limit.bytes>0,limit.bytes<=physical,
                  sample.total>0,sample.total<=physical,sample.free<=sample.total,
                  sample.sampledAt>=0,limit.sampledAt>=0,
                  sample.sampledAt<=ActivityPolicy.maximumTimestamp,limit.sampledAt<=ActivityPolicy.maximumTimestamp,
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
