import Foundation

func runNativeRequestRetirementTests()throws {
    let instance=String(repeating:"1",count:32),id=String(repeating:"a",count:64),root=UInt64.max
    let request=try NativeRequestRetirementWire.request(instance:instance,correlationID:id,rootSequence:root)
    guard request.count==64,request.prefix(4)==Data("FIE9".utf8),request[4]==1,
          request[56..<64].allSatisfy({$0==255}) else {fatalError("Retirement request lost original full-width root")}
    func frame(recorded:Bool=true,uncertain:Bool=false,retirement:UInt64=1)->Data {
        var bytes=Data(repeating:0,count:88)
        bytes.replaceSubrange(0..<4,with:Data("FIZ9".utf8));bytes[4]=1;bytes[6]=recorded ? 1:0;bytes[7]=uncertain ? 1:0
        bytes.replaceSubrange(8..<56,with:request[8..<56])
        func put(_ value:UInt64,_ at:Int){for i in 0..<8 {bytes[at+i]=UInt8(truncatingIfNeeded:value >> ((7-i)*8))}}
        put(2,56);put(root,64);put(retirement,72);return bytes
    }
    func decode(_ bytes:Data)throws->NativeRequestRetirement {try NativeRequestRetirementWire.reply(bytes,instance:instance,correlationID:id,rootSequence:root)}
    let record=try decode(frame());guard record.recorded,!record.uncertain,record.rootSequence==root else {fatalError("Local retirement identity lost")}
    let missing=try decode(frame(recorded:false,uncertain:true,retirement:0));guard !missing.recorded,missing.uncertain else {fatalError("Absent retirement became known completion")}
    var sliced=Data([9]);sliced.append(frame());sliced.removeFirst();_=try decode(sliced)
    func refuses(_ bytes:Data){do{_=try decode(bytes)}catch{return};fatalError("Malformed retirement accepted")}
    for index in [0,4,5,6,7,8,24,64,80] {var bad=frame();bad[index]=2;refuses(bad)}
    refuses(frame(recorded:false,uncertain:false,retirement:0));refuses(frame(recorded:false,uncertain:true));refuses(frame(retirement:0))
    refuses(Data(frame().dropLast()));var extra=frame();extra.append(0);refuses(extra)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let job=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"b",count:64),profileHash:String(repeating:"c",count:64),
        managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:instance,canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    let correlation=try scope.nativeRequestCorrelationID(job:job,attempt:0)
    func retirement(_ sequence:UInt64,root:UInt64=UInt64.max)->NativeRequestRetirementSample {
        NativeRequestRetirementSample(peer:peer,sampledAt:10000,retirement:NativeRequestRetirement(instance:instance,correlationID:correlation,
            sampleSequence:sequence,rootSequence:root,retirementSequence:1,recorded:true,uncertain:false))
    }
    do {
        let journal=try Journal(directory:directory)
        try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope);try journal.markDispatched(job:job,attempt:0)
        guard try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:retirement(1),now:10000)==nil else {fatalError("Retirement adopted an unobserved root")}
        let live=NativeRequestLineageSample(peer:peer,sampledAt:10000,lineage:NativeRequestLineage(instance:instance,correlationID:correlation,
            sampleSequence:2,rootSequence:root,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:0,active:0,responding:1))
        _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:live,now:10000)
        guard try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:retirement(3),now:10000) != nil,
              try journal.unresolvedCount()==1,try journal.inferenceScope(job:job,attempt:0)?.state == .dispatched else {fatalError("Local retirement changed inference ownership")}
    }
    do {
        let journal=try Journal(directory:directory)
        guard try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:retirement(3),now:10000)==nil else {fatalError("Retirement replay survived restart")}
        guard try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:retirement(4),now:10000) != nil,
              try journal.uncertainCount()==1 else {fatalError("Local history cleared restart uncertainty")}
        guard try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:retirement(5,root:7),now:10000)==nil,
              try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:retirement(6),now:10000)==nil else {fatalError("Changed root failed to fence retirement")}
    }
    print("PASS: original-root-bound bounded local retirement wire, absent-is-unknown, full-width identity and strict framing; no native completion authority")
}
