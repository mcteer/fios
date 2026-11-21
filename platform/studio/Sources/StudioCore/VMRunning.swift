import Foundation

// Trusted code-only observation, not a lease, absence/idle proof or authority
// to start/stop anything. No task/control JSON decodes this type.
struct VMRunningProof:Sendable {
    let sourceSHA256:String
    let sampledAt:Int64
    func validate(expectedSHA256:String,now:Int64)throws {
        guard WireScalar.sha256(expectedSHA256),sourceSHA256==expectedSHA256,
              sampledAt>=0,sampledAt<=ActivityPolicy.maximumTimestamp,now>=0,now<=ActivityPolicy.maximumTimestamp else {throw RuntimeError.identity}
        guard (-1000...5000).contains(now-sampledAt) else {throw RuntimeError.deadline}
    }
}
protocol VMRunningReading:Sendable {func capture()throws->VMRunningProof}
struct VerifiedVMRunningProbe:VMRunningReading {
    let executable:VerifiedExecutable
    let home:String
    static func isRunning(_ result:CommandResult)->Bool {result.status==0 && result.output==Data("Running\n".utf8)}
    func capture()throws->VMRunningProof {
        let began=ProcessInfo.processInfo.systemUptime,stamp=HostResources.nowMilliseconds()
        guard stamp>=0,stamp<=ActivityPolicy.maximumTimestamp else {throw RuntimeError.identity}
        let result=try executable.run(arguments:["status"],timeout:1,maximumOutput:64,environment:["HOME":home])
        guard Self.isRunning(result) else {throw RuntimeError.launch} // Unknown, NEVER proven absent.
        try executable.verify(deadline:began+2)
        guard HostResources.nowMilliseconds()>=stamp else {throw RuntimeError.identity}
        guard ProcessInfo.processInfo.systemUptime-began<=2 else {throw RuntimeError.deadline}
        return VMRunningProof(sourceSHA256:executable.sha256,sampledAt:stamp)
    }
}

// Off-loop prerequisite gate. Readiness is sampled; this is NOT an atomic
// no-start/stop reservation. Public wiring still requires reviewed transport
// and lifecycle behavior. Only fixed metadata reads are delegated.
final class RunningVMResourceReader:VMResourceReading,@unchecked Sendable {
    private let kernel:any VMResourceReading
    private let running:any VMRunningReading
    private let expectedCLIHash:String
    private let now:@Sendable()->Int64
    private let uptime:@Sendable()->TimeInterval
    private let lock=NSLock()
    private var previous:Int64 = -1
    private var fenced=false
    init(kernel:any VMResourceReading,running:any VMRunningReading,expectedCLIHash:String,
         now:@escaping @Sendable()->Int64=HostResources.nowMilliseconds,
         uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {
        self.kernel=kernel;self.running=running;self.expectedCLIHash=expectedCLIHash;self.now=now;self.uptime=uptime
    }
    func releaseAfterVerifiedAbsence(id:String) {kernel.releaseAfterVerifiedAbsence(id:id)}
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        lock.lock();defer {lock.unlock()}
        let stamp=now(),began=uptime()
        guard !fenced,stamp>=0,stamp<=ActivityPolicy.maximumTimestamp,stamp>=previous,began.isFinite,began>=0,
              WireScalar.sha256(expectedCLIHash) else {fenced=true;throw RuntimeError.identity}
        previous=stamp
        guard leaseUntil<=ActivityPolicy.maximumTimestamp,leaseUntil>stamp,leaseUntil-stamp>=5000 else {throw RuntimeError.deadline}
        do {
            let proof=try running.capture(),before=now()
            guard before>=previous else {throw RuntimeError.identity}
            previous=before
            try proof.validate(expectedSHA256:expectedCLIHash,now:before)
            let sample=try kernel.read(configuration:configuration,id:id,leaseUntil:leaseUntil)
            let completed=now(),elapsed=uptime()-began
            guard completed>=previous else {throw RuntimeError.identity}
            previous=completed
            try proof.validate(expectedSHA256:expectedCLIHash,now:completed)
            guard elapsed>=0,elapsed<=5,completed<leaseUntil else {throw RuntimeError.deadline}
            return sample
        } catch {
            let completed=now()
            if completed<previous {fenced=true}
            previous=max(previous,completed)
            if case RuntimeError.identity=error {fenced=true}
            throw error
        }
    }
}
