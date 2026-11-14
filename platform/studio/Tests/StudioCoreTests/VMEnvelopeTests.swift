import Foundation

func runVMEnvelopeTests() throws {
    let profile=String(repeating:"a",count:64),boot=String(repeating:"b",count:64),machine=String(repeating:"c",count:64)
    func context(cap:UInt64=12<<30,configurationAt:Int64=1000,before:Set<String>=[],after:Set<String>=[],kernels:[VMMachineKernel]=[])->VMEnvelopeContext {
        VMEnvelopeContext(nativeProfileHash:profile,expectedBootHash:boot,configuredCap:cap,physical:32<<30,configurationSampledAt:configurationAt,topologyBeforeAt:1000,topologyAfterAt:1000,machineIDsBefore:before,machineIDsAfter:after,machineKernels:kernels)
    }
    let sample=VMKernelSample(sampledAt:1000,total:16<<30,free:8<<30,bootHash:boot)
    guard let value=VMEnvelope.observation(sample,context:context(),now:1000),VMResources.remaining(value,expectedRuntimeHash:value.runtimeHash,now:1000)==4<<30 else {fatalError("Empty-inventory complete VM envelope refused")}
    guard VMEnvelope.observation(sample,context:context(configurationAt:0),now:5001)==nil,
          VMEnvelope.observation(sample,context:context(before:[machine]),now:1000)==nil,
          VMEnvelope.observation(sample,context:context(before:[machine],after:[machine]),now:1000)==nil,
          VMEnvelope.observation(sample,context:context(before:[machine],after:[machine],kernels:[VMMachineKernel(identityHash:machine,bootHash:profile,sampledAt:1000)]),now:1000)==nil,
          VMEnvelope.observation(VMKernelSample(sampledAt:1000,total:16<<30,free:8<<30,bootHash:profile),context:context(),now:1000)==nil else {fatalError("Partial/stale/foreign-VM envelope accepted")}
    guard let shared=VMEnvelope.observation(sample,context:context(before:[machine],after:[machine],kernels:[VMMachineKernel(identityHash:machine,bootHash:boot,sampledAt:1000)]),now:1000),shared.runtimeHash != value.runtimeHash,
          let changed=VMEnvelope.observation(sample,context:context(cap:10<<30),now:1000),changed.runtimeHash != value.runtimeHash,
          VMResources.remaining(value,expectedRuntimeHash:changed.runtimeHash,now:1000)==nil else {fatalError("VM cap/topology identity not fenced")}
    print("PASS: VM envelope binds native profile/kernel/cap/physical/topology, requires every running machine's fresh same-kernel proof and rejects stale/foreign/partial capacity")
}
