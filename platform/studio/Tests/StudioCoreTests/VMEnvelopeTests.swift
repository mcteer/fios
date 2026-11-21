import Foundation

func runVMEnvelopeTests() throws {
    let profile=String(repeating:"a",count:64),boot=String(repeating:"b",count:64),machine=String(repeating:"c",count:64)
    func context(cap:UInt64=12<<30,configurationAt:Int64=1000,beforeAt:Int64=1000,afterAt:Int64=1000,before:Set<String>=[],after:Set<String>=[],kernels:[VMMachineKernel]=[])->VMEnvelopeContext {
        VMEnvelopeContext(nativeProfileHash:profile,expectedBootHash:boot,configuredCap:cap,physical:32<<30,configurationSampledAt:configurationAt,topologyBeforeAt:beforeAt,topologyAfterAt:afterAt,machineIDsBefore:before,machineIDsAfter:after,machineKernels:kernels)
    }
    let sample=VMKernelSample(sampledAt:1000,total:16<<30,free:8<<30,bootHash:boot)
    guard let value=VMEnvelope.observation(sample,context:context(),now:1000),VMResources.remaining(value,expectedRuntimeHash:value.runtimeHash,now:1000)==4<<30 else {fatalError("Empty-inventory complete VM envelope refused")}
    guard VMEnvelope.observation(sample,context:context(configurationAt:0),now:5001)==nil,
          VMEnvelope.observation(sample,context:context(before:[machine]),now:1000)==nil,
          VMEnvelope.observation(sample,context:context(before:[machine],after:[machine]),now:1000)==nil,
          VMEnvelope.observation(sample,context:context(before:[machine],after:[machine],kernels:[VMMachineKernel(identityHash:machine,bootHash:profile,sampledAt:1000)]),now:1000)==nil,
          VMEnvelope.observation(VMKernelSample(sampledAt:1000,total:16<<30,free:8<<30,bootHash:profile),context:context(),now:1000)==nil else {fatalError("Partial/stale/foreign-VM envelope accepted")}
    guard VMEnvelope.observation(sample,context:context(beforeAt:1001,afterAt:999),now:1001)==nil,
          VMEnvelope.observation(sample,context:context(beforeAt:1001,afterAt:1002),now:1002)==nil,
          VMEnvelope.observation(sample,context:context(beforeAt:998,afterAt:999),now:1000)==nil,
          let bracketed=VMEnvelope.observation(sample,context:context(beforeAt:999,afterAt:1001),now:1001),
          bracketed.sampledAt==999,bracketed.runtimeHash==value.runtimeHash else {fatalError("VM topology reads did not bracket the original kernel sample")}
    for (stamp,accepted) in [(1000,true),(999,false),(7000,true),(7001,false)] {
        let kernel=VMKernelSample(sampledAt:6000,total:16<<30,free:8<<30,bootHash:boot)
        let config=VMEnvelope.observation(kernel,context:context(configurationAt:Int64(stamp),beforeAt:6000,afterAt:6000),now:6000)
        let machineEnvelope=VMEnvelope.observation(kernel,context:context(configurationAt:6000,beforeAt:6000,afterAt:6000,
            before:[machine],after:[machine],kernels:[VMMachineKernel(identityHash:machine,bootHash:boot,sampledAt:Int64(stamp))]),now:6000)
        guard (config != nil)==accepted,(machineEnvelope != nil)==accepted,
              !accepted || (config?.sampledAt==Int64(min(stamp,6000)) && machineEnvelope?.sampledAt==Int64(min(stamp,6000))) else {
            fatalError("VM configuration and machine kernel freshness failed independent bounds")
        }
    }
    guard let shared=VMEnvelope.observation(sample,context:context(before:[machine],after:[machine],kernels:[VMMachineKernel(identityHash:machine,bootHash:boot,sampledAt:1000)]),now:1000),shared.runtimeHash != value.runtimeHash,
          let changed=VMEnvelope.observation(sample,context:context(cap:10<<30),now:1000),changed.runtimeHash != value.runtimeHash,
          VMResources.remaining(value,expectedRuntimeHash:changed.runtimeHash,now:1000)==nil else {fatalError("VM cap/topology identity not fenced")}
    print("PASS: VM envelope binds native profile/kernel/cap/physical/topology, requires every running machine's fresh same-kernel proof and rejects stale/foreign/partial capacity")
}
