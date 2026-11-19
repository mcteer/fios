import Foundation

func runResourceObservationTests() throws {
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
    let zeroVM=try frame(10000,sample.replacingVM(0,sampledAt:10000))
    guard zeroVM.resources["vmAvailable"] as? UInt64==0,quality(zeroVM,"vm_available")=="observed" else {fatalError("Observed zero VM capacity lost")}
    let invalid=ResourceSample(sampledAt:10000,physical:64<<30,available:65<<30,vmAvailable:nil,diskFree:UInt64.max,cpu:.nan,pressure:.unknown,thermal:.unknown)
    let rejected=try frame(10000,invalid)
    guard rejected.resources["available"] is NSNull,rejected.resources["diskFree"] is NSNull,rejected.resources["cpu"] is NSNull else {fatalError("Invalid/noninteroperable signal published")}
    let bytes=try JSONSerialization.data(withJSONObject:["resources":rejected.resources,"resource_observation":rejected.observation])
    guard bytes.count<8192 else {fatalError("Resource export exceeded bounded metadata")}
    print("PASS: per-signal age/availability, independent host/GPU/VM timing, exact freshness edges, observed zero/power and invalid/unbound capacity refusal; no native-idle authority")
}
