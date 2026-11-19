import Foundation

struct NativeVMInventory:Sendable {
    let configuredCap:UInt64
    let sampledAt:Int64
    let machineIDs:Set<String>
}
protocol NativeVMInventoryReading:Sendable {
    func capture(checkpoint:()throws->Void)throws->NativeVMInventory
}
extension NativeVMInventoryReading {
    func capture()throws->NativeVMInventory {try capture(checkpoint:{})}
}
// Only a reviewed native profile supplies the canonical, identity-pinned CLI.
// Fixed documented read-only operations; no start/run/ssh/config-set fallback.
struct VerifiedVMInventory:NativeVMInventoryReading {
    let executable:VerifiedExecutable
    let home:String
    func capture(checkpoint:()throws->Void)throws->NativeVMInventory {
        let began=ProcessInfo.processInfo.systemUptime,sampledAt=HostResources.nowMilliseconds()
        let environment=["HOME":home]
        func command(_ arguments:[String],maximumOutput:Int)throws->CommandResult {
            let remaining=5-(ProcessInfo.processInfo.systemUptime-began)
            guard remaining>0 else {throw RuntimeError.deadline}
            return try executable.runChecked(arguments:arguments,timeout:min(1,remaining),maximumOutput:maximumOutput,
                environment:environment,checkpoint:checkpoint)
        }
        let status=try command(["status"],maximumOutput:64)
        guard VerifiedVMRunningProbe.isRunning(status) else {throw RuntimeError.launch}
        let config=try command(["config","get","memory_mib"],maximumOutput:64)
        guard config.status==0,let text=String(data:config.output,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines),
              !text.isEmpty,text.utf8.count<=8,text.first != "0",text.utf8.allSatisfy({(48...57).contains($0)}),
              let mib=UInt64(text),mib<=UInt64(ActivityPolicy.maximumTimestamp)/(1<<20) else {throw RuntimeError.invalid}
        let inventory=try command(["list","--format","json"],maximumOutput:65536)
        guard inventory.status==0 else {throw RuntimeError.launch}
        try StrictJSON.validate(inventory.output,maximum:65536)
        // Inspect ALL configured machines, not just running: starting/stopping
        // states must not silently disappear from capacity coverage.
        // Nonempty inventory needs separately acquired same-kernel/state proofs.
        // Do not invent coverage from counts or parse unreviewed item schemas.
        guard let machines=try JSONSerialization.jsonObject(with:inventory.output) as? [Any],machines.isEmpty,
              ProcessInfo.processInfo.systemUptime-began<=5 else {throw RuntimeError.identity}
        return NativeVMInventory(configuredCap:mib*(1<<20),sampledAt:sampledAt,machineIDs:[])
    }
}

// Runs as ONE shared SandboxExecutor operation: native queries and kernel read
// are sequential, never additional independent subprocess slots. Not enabled
// by task JSON or the observation-only manager's default composition.
struct VMEnvelopeReader:VMResourceReading {
    let kernel:any VMResourceReading
    let inventory:any NativeVMInventoryReading
    let nativeProfileHash:String
    let physical:UInt64
    var wallClock:@Sendable ()->Int64 = {HostResources.nowMilliseconds()}
    var uptime:@Sendable ()->TimeInterval = {ProcessInfo.processInfo.systemUptime}
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        let began=uptime()
        var previousWall:Int64 = 0,previousUptime=began
        func checkpoint()throws->Int64 {
            let now=wallClock(),steady=uptime()
            guard (0...WireScalar.maximumTimestamp).contains(now),now>=previousWall,
                  began.isFinite,began>=0,steady.isFinite,steady>=previousUptime else {throw RuntimeError.identity}
            guard leaseUntil<=WireScalar.maximumTimestamp,now<leaseUntil,steady-began<=5 else {throw RuntimeError.deadline}
            previousWall=now;previousUptime=steady
            return now
        }
        _=try checkpoint()
        let first=try inventory.capture(checkpoint:{_=try checkpoint()})
        func firstFresh(at time:Int64)throws {
            guard (0...WireScalar.maximumTimestamp).contains(first.sampledAt),
                  (-1000...5000).contains(time-first.sampledAt) else {throw RuntimeError.identity}
        }
        try firstFresh(at:checkpoint())
        var sample=try kernel.read(configuration:configuration,id:id,leaseUntil:leaseUntil)
        try firstFresh(at:checkpoint())
        let last=try inventory.capture(checkpoint:{try firstFresh(at:checkpoint())}),now=try checkpoint()
        guard first.configuredCap==last.configuredCap else {throw RuntimeError.identity}
        let context=VMEnvelopeContext(nativeProfileHash:nativeProfileHash,expectedBootHash:sample.bootHash,
            configuredCap:first.configuredCap,physical:physical,configurationSampledAt:min(first.sampledAt,last.sampledAt),
            topologyBeforeAt:first.sampledAt,topologyAfterAt:last.sampledAt,machineIDsBefore:first.machineIDs,machineIDsAfter:last.machineIDs,machineKernels:[])
        guard let envelope=VMEnvelope.observation(sample,context:context,now:now) else {throw RuntimeError.identity}
        sample.envelope=envelope
        return sample
    }
    func releaseAfterVerifiedAbsence(id:String) {kernel.releaseAfterVerifiedAbsence(id:id)}
}
