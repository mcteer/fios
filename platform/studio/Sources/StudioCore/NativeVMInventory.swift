import Foundation

struct NativeVMInventory:Sendable {
    let configuredCap:UInt64
    let sampledAt:Int64
    let machineIDs:Set<String>
}
protocol NativeVMInventoryReading:Sendable {
    func capture()throws->NativeVMInventory
}
// Only a reviewed native profile supplies the canonical, identity-pinned CLI.
// Fixed documented read-only operations; no start/run/ssh/config-set fallback.
struct VerifiedVMInventory:NativeVMInventoryReading {
    let executable:VerifiedExecutable
    let home:String
    func capture()throws->NativeVMInventory {
        let began=ProcessInfo.processInfo.systemUptime,sampledAt=HostResources.nowMilliseconds()
        let environment=["HOME":home]
        let status=try executable.run(arguments:["status"],timeout:1,maximumOutput:64,environment:environment)
        guard status.status==0 else {throw RuntimeError.launch}
        let config=try executable.run(arguments:["config","get","memory_mib"],timeout:1,maximumOutput:64,environment:environment)
        guard config.status==0,let text=String(data:config.output,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines),
              !text.isEmpty,text.utf8.count<=8,text.first != "0",text.utf8.allSatisfy({(48...57).contains($0)}),
              let mib=UInt64(text),mib<=UInt64(ActivityPolicy.maximumTimestamp)/(1<<20) else {throw RuntimeError.invalid}
        let inventory=try executable.run(arguments:["list","--format","json"],timeout:1,maximumOutput:65536,environment:environment)
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
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        let began=ProcessInfo.processInfo.systemUptime,first=try inventory.capture()
        var sample=try kernel.read(configuration:configuration,id:id,leaseUntil:leaseUntil)
        let last=try inventory.capture(),now=HostResources.nowMilliseconds()
        guard first.configuredCap==last.configuredCap,ProcessInfo.processInfo.systemUptime-began<=5,now<leaseUntil else {throw RuntimeError.identity}
        let context=VMEnvelopeContext(nativeProfileHash:nativeProfileHash,expectedBootHash:sample.bootHash,
            configuredCap:first.configuredCap,physical:physical,configurationSampledAt:min(first.sampledAt,last.sampledAt),
            topologyBeforeAt:first.sampledAt,topologyAfterAt:last.sampledAt,machineIDsBefore:first.machineIDs,machineIDsAfter:last.machineIDs,machineKernels:[])
        guard let envelope=VMEnvelope.observation(sample,context:context,now:now) else {throw RuntimeError.identity}
        sample.envelope=envelope
        return sample
    }
    func releaseAfterVerifiedAbsence(id:String) {kernel.releaseAfterVerifiedAbsence(id:id)}
}
