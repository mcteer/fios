import Foundation

func runNativePreparationTests()throws {
    try runNativePreparationReservationTests()
    let instance=String(repeating:"a",count:32),id=String(repeating:"b",count:64),model="fixture/exact-模型",root=UInt64.max
    let request=try NativePreparationWire.request(operation:.reserve,instance:instance,correlationID:id,model:model)
    guard request.count==1104,request.prefix(4)==Data("FIP9".utf8),request[5]==1,
          request[56..<64].allSatisfy({$0==0}),request[80..<80+model.utf8.count]==Data(model.utf8),
          request[(80+model.utf8.count)...].allSatisfy({$0==0}) else {fatalError("Preparation request lost exact bounded model identity")}
    func frame(_ operation:NativePreparationOperation)->Data {
        var data=Data(repeating:0,count:88);data.replaceSubrange(0..<4,with:Data("FIV9".utf8));data[4]=1;data[6]=operation.rawValue
        data.replaceSubrange(8..<24,with:request[8..<24]);data[31]=2;data[38]=3;data[39]=232
        data.replaceSubrange(40..<48,with:Data(repeating:255,count:8));data.replaceSubrange(48..<80,with:request[24..<56])
        if operation == .reserve {data.replaceSubrange(80..<84,with:request[68..<72])}
        return data
    }
    func decode(_ data:Data,_ operation:NativePreparationOperation = .reserve)throws->NativePreparationAcknowledgement {
        try NativePreparationWire.reply(data,operation:operation,instance:instance,correlationID:id,model:model,
            rootSequence:operation == .reserve ? 0:root,lifetimeMilliseconds:operation == .reserve ? 5000:0,after:1)
    }
    let reserved=try decode(frame(.reserve)),withdrawn=try decode(frame(.withdraw),.withdraw)
    guard reserved.rootSequence==root,withdrawn.rootSequence==root,reserved.model.utf8.elementsEqual(model.utf8),
          reserved.sampleSequence==2,reserved.sourceSampledAt==1000,reserved.lifetimeMilliseconds==5000,
          withdrawn.lifetimeMilliseconds==0 else {fatalError("Preparation acknowledgement narrowed original identity")}
    func refuses(_ data:Data,_ operation:NativePreparationOperation = .reserve) {
        do{_=try decode(data,operation)}catch{return};fatalError("Malformed preparation acknowledgement accepted")
    }
    for index in [0,4,5,6,7,8,24,32,48,80,84,87] {var bad=frame(.reserve);bad[index]=255;refuses(bad)}
    var zero=frame(.reserve);zero.replaceSubrange(40..<48,with:Data(repeating:0,count:8));refuses(zero)
    var wrongRoot=frame(.withdraw);wrongRoot[47]=254;refuses(wrongRoot,.withdraw)
    var replay=frame(.reserve);replay[31]=1;refuses(replay)
    refuses(frame(.reserve).dropLast());var extra=frame(.reserve);extra.append(0);refuses(extra)
    var unknownClock=frame(.reserve);unknownClock.replaceSubrange(32..<40,with:Data(repeating:255,count:8))
    guard try decode(unknownClock).sourceSampledAt==nil else {fatalError("Unknown source clock became a positive observation")}
    var sliced=Data([9]);sliced.append(frame(.reserve));sliced.removeFirst();_=try decode(sliced)
    for (operation,rootValue,lifetime) in [(NativePreparationOperation.reserve,UInt64(1),UInt32(5000)),(.reserve,0,0),(.reserve,0,5001),(.withdraw,0,0),(.withdraw,root,1)] {
        do{_=try NativePreparationWire.request(operation:operation,instance:instance,correlationID:id,model:model,rootSequence:rootValue,lifetimeMilliseconds:lifetime)}catch{continue}
        fatalError("Invalid native preparation operation bounds accepted")
    }
    for badModel in ["",String(repeating:"x",count:1025),"fixture\0model"] {
        do{_=try NativePreparationWire.request(operation:.reserve,instance:instance,correlationID:id,model:badModel)}catch{continue}
        fatalError("Unbounded/invalid exact native model accepted")
    }
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    for version:UInt8 in [2,3] {
        let client=NativeControlClient(path:"/fixture/missing/control.sock",peer:peer,version:version)
        do {
            _=try client.reservePreparation(instance:instance,correlationID:id,model:model,after:version==2 ? 0:UInt64.max)
        } catch NativeControlError.invalid {continue}
        fatalError("Invalid preparation context reached transport before refusal")
    }
    do{_=try NativePreparationWire.request(operation:.reserve,instance:instance,correlationID:String(repeating:"0",count:64),model:model)}catch{
        print("PASS: native preparation CPU acknowledgements, full-width roots, exact model/operation/epoch/correlation, bounded frames and unknown clock; no dispatch or terminal proof")
        return
    }
    fatalError("Empty native preparation correlation accepted")
}
