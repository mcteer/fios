import Foundation

func runNativePristinePreparationTests()throws {
    let instance=String(repeating:"a",count:32),id=String(repeating:"b",count:64),model="fixture/exact-模型",root=UInt64.max
    let request=try NativePristinePreparationWire.request(instance:instance,correlationID:id,model:model,rootSequence:root)
    guard request.count==1104,request[4]==2,request[5]==3,request[80..<80+model.utf8.count]==Data(model.utf8)
        else {fatalError("Pristine preparation lost distinct wire/model")}
    var reply=Data(repeating:0,count:88)
    reply.replaceSubrange(0..<4,with:Data("FIV9".utf8));reply[4]=2;reply[6]=3
    reply.replaceSubrange(8..<24,with:request[8..<24]);reply[31]=2;reply[38]=3;reply[39]=232
    reply.replaceSubrange(40..<48,with:request[56..<64]);reply.replaceSubrange(48..<80,with:request[24..<56])
    func decode(_ bytes:Data)throws->NativePristinePreparationClosure {
        try NativePristinePreparationWire.reply(bytes,instance:instance,correlationID:id,model:model,rootSequence:root,after:1)
    }
    let closure=try decode(reply)
    guard closure.rootSequence==root,closure.sampleSequence==2,closure.sourceSampledAt==1000,
          closure.model.utf8.elementsEqual(model.utf8) else {fatalError("Pristine preparation narrowed identity")}
    for index in [0,4,5,6,7,8,24,32,40,48,80,84,87] {
        var bad=reply;bad[index]^=0x7f
        do{_=try decode(bad)}catch{continue};fatalError("Malformed pristine closure accepted at \(index)")
    }
    for version:UInt8 in [1,3] {
        var bad=reply;bad[4]=version
        do{_=try decode(bad)}catch{continue};fatalError("Other preparation version became pristine closure")
    }
    do {
        _=try NativePreparationWire.reply(reply,operation:.withdraw,instance:instance,correlationID:id,model:model,
            rootSequence:root,lifetimeMilliseconds:0,after:1)
        fatalError("Pristine closure became ordinary withdrawal acknowledgement")
    }catch{}
    var replay=reply;replay[31]=1
    do{_=try decode(replay);fatalError("Pristine sequence replay accepted")}catch{}
    do{_=try decode(reply.dropLast());fatalError("Truncated pristine reply accepted")}catch{}
    var extra=reply;extra.append(0)
    do{_=try decode(extra);fatalError("Trailing pristine reply accepted")}catch{}
    var unknown=reply;unknown.replaceSubrange(32..<40,with:Data(repeating:255,count:8))
    guard try decode(unknown).sourceSampledAt==nil else {fatalError("Unknown clock gained freshness")}
    do {
        _=try NativePristinePreparationWire.request(instance:instance,correlationID:id,model:model,rootSequence:0)
        fatalError("Zero pristine root accepted")
    }catch{}
    print("PASS: distinct pristine CPU closure frames reject weak acknowledgements, malformed identity, replay and unknown-clock authority")
}
