import Foundation

func runNativeBackendFenceWireTests()throws {
    let instance=String(repeating:"07",count:16),request=try NativeBackendFenceWire.request(instance:instance)
    guard request.count==32,Array(request.prefix(5))==Array("FIB9".utf8)+[1],
          request[8..<24]==Data(repeating:7,count:16),request[24..<32].allSatisfy({$0==0}) else {fatalError("Backend observation request changed")}
    var frame=Data(repeating:0,count:64)
    frame.replaceSubrange(0..<4,with:Data("FIF9".utf8));frame[4]=1;frame[6]=7;frame[7]=1
    frame.replaceSubrange(8..<24,with:Data(repeating:7,count:16));frame[31]=2;frame[38]=3;frame[39]=232
    frame[43]=17;frame[47]=3
    let value=try NativeBackendFenceWire.reply(frame,instance:instance,after:1)
    guard value.sampleSequence==2,value.sampledAt==1000,value.mimoWarmUncertain==true,
          value.ds4MetalUncertainty==17,value.ds4HostUncertainty==3 else {fatalError("Partial source flags changed")}
    var unavailable=frame;unavailable[6]=0;unavailable[7]=0;unavailable[43]=0;unavailable[47]=0
    let missing=try NativeBackendFenceWire.reply(unavailable,instance:instance)
    guard missing.mimoWarmUncertain==nil,missing.ds4MetalUncertainty==nil,missing.ds4HostUncertainty==nil else {fatalError("Unavailable flags became zero/false")}
    var cold=unavailable;cold[6]=7
    let zero=try NativeBackendFenceWire.reply(cold,instance:instance)
    guard zero.mimoWarmUncertain==false,zero.ds4MetalUncertainty==0,zero.ds4HostUncertainty==0 else {fatalError("Observed false/zero became unavailable")}
    var sliced=Data(repeating:0,count:80)+frame;sliced.removeFirst(80)
    guard try NativeBackendFenceWire.reply(sliced,instance:instance).sampleSequence==2 else {fatalError("Backend decoding depended on Data offsets")}
    for index in [0,4,5,6,7,48] {
        var malformed=frame;malformed[index]=255
        do {_=try NativeBackendFenceWire.reply(malformed,instance:instance);fatalError("Invalid backend frame accepted")}catch NativeControlError.invalid {}
    }
    do {_=try NativeBackendFenceWire.reply(frame,instance:instance,after:2);fatalError("Replayed backend sequence accepted")}catch NativeControlError.invalid {}
    let peer=NativeControlPeer(pid:42,start:100,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"a",count:64)))
    func sample(_ sequence:UInt64,_ time:Int64,_ mimo:Bool?,_ metal:UInt32?,_ host:UInt32?)->NativeBackendFenceSample {
        NativeBackendFenceSample(peer:peer,receivedAt:time,fences:NativeBackendFences(instance:instance,sampleSequence:sequence,sampledAt:time,
            mimoWarmUncertain:mimo,ds4MetalUncertainty:metal,ds4HostUncertainty:host))
    }
    var diagnostics=NativeBackendFenceDiagnostics(configured:true)
    diagnostics.completed(sample(2,1000,true,17,3),expectedInstance:instance,now:1000)
    let fresh=diagnostics.summary(now:1000)
    guard fresh["state"] as? String=="received",fresh["authority"] as? Bool==false,fresh["coverage"] as? String=="unknown",fresh["retained_uncertainty"] as? Bool==true else {fatalError("Partial backend observations acquired authority")}
    diagnostics.failed()
    let gap=diagnostics.summary(now:1001)
    guard gap["mimo_warm_uncertain"] is NSNull,gap["retained_uncertainty"] as? Bool==true else {fatalError("Unknown source gap cleared retained uncertainty")}
    diagnostics.completed(sample(3,1001,nil,nil,nil),expectedInstance:instance,now:1001)
    guard diagnostics.summary(now:1001)["state"] as? String=="unavailable" else {fatalError("Missing provider became observed zero")}
    diagnostics.completed(sample(4,1002,true,17,3),expectedInstance:instance,now:1002)
    guard diagnostics.summary(now:1002)["state"] as? String=="received" else {fatalError("Newer matching source did not refresh")}
    diagnostics.completed(sample(5,1003,false,0,0),expectedInstance:instance,now:1003)
    guard diagnostics.summary(now:1003)["state"] as? String=="fenced",diagnostics.summary(now:1003)["retained_uncertainty"] as? Bool==true else {fatalError("Source flag regression cleared retained uncertainty")}
    var coldDiagnostics=NativeBackendFenceDiagnostics(configured:true)
    coldDiagnostics.completed(sample(1,1000,false,0,0),expectedInstance:instance,now:1000)
    guard coldDiagnostics.summary(now:1000)["mimo_warm_uncertain"] as? Bool==false,
          coldDiagnostics.summary(now:6001)["mimo_warm_uncertain"] is NSNull,
          coldDiagnostics.summary(now:Int64.min)["state"] as? String=="stale" else {fatalError("Expired/invalid source time became fresh")}
    print("PASS: readonly backend frame preserves source/sequence/clock, unavailable versus observed values and unknown-only partial scope")
}
