import Foundation

func runNativePrimaryActivityWireTests()throws {
    let instance=String(repeating:"07",count:16),request=try NativePrimaryActivityWire.request(instance:instance)
    guard request.count==32,request.prefix(5)==Data("FIA9".utf8)+Data([1]),request[8..<24]==Data(repeating:7,count:16) else {fatalError("Primary observation request changed")}
    var frame=Data(repeating:0,count:66624)
    frame.replaceSubrange(0..<4,with:Data("FIT9".utf8));frame[4]=1
    frame.replaceSubrange(8..<24,with:Data(repeating:7,count:16));frame[31]=2;frame[38]=3;frame[39]=232
    frame[43]=1;frame[55]=1;frame[63]=1;frame[65]=11;frame[75]=1
    frame.replaceSubrange(80..<91,with:Data("org/primary".utf8))
    let value=try NativePrimaryActivityWire.reply(frame,instance:instance,after:1)
    guard value.sampleSequence==2,value.sampledAt==1000,value.owners==1,value.ingress==0,value.active==1,
          value.models.count==1,value.models[0].model=="org/primary",value.models[0].active==1,!value.uncertain else {fatalError("Primary source attribution changed")}
    var rebased=Data(repeating:0,count:80)+frame;rebased.removeFirst(80)
    guard try NativePrimaryActivityWire.reply(rebased,instance:instance).models.count==1 else {fatalError("Primary frame depended on Data offsets")}
    var empty=frame;empty.replaceSubrange(40..<66624,with:Data(repeating:0,count:66624-40))
    let missing=try NativePrimaryActivityWire.reply(empty,instance:instance)
    guard missing.owners==0,missing.models.isEmpty else {fatalError("Empty primary ownership gained an identity")}
    var noClock=frame;noClock.replaceSubrange(32..<40,with:Data(repeating:255,count:8))
    guard try NativePrimaryActivityWire.reply(noClock,instance:instance).sampledAt==nil else {fatalError("Unavailable native clock became local time")}
    do {_=try NativePrimaryActivityWire.reply(frame,instance:instance,after:2);fatalError("Primary source sequence replay accepted")}catch NativeControlError.invalid {}
    var inconsistent=frame;inconsistent[75]=2
    do {_=try NativePrimaryActivityWire.reply(inconsistent,instance:instance);fatalError("Non-disjoint model phases accepted")}catch NativeControlError.invalid {}
    let peer=NativeControlPeer(pid:42,start:100,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"a",count:64)))
    func sample(_ sequence:UInt8,_ time:UInt8,_ uncertain:Bool)throws->NativePrimaryActivitySample {
        var current=frame;current[31]=sequence;current[39]=time;current[7]=uncertain ? 1:0
        let activity=try NativePrimaryActivityWire.reply(current,instance:instance)
        return NativePrimaryActivitySample(peer:peer,receivedAt:activity.sampledAt!,activity:activity)
    }
    var diagnostic=NativePrimaryActivityDiagnostics(configured:true)
    diagnostic.completed(try sample(2,232,true),expectedInstance:instance,now:1000)
    let fresh=diagnostic.summary(now:1000)
    guard fresh["state"] as? String=="received",fresh["coverage"] as? String=="unknown",fresh["authority"] as? Bool==false,
          fresh["model_identities"] as? Int==1,fresh["retained_uncertainty"] as? Bool==true else {fatalError("Primary observations gained authority")}
    guard diagnostic.summary(now:6001)["state"] as? String=="stale",diagnostic.summary(now:Int64.min)["state"] as? String=="stale" else {fatalError("Primary source clock refreshed or overflowed")}
    diagnostic.failed()
    guard diagnostic.summary(now:1001)["retained_uncertainty"] as? Bool==true else {fatalError("Unavailable primary sample cleared uncertainty")}
    diagnostic.completed(try sample(3,233,true),expectedInstance:instance,now:1001)
    guard diagnostic.summary(now:1001)["state"] as? String=="received" else {fatalError("New primary sample did not refresh")}
    diagnostic.completed(try sample(4,234,false),expectedInstance:instance,now:1002)
    guard diagnostic.summary(now:1002)["state"] as? String=="fenced",diagnostic.summary(now:1002)["retained_uncertainty"] as? Bool==true else {fatalError("Primary sticky uncertainty cleared")}

}
