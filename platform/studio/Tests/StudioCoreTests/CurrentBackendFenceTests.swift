import Foundation
func runCurrentBackendFenceWireTests(nativeFrame:String?=nil,backgroundFrame:String?=nil)throws {
    try runBackgroundCoverageWireTests()
    let instance=String(repeating:"07",count:16),request=try NativeBackendFenceWire.currentRequest(instance:instance)
    guard request.count==32,request.prefix(5)==Data("FIB9".utf8)+Data([2]) else {fatalError("Current backend request version changed")}
    var frame=Data(repeating:0,count:64);frame.replaceSubrange(0..<4,with:Data("FIF9".utf8));frame[4]=2;frame[6]=127
    frame.replaceSubrange(8..<24,with:Data(repeating:7,count:16));frame[31]=2;frame[38]=3;frame[39]=232
    for mask in 0..<128 {
        var current=frame;current[7]=UInt8(mask)
        let value=try NativeBackendFenceWire.currentReply(current,instance:instance,after:1)
        guard value.current==NativeCurrentBackendFlags(available:127,uncertain:UInt8(mask)),value.mimoWarmUncertain==nil,value.ds4MetalUncertainty==nil,value.ds4HostUncertainty==nil else {fatalError("Current flags were aliased to another native ABI")}
    }
    func invalid(_ data:Data)throws {do {_=try NativeBackendFenceWire.currentReply(data,instance:instance);fatalError("Invalid current flag frame accepted")}catch NativeControlError.invalid {}}
    for offset in [4,5,6,7,8,40,43,48,63] {var bad=frame;bad[offset]=255;try invalid(bad)}
    var absent=frame;absent[6]=0;absent[7]=1;try invalid(absent)
    try invalid(Data(frame.dropLast()))
    do {_=try NativeBackendFenceWire.reply(frame,instance:instance);fatalError("Current flags reinterpreted as legacy")}catch NativeControlError.invalid {}
    do {_=try NativeBackendFenceWire.currentReply(frame,instance:instance,after:2);fatalError("Current source replay accepted")}catch NativeControlError.invalid {}
    let peer=NativeControlPeer(pid:42,start:100,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"a",count:64)))
    func sample(_ mask:UInt8,_ available:UInt8,_ sequence:UInt8)throws->NativeBackendFenceSample {
        var data=frame;data[6]=available;data[7]=mask;data[31]=sequence
        return NativeBackendFenceSample(peer:peer,receivedAt:1000,fences:try NativeBackendFenceWire.currentReply(data,instance:instance))
    }
    var diagnostic=NativeBackendFenceDiagnostics(configured:true)
    diagnostic.completed(try sample(64,65,2),expectedInstance:instance,now:1000)
    let summary=diagnostic.summary(now:1000),sources=summary["current_sources"] as? [String:Any]
    guard summary["state"] as? String=="received",summary["frame_version"] as? Int==2,
          summary["coverage"] as? String=="unknown",summary["authority"] as? Bool==false,
          sources?["sdk_uncertain"] as? Bool==false,sources?["ane_native_uncertain"] as? Bool==true,
          sources?["llama_uncertain"] is NSNull,summary["retained_uncertainty"] as? Bool==true else {fatalError("Current source absence or independent uncertainty was lost")}
    diagnostic.failed()
    diagnostic.completed(try sample(0,65,3),expectedInstance:instance,now:1000)
    guard diagnostic.summary(now:1000)["state"] as? String=="fenced",diagnostic.summary(now:1000)["retained_uncertainty"] as? Bool==true else {fatalError("New successful flags cleared earlier independent uncertainty")}
    var unavailable=NativeBackendFenceDiagnostics(configured:true)
    unavailable.completed(try sample(0,0,2),expectedInstance:instance,now:1000)
    guard unavailable.summary(now:1000)["state"] as? String=="unavailable" else {fatalError("Compiled-out sources became available zeros")}
    var changed=NativeBackendFenceDiagnostics(configured:true)
    changed.completed(try sample(0,127,2),expectedInstance:instance,now:1000)
    changed.completed(try sample(0,65,3),expectedInstance:instance,now:1000)
    guard changed.summary(now:1000)["state"] as? String=="fenced" else {fatalError("Compiled source availability changed within one epoch")}
    var legacy=frame;legacy[4]=1;legacy[6]=0;legacy[31]=3
    var format=NativeBackendFenceDiagnostics(configured:true);format.completed(try sample(0,127,2),expectedInstance:instance,now:1000)
    format.completed(NativeBackendFenceSample(peer:peer,receivedAt:1000,fences:try NativeBackendFenceWire.reply(legacy,instance:instance)),expectedInstance:instance,now:1000)
    guard format.summary(now:1000)["state"] as? String=="fenced" else {fatalError("Backend flag ABI changed within one epoch")}
    if let nativeFrame {
        let value=try NativeBackendFenceWire.currentReply(Data(contentsOf:URL(fileURLWithPath:nativeFrame)),instance:String(repeating:"79",count:16))
        guard value.current==NativeCurrentBackendFlags(available:127,uncertain:127) else {fatalError("Actual native flag frame disagreed with manager")}
    }
    if let backgroundFrame {
        let value=try NativeBackendFenceWire.backgroundReply(Data(contentsOf:URL(fileURLWithPath:backgroundFrame)),instance:String(repeating:"79",count:16))
        guard value.current==NativeCurrentBackendFlags(available:1,uncertain:0),
              value.backgroundCoverage?.sdkResidencyRefreshUntracked==true else {fatalError("Actual native background frame disagreed with manager")}
    }
}

private func runBackgroundCoverageWireTests()throws {
    let instance=String(repeating:"07",count:16)
    guard try NativeBackendFenceWire.backgroundRequest(instance:instance)[4]==3 else {throw NativeControlError.invalid}
    var frame=Data(repeating:0,count:64);frame.replaceSubrange(0..<4,with:Data("FIF9".utf8));frame[4]=3;frame[6]=127
    frame.replaceSubrange(8..<24,with:Data(repeating:7,count:16));frame[31]=2;frame[38]=3;frame[39]=232
    let peer=NativeControlPeer(pid:42,start:100,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"a",count:64)))
    func sample(_ code:UInt8,_ sequence:UInt8=2)throws->NativeBackendFenceSample {
        var data=frame;data[40]=code;data[31]=sequence
        return NativeBackendFenceSample(peer:peer,receivedAt:1000,fences:try NativeBackendFenceWire.backgroundReply(data,instance:instance))
    }
    for code:UInt8 in [0,1,2] {
        let value=try sample(code)
        guard value.fences.backgroundCoverage != nil,
              value.fences.backgroundCoverage?.sdkResidencyRefreshUntracked==(code==0 ? nil:code==2),
              value.fences.current?.uncertain==0 else {fatalError("Background coverage was confused with cleanup failure")}
    }
    for (offset,value) in [(40,UInt8(3)),(41,1),(63,1),(4,2)] {
        var bad=frame;bad[offset]=value
        do {_=try NativeBackendFenceWire.backgroundReply(bad,instance:instance);fatalError("Malformed background frame accepted")}
        catch NativeControlError.invalid {}
    }
    do {_=try NativeBackendFenceWire.currentReply(frame,instance:instance);fatalError("Background frame silently fell back to v2")}
    catch NativeControlError.invalid {}
    var diagnostics=NativeBackendFenceDiagnostics(configured:true,observeBackground:true)
    diagnostics.completed(try sample(1),expectedInstance:instance,now:1000)
    diagnostics.completed(try sample(2,3),expectedInstance:instance,now:1000)
    let observed=diagnostics.summary(now:1000),background=observed["source_background"] as? [String:Any]
    guard observed["frame_version"] as? Int==3,observed["retained_uncertainty"] as? Bool==false,
          observed["retained_coverage_gap"] as? Bool==true,background?["sdk_residency_refresh_untracked"] as? Bool==true,
          observed["coverage"] as? String=="unknown",observed["authority"] as? Bool==false else {fatalError("Background gap gained authority or became cleanup failure")}
    diagnostics.failed()
    guard diagnostics.summary(now:1000)["retained_coverage_gap"] as? Bool==true else {fatalError("Missing source cleared prior coverage gap")}
    diagnostics.completed(try sample(1,4),expectedInstance:instance,now:1000)
    guard diagnostics.summary(now:1000)["state"] as? String=="fenced" else {fatalError("Background source regression cleared sticky gap")}
    var unavailable=NativeBackendFenceDiagnostics(configured:true,observeBackground:true)
    unavailable.completed(try sample(0),expectedInstance:instance,now:1000)
    guard (unavailable.summary(now:1000)["source_background"] as? [String:Any])?["sdk_residency_refresh_untracked"] is NSNull else {fatalError("Unavailable background observation became false")}
    var sdkOnly=NativeBackendFenceDiagnostics(configured:true,observeBackground:true)
    func sdkSample(_ uncertain:Bool,_ sequence:UInt8)throws->NativeBackendFenceSample {
        var data=frame;data[6]=1;data[7]=uncertain ? 1:0;data[31]=sequence
        return NativeBackendFenceSample(peer:peer,receivedAt:1000,fences:try NativeBackendFenceWire.backgroundReply(data,instance:instance))
    }
    sdkOnly.completed(try sdkSample(false,2),expectedInstance:instance,now:1000)
    sdkOnly.completed(try sdkSample(true,3),expectedInstance:instance,now:1000)
    let positive=sdkOnly.summary(now:1000),sources=positive["current_sources"] as? [String:Any]
    guard sources?["sdk_uncertain"] as? Bool==true,sources?["llama_uncertain"] is NSNull,
          positive["coverage"] as? String=="unknown",positive["authority"] as? Bool==false,
          positive["retained_uncertainty"] as? Bool==true,positive["retained_coverage_gap"] as? Bool==false else {
        fatalError("Sparse SDK uncertainty gained authority or erased the unknown sources")
    }
    sdkOnly.failed()
    sdkOnly.completed(try sdkSample(false,4),expectedInstance:instance,now:1000)
    guard sdkOnly.summary(now:1000)["state"] as? String=="fenced" else {fatalError("Later SDK false cleared its preceding positive fence")}
    print("PASS: explicit v3 background coverage stays separate from cleanup failure, preserves availability and sticky gaps, no authority or fallback")
}
