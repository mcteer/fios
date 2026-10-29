import Foundation

func runResourceObservationTests() throws {
    let epoch=UUID().uuidString.lowercased(),vmEpoch=String(repeating:"a",count:64)
    var sample=ResourceSample(sampledAt:10000,physical:64<<30,available:32<<30,vmAvailable:4<<30,diskFree:100<<30,cpu:0,pressure:.normal,thermal:.nominal,vmSampledAt:10000)
    sample.lowPowerMode=false
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
    let missingTime=try frame(10000,nil,nil)
    guard missingTime.resources["gpu"] is NSNull,quality(missingTime,"gpu")=="unknown" else {fatalError("Undated GPU counter accepted")}
    let noVM=try ResourceObservationExport.encode(sample:sample,gpu:nil,gpuSampledAt:nil,now:10000,epoch:epoch,sequence:1,vmEpoch:nil)
    guard noVM.resources["vmAvailable"] is NSNull,quality(noVM,"vm_available")=="unknown" else {fatalError("Unbound VM capacity published")}
    let invalid=ResourceSample(sampledAt:10000,physical:64<<30,available:65<<30,vmAvailable:nil,diskFree:UInt64.max,cpu:.nan,pressure:.unknown,thermal:.unknown)
    let rejected=try frame(10000,invalid)
    guard rejected.resources["available"] is NSNull,rejected.resources["diskFree"] is NSNull,rejected.resources["cpu"] is NSNull else {fatalError("Invalid/noninteroperable signal published")}
    let bytes=try JSONSerialization.data(withJSONObject:["resources":rejected.resources,"resource_observation":rejected.observation])
    guard bytes.count<8192 else {fatalError("Resource export exceeded bounded metadata")}
    print("PASS: per-signal age/availability, independent host/GPU/VM timing, exact freshness edges, observed zero/power and invalid/unbound capacity refusal; no native-idle authority")
}
