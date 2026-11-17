import Foundation

func runNativeLineageClockTests()throws {
    let instance=String(repeating:"07",count:16),correlation=String(repeating:"09",count:32)
    let request=try NativeRequestLineageWire.request(instance:instance,correlationID:correlation,version:2)
    guard request.count==64,request[4]==2 else {throw NativeControlError.invalid}
    var frame=Data(repeating:0,count:112)
    frame.replaceSubrange(0..<4,with:Data("FIP9".utf8));frame[4]=2;frame[6]=1
    frame.replaceSubrange(8..<56,with:request[8..<56])
    func number(_ offset:Int,_ value:UInt64,_ length:Int=8) {
        for index in 0..<length {frame[offset+index]=UInt8(truncatingIfNeeded:value>>((length-index-1)*8))}
    }
    number(56,1);number(64,UInt64.max);number(72,1);number(80,1,4);number(92,1,4);number(100,10000)
    let value=try NativeRequestLineageWire.reply(frame,instance:instance,correlationID:correlation,version:2)
    guard value.sourceCapturedAt==10000,value.rootSequence==UInt64.max,value.active==1 else {throw NativeControlError.invalid}
    var legacy=frame;legacy[4]=1;legacy.replaceSubrange(100..<108,with:Data(repeating:0,count:8))
    guard try NativeRequestLineageWire.reply(legacy,instance:instance,correlationID:correlation).sourceCapturedAt==nil else {throw NativeControlError.invalid}
    number(100,UInt64.max)
    guard try NativeRequestLineageWire.reply(frame,instance:instance,correlationID:correlation,version:2).sourceCapturedAt==nil else {throw NativeControlError.invalid}
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:instance,canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"c",count:64)))
    let job=UUID().uuidString.lowercased(),id=try scope.nativeRequestCorrelationID(job:job,attempt:0)
    var consumer=try NativeRequestLineageConsumer(scope:scope,job:job,attempt:0,peer:peer)
    var observed=NativeRequestLineage(instance:instance,correlationID:id,sampleSequence:1,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:0,active:1,responding:0,sourceCapturedAt:10000)
    guard case .live=consumer.accept(NativeRequestLineageSample(peer:peer,sampledAt:10001,lineage:observed),now:10002) else {throw NativeControlError.invalid}
    observed=NativeRequestLineage(instance:instance,correlationID:id,sampleSequence:2,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:0,active:1,responding:0,sourceCapturedAt:10000)
    // A later client query cannot refresh an old native capture.
    guard case .unknown=consumer.accept(NativeRequestLineageSample(peer:peer,sampledAt:16000,lineage:observed),now:16001),consumer.rootSequence==UInt64.max else {throw NativeControlError.invalid}
    // The opt-in queue frame keeps operation counts separate from handler owners.
    number(100,10000)
    frame[4]=3;frame.append(Data(repeating:0,count:16));number(112,1,4)
    var queued=try NativeRequestLineageWire.reply(frame,instance:instance,correlationID:correlation,version:3)
    guard queued.operations?.queued==1,queued.operations?.active==0,queued.active==1 else {throw NativeControlError.invalid}
    let events=NativeRequestEventsSample(peer:peer,requestedAt:10000,receivedAt:10001,
        events:NativeRequestEvents(instance:instance,correlationID:correlation,rootSequence:UInt64.max,sampleSequence:1,sampledAt:10000,
            identityKnown:true,sdkInitialized:true,sourceUncertain:false,host:nil,metal:nil))
    func state(_ value:NativeRequestLineage)->String? {
        let sample=NativeRequestLineageSample(peer:peer,sampledAt:10000,lineage:value)
        return (NativeRequestEventStatus(attempt:0,sample:events,lineage:sample).object["request"] as? [String:Any])?["state"] as? String
    }
    guard state(queued)=="queued" else {throw NativeControlError.invalid}
    number(116,1,4);queued=try NativeRequestLineageWire.reply(frame,instance:instance,correlationID:correlation,version:3)
    guard state(queued)=="active",queued.operations?.queued==1,queued.operations?.active==1 else {throw NativeControlError.invalid}
    print("PASS: native lineage capture time stays separate from query time; legacy and unavailable clocks remain explicit; later queries do not refresh old native captures")
}
