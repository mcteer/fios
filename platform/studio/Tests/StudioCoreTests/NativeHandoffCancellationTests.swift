import Foundation

func runNativeHandoffCancellationTests()throws {
    let job=UUID().uuidString.lowercased(),instance=String(repeating:"1",count:32)
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:instance,canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    let peer=NativeControlPeer(pid:42,start:9,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"c",count:64)))
    let id=try scope.nativeRequestCorrelationID(job:job,attempt:0)
    func consumer()throws->NativeRequestLineageConsumer {
        var value=try NativeRequestLineageConsumer(scope:scope,job:job,attempt:0,peer:peer)
        let sample=NativeRequestLineageSample(peer:peer,sampledAt:10000,lineage:NativeRequestLineage(instance:instance,correlationID:id,sampleSequence:1,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:1,preparing:0,active:0,responding:0))
        guard case .live=value.accept(sample,now:10000) else {throw JournalError.invalid}
        return value
    }
    func cancelled(root:UInt64=UInt64.max,state:NativeHandoffState = .cancelled,uncertain:Bool=false,sequence:UInt64=2,at:Int64=10001)->NativeHandoffSample {
        NativeHandoffSample(peer:peer,sampledAt:at,result:NativeHandoffResult(operation:.cancel,instance:instance,correlationID:id,rootSequence:root,sampleSequence:sequence,state:state,uncertain:uncertain))
    }
    for sample in [cancelled(root:7),cancelled(state:.handedOff),cancelled(state:.unknown,uncertain:true),cancelled(uncertain:true),cancelled(sequence:1),cancelled(sequence:UInt64(ActivityPolicy.maximumTimestamp)+1),cancelled(at:11002),cancelled(at:4999)] {
        var value=try consumer()
        guard value.acceptHandoffCancellation(sample,now:10001)==nil else {fatalError("Ineligible native cancellation became non-dispatch metadata")}
    }
    var transferred=try consumer()
    _=transferred.acceptHandoffCancellation(cancelled(state:.handedOff),now:10001)
    guard transferred.fenced,transferred.acceptHandoffCancellation(cancelled(sequence:3,at:10002),now:10002)==nil else {fatalError("Handed-off root later became not-sent")}
    var value=try consumer()
    guard value.acceptHandoffCancellation(nil,now:10000)==nil,
          value.acceptHandoffCancellation(cancelled(),now:10001) != nil else {throw JournalError.invalid}
    let receipt=NativeHandoffClosureCheckpoint(version:1,localProducer:"never_spawned",workerMetadataVersion:2,handoffVersion:1,launchNonce:UUID().uuidString.lowercased(),grantSHA256:nil)
    try value.recordHandoffClosure(receipt)
    let data=try value.checkpoint(scope:scope)
    let restored=try NativeRequestLineageConsumer(scope:scope,job:job,attempt:0,peer:peer,checkpoint:data)
    guard restored.rootSequence==UInt64.max,!restored.fenced,
          try NativeRequestLineageConsumer.handoffClosureReceipt(data,scope:scope,job:job,attempt:0)?.launchNonce==receipt.launchNonce else {throw JournalError.invalid}
    let original=try JSONSerialization.jsonObject(with:data) as! [String:Any]
    guard original["version"] as? Int==2 else {throw JournalError.invalid}
    func refuses(_ object:[String:Any])throws {
        let bytes=try JSONSerialization.data(withJSONObject:object)
        do {try NativeRequestLineageConsumer.validateCheckpoint(bytes,scope:scope,job:job,attempt:0)}catch{return}
        fatalError("Malformed durable non-dispatch receipt accepted")
    }
    var bad=original;bad.removeValue(forKey:"handoffClosure");try refuses(bad)
    bad=original;bad["version"]=1;try refuses(bad)
    bad=original;bad["root"]="0";try refuses(bad)
    for field in ["workerMetadataVersion","handoffVersion","localProducer","grantSHA256","unexpected"] {
        var closure=original["handoffClosure"] as! [String:Any]
        closure[field]=field=="localProducer" ? "native_complete":field=="grantSHA256" ? String(repeating:"a",count:64):99
        bad=original;bad["handoffClosure"]=closure;try refuses(bad)
    }
    var old=try consumer()
    let legacy=try old.checkpoint(scope:scope)
    guard try NativeRequestLineageConsumer.handoffClosureReceipt(legacy,scope:scope,job:job,attempt:0)==nil else {fatalError("Legacy checkpoint fabricated proof")}
    _=old.acceptHandoffCancellation(cancelled(),now:10001)
    guard old.acceptHandoffCancellation(cancelled(),now:10001)==nil else {fatalError("Cancellation sample replayed")}
    print("PASS: original-root cancellation candidate rejects transfer/unknown/replay/stale/foreign root; strict version2 durable non-dispatch receipt and legacy-reader separation, no device/all-client proof")
}
