import Foundation
func runQueuedPrimaryActivityWireTests(nativeFrames:[String]=[])throws {
    let instance=String(repeating:"07",count:16),request=try NativePrimaryActivityWire.queuedRequest(instance:instance)
    guard request.count==32,request.prefix(5)==Data("FIA9".utf8)+Data([2]) else {fatalError("Queued request version changed")}
    var frame=Data(repeating:0,count:66888)
    frame.replaceSubrange(0..<4,with:Data("FIT9".utf8));frame[4]=2
    frame.replaceSubrange(8..<24,with:Data(repeating:7,count:16));frame[31]=2;frame[38]=3;frame[39]=232
    frame[43]=1;frame[55]=1;frame[67]=1;frame[73]=11;frame[83]=1
    frame.replaceSubrange(92..<103,with:Data("org/primary".utf8))
    let value=try NativePrimaryActivityWire.queuedReply(frame,instance:instance,after:1)
    guard value.queued==1,value.active==0,value.models[0].queued==1,value.owners==1 else {fatalError("Queued phase lost in manager decode")}
    func invalid(_ bad:Data)throws {
        do {_=try NativePrimaryActivityWire.queuedReply(bad,instance:instance);fatalError("Invalid queued frame accepted")}catch NativeControlError.invalid {}
    }
    var rebased=Data(repeating:0,count:19)+frame;rebased.removeFirst(19)
    guard try NativePrimaryActivityWire.queuedReply(rebased,instance:instance).queued==1 else {fatalError("Queued frame depended on Data offsets")}
    for offset in [5,6,68,69,70,71,74,75,103,66887] {var bad=frame;bad[offset]=1;try invalid(bad)}
    var badVersion=frame;badVersion[4]=1;try invalid(badVersion)
    var over=frame;over[42]=1;over[43]=1;try invalid(over)
    var incoherent=frame;incoherent[83]=2;try invalid(incoherent)
    var wrong=frame;wrong[8]=8;try invalid(wrong)
    do {_=try NativePrimaryActivityWire.reply(frame,instance:instance);fatalError("Queued frame reinterpreted as legacy")}catch NativeControlError.invalid {}
    try invalid(Data(frame.dropLast()))
    var maximum=frame
    maximum.replaceSubrange(40..<66888,with:Data(repeating:0,count:66888-40))
    maximum[43]=64;maximum[55]=64;maximum[67]=64
    for index in 0..<64 {
        let offset=72+index*1044,id=Data("org/model-\(index)".utf8)
        maximum[offset+1]=UInt8(id.count);maximum[offset+11]=1
        maximum.replaceSubrange((offset+20)..<(offset+20+id.count),with:id)
    }
    guard try NativePrimaryActivityWire.queuedReply(maximum,instance:instance).models.count==64 else {fatalError("Maximum queued model set truncated")}
    var duplicate=maximum
    duplicate.replaceSubrange((72+1044)..<(72+2088),with:maximum[72..<(72+1044)])
    try invalid(duplicate)
    var noClock=frame;noClock.replaceSubrange(32..<40,with:Data(repeating:255,count:8))
    guard try NativePrimaryActivityWire.queuedReply(noClock,instance:instance).sampledAt==nil else {fatalError("Missing source clock replaced")}
    let peer=NativeControlPeer(pid:42,start:100,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"a",count:64)))
    var diagnostic=NativePrimaryActivityDiagnostics(configured:true)
    diagnostic.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1000,activity:value),expectedInstance:instance,now:1000)
    let summary=diagnostic.summary(now:1000)
    guard (summary["reported_counts"] as? [String:Int])?["queued"]==1,summary["coverage"] as? String=="unknown",summary["authority"] as? Bool==false else {fatalError("Queued diagnostic lost phase or gained authority")}
    var legacy=Data(repeating:0,count:66624)
    legacy.replaceSubrange(0..<4,with:Data("FIT9".utf8));legacy[4]=1
    legacy.replaceSubrange(8..<24,with:Data(repeating:7,count:16));legacy[31]=3;legacy[38]=3;legacy[39]=233
    let old=try NativePrimaryActivityWire.reply(legacy,instance:instance)
    diagnostic.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1001,activity:old),expectedInstance:instance,now:1001)
    guard diagnostic.summary(now:1001)["state"] as? String=="fenced" else {fatalError("Source phase format changed within one process epoch")}
    var legacyOnly=NativePrimaryActivityDiagnostics(configured:true)
    legacyOnly.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1001,activity:old),expectedInstance:instance,now:1001)
    guard (legacyOnly.summary(now:1001)["reported_counts"] as? [String:Any])?["queued"] is NSNull else {fatalError("Legacy missing queue phase became a zero observation")}

    guard nativeFrames.isEmpty || nativeFrames.count==2 else {fatalError("Native frame set incomplete")}
    for (index,path) in nativeFrames.enumerated() {
        let native=try Data(contentsOf:URL(fileURLWithPath:path))
        let decoded=try NativePrimaryActivityWire.queuedReply(native,instance:String(repeating:"6f",count:16))
        let expected=index==0 ? 1:64
        guard decoded.queued==expected,decoded.owners==expected,decoded.models.count==expected,decoded.active==0 else {fatalError("Actual native frame disagrees with manager")}
        for (row,model) in decoded.models.enumerated() {
            guard model.model==(index==0 ? "fixture/queued-wire":"fixture/model-\(row)"),model.queued==1 else {fatalError("Actual native exact model identity changed")}
        }
    }

}
