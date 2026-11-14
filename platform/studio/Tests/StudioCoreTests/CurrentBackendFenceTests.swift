import Foundation
func runCurrentBackendFenceWireTests(nativeFrame:String?=nil)throws {
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
}
