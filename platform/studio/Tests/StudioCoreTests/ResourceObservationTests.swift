import Foundation

func runResourceObservationTests() throws {
    let bound=WireScalar.maximumTimestamp
    for invalid in [Int64.min,-1,bound+1,Int64.max] {
        guard ResourceClock.age(now:invalid,sampledAt:10_000)==nil,
              ResourceClock.age(now:10_000,sampledAt:invalid)==nil,
              !ResourceClock.fresh(now:invalid,sampledAt:invalid) else {
            fatalError("Invalid resource consumer or source clock entered age arithmetic")
        }
    }
    guard ResourceClock.age(now:0,sampledAt:bound) == -bound,
          ResourceClock.age(now:bound,sampledAt:0) == bound,
          ResourceClock.fresh(now:bound,sampledAt:bound) else {fatalError("Valid endpoint bounds changed")}
    let epoch=UUID().uuidString.lowercased(),vmEpoch=String(repeating:"a",count:64)
    var sample=ResourceSample(sampledAt:10000,physical:64<<30,available:32<<30,vmAvailable:4<<30,diskFree:100<<30,cpu:0,pressure:.normal,thermal:.nominal,vmSampledAt:10000)
    sample.lowPowerMode=false;sample.cpuSampledAt=10000
    let gpu=GPUResources.decode(["Device Utilization %":0,"In use system memory":0])!
    func frame(_ now:Int64,_ value:ResourceSample?=nil,_ gpuAt:Int64?=10000)throws->ResourceObservationExport.Frame {
        try ResourceObservationExport.encode(sample:value ?? sample,gpu:gpu,gpuSampledAt:gpuAt,now:now,epoch:epoch,sequence:1,vmEpoch:vmEpoch)
    }
    func quality(_ frame:ResourceObservationExport.Frame,_ name:String)->String? {
        ((frame.observation["signals"] as? [String:[String:Any]])?[name])?["availability"] as? String
    }
    let fresh=try frame(10000)
    guard fresh.resources["cpu"] as? Double==0,fresh.resources["gpu"] as? Double==0,
          fresh.resources["lowPowerMode"] as? Bool==false,quality(fresh,"cpu")=="observed",quality(fresh,"vm_available")=="observed",
          sample.replacingVM(nil).lowPowerMode==false else {fatalError("Observed zero/power/VM identity lost")}
    for now:Int64 in [15000,9000] {guard quality(try frame(now),"cpu")=="observed" else {fatalError("Freshness boundary rejected")}}
    for now:Int64 in [15001,8999] {
        let stale=try frame(now)
        guard stale.resources["cpu"] is NSNull,stale.resources["gpu"] is NSNull,
              stale.resources["pressure"] as? String=="unknown",stale.resources["thermal"] as? String=="unknown",
              quality(stale,"cpu")=="stale" else {fatalError("Stale/future signal published as observed")}
    }
    var oldHost=sample;oldHost=ResourceSample(sampledAt:0,physical:oldHost.physical,available:oldHost.available,vmAvailable:oldHost.vmAvailable,diskFree:oldHost.diskFree,cpu:oldHost.cpu,pressure:.normal,thermal:.nominal,vmSampledAt:10000)
    let separate=try frame(10000,oldHost)
    guard separate.resources["cpu"] is NSNull,quality(separate,"gpu")=="observed",quality(separate,"vm_available")=="observed" else {fatalError("Independent signal ages conflated")}
    var undated=sample;undated.cpuSampledAt=nil
    let noCPUClock=try frame(10000,undated)
    guard noCPUClock.resources["cpu"] is NSNull,quality(noCPUClock,"cpu")=="unknown",
          quality(noCPUClock,"available_memory")=="observed" else {fatalError("Undated CPU borrowed fresh host time")}
    var invalidClocks=sample.replacingVM(4<<30,sampledAt:Int64.max)
    invalidClocks.cpuSampledAt=Int64.min
    let badClocks=try frame(10000,invalidClocks,Int64.min)
    let clockSignals=badClocks.observation["signals"] as? [String:[String:Any]]
    for name in ["cpu","vm_available","gpu","gpu_in_use_memory"] {
        guard quality(badClocks,name)=="unknown",clockSignals?[name]?["sampled_at"] is NSNull,
              clockSignals?[name]?["age_ms"] is NSNull else {fatalError("Invalid independent clock reached resource export")}
    }
    guard quality(badClocks,"available_memory")=="observed",badClocks.observation["vm_epoch"] is NSNull else {
        fatalError("Invalid independent clock suppressed valid host sample or retained VM epoch")
    }
    let missingTime=try frame(10000,nil,nil)
    guard missingTime.resources["gpu"] is NSNull,quality(missingTime,"gpu")=="unknown" else {fatalError("Undated GPU counter accepted")}
    let noVM=try ResourceObservationExport.encode(sample:sample,gpu:nil,gpuSampledAt:nil,now:10000,epoch:epoch,sequence:1,vmEpoch:nil)
    guard noVM.resources["vmAvailable"] is NSNull,quality(noVM,"vm_available")=="unknown" else {fatalError("Unbound VM capacity published")}
    for bytes:UInt64 in [(64<<30)+1,UInt64.max] {
        let oversized=try frame(10000,sample.replacingVM(bytes,sampledAt:10000))
        guard oversized.resources["vmAvailable"] is NSNull,quality(oversized,"vm_available")=="unknown",
              oversized.observation["vm_coverage"] as? String=="unknown" else {fatalError("FIO_VM_EXCEEDS_PHYSICAL_EXPORTED")}
    }
    // A current host sample must not refresh a dated VM envelope or its epoch.
    for at:Int64 in [4999,11001] {
        let delayedVM=try frame(10000,sample.replacingVM(4<<30,sampledAt:at))
        guard delayedVM.resources["vmAvailable"] is NSNull,quality(delayedVM,"vm_available")=="stale",
              delayedVM.observation["vm_epoch"] is NSNull,delayedVM.observation["vm_coverage"] as? String=="unknown",
              quality(delayedVM,"available_memory")=="observed" else {fatalError("Stale VM lease observation borrowed current host freshness")}
    }
    var mixed=sample.replacingVM(4<<30,sampledAt:4999)
    mixed.cpuSampledAt=11000
    let independent=try frame(10000,mixed,11001)
    let independentSignals=independent.observation["signals"] as? [String:[String:Any]]
    guard independent.resources["cpu"] as? Double==0,quality(independent,"cpu")=="observed",
          independentSignals?["cpu"]?["age_ms"] as? Int64 == -1000,
          independent.resources["gpu"] is NSNull,quality(independent,"gpu")=="stale",
          independentSignals?["gpu"]?["age_ms"] as? Int64 == -1001,
          independent.resources["vmAvailable"] is NSNull,independent.observation["vm_epoch"] is NSNull,
          independentSignals?["vm_available"]?["age_ms"] as? Int64 == 5001 else {
        fatalError("Mixed resource clocks leaked stale capacity or lost measured zero")
    }
    for (at,age): (Int64,Int64) in [(4999,5001),(11001,-1001)] {
        var delayedCPU=sample.replacingVM(0,sampledAt:5000)
        delayedCPU.cpuSampledAt=at
        let projected=try frame(10000,delayedCPU,11000)
        let signals=projected.observation["signals"] as? [String:[String:Any]]
        guard projected.resources["cpu"] is NSNull,quality(projected,"cpu")=="stale",
              signals?["cpu"]?["sampled_at"] as? Int64==at,signals?["cpu"]?["age_ms"] as? Int64==age,
              projected.resources["gpu"] as? Double==0,quality(projected,"gpu")=="observed",
              projected.resources["vmAvailable"] as? UInt64==0,projected.observation["vm_epoch"] as? String==vmEpoch,
              quality(projected,"available_memory")=="observed" else {
            fatalError("Mixed status refreshed stale CPU or withheld independently fresh signals")
        }
    }
    let zeroVM=try frame(10000,sample.replacingVM(0,sampledAt:10000))
    guard zeroVM.resources["vmAvailable"] as? UInt64==0,quality(zeroVM,"vm_available")=="observed" else {fatalError("Observed zero VM capacity lost")}
    let invalid=ResourceSample(sampledAt:10000,physical:64<<30,available:65<<30,vmAvailable:nil,diskFree:UInt64.max,cpu:.nan,pressure:.unknown,thermal:.unknown)
    let rejected=try frame(10000,invalid)
    guard rejected.resources["available"] is NSNull,rejected.resources["diskFree"] is NSNull,rejected.resources["cpu"] is NSNull else {fatalError("Invalid/noninteroperable signal published")}
    let bytes=try JSONSerialization.data(withJSONObject:["resources":rejected.resources,"resource_observation":rejected.observation])
    guard bytes.count<8192 else {fatalError("Resource export exceeded bounded metadata")}
    print("PASS: per-signal age/availability, independent host/GPU/VM timing, exact freshness edges, observed zero/power and invalid/unbound capacity refusal; no native-idle authority")
}
