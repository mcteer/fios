import Foundation

// Trusted code-only composition. Production uses the opaque root-enrolled
// factory; synthetic kernel/cap implementations are isolated test inputs.
// The first epoch comes only from the authenticated owned-target reader, not
// policy JSON or a caller's asserted boot. No create/start/retry authority.
final class VMResourceProfileReader:VMResourceReading,@unchecked Sendable {
    private let kernel:any VMResourceReading
    private let cap:any NativeVMCapReading
    private let profileHash:String
    private let reviewDigest:String
    private let physical:UInt64
    private let now:@Sendable()->Int64
    private let uptime:@Sendable()->TimeInterval
    private let lock=NSLock()
    private var bound:SharedKernelVMReader?
    private var previous:Int64 = -1
    private var fenced=false
    init(kernel:any VMResourceReading,cap:any NativeVMCapReading,profileHash:String,reviewDigest:String,physical:UInt64,
         now:@escaping @Sendable()->Int64=HostResources.nowMilliseconds,
         uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {
        self.kernel=kernel;self.cap=cap;self.profileHash=profileHash;self.reviewDigest=reviewDigest;self.physical=physical
        self.now=now;self.uptime=uptime
    }
    func releaseAfterVerifiedAbsence(id:String) {
        // This callback runs on the lifecycle loop. Never wait for the
        // off-loop capture lock; the immutable raw reader owns target fences.
        // The global cap cache and epoch/clock fences remain untouched.
        kernel.releaseAfterVerifiedAbsence(id:id)
    }
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        lock.lock();defer{lock.unlock()}
        let stamp=now(),began=uptime()
        guard !fenced,stamp>=0,stamp<=ActivityPolicy.maximumTimestamp,stamp>=previous,began.isFinite,began>=0 else {fenced=true;throw RuntimeError.identity}
        previous=stamp
        guard physical>0,physical<=UInt64(ActivityPolicy.maximumTimestamp),WireScalar.sha256(profileHash),WireScalar.sha256(reviewDigest),
              leaseUntil<=ActivityPolicy.maximumTimestamp,leaseUntil>stamp,leaseUntil-stamp>=5000 else {throw RuntimeError.deadline}
        var bootstrap:(sample:VMKernelSample,wall:Int64,tick:TimeInterval)?
        if bound==nil {
            let first=try kernel.read(configuration:configuration,id:id,leaseUntil:leaseUntil)
            let completed=now()
            guard completed>=stamp else {fenced=true;throw RuntimeError.identity}
            previous=max(previous,completed)
            let permission=try SharedVMKernelPermission(nativeProfileHash:profileHash,bootHash:first.bootHash,reviewDigest:reviewDigest)
            bootstrap=(first,stamp,began)
            // Keep the exact inner instance on every failure; a later call may
            // never reset its clock/boot/uncertainty fence or its cap cache.
            bound=SharedKernelVMReader(kernel:kernel,cap:cap,permission:permission,physical:physical,now:now,uptime:uptime)
        }
        let result=try bound!.read(configuration:configuration,id:id,leaseUntil:leaseUntil,first:bootstrap)
        let completed=now(),elapsed=uptime()-began
        guard completed>=previous else {fenced=true;throw RuntimeError.identity}
        previous=completed
        guard elapsed>=0,elapsed<=5,completed<leaseUntil else {throw RuntimeError.deadline}
        return result
    }
}
