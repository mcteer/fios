import Foundation

func runNativeLineageConsumerTests()throws {
    let epoch=String(repeating:"1",count:32),job="00000000-0000-4000-8000-000000000001"
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:"00000000-0000-4000-8000-000000000002",nativeEpoch:epoch,canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"c",count:64)))
    let id=try scope.nativeRequestCorrelationID(job:job,attempt:0)
    func consumer()throws->NativeRequestLineageConsumer {try NativeRequestLineageConsumer(scope:scope,job:job,attempt:0,peer:peer)}
    func sample(_ sequence:UInt64,at:Int64=10000,root:UInt64=10,found:Bool=true,uncertain:Bool=false,
                source:NativeControlPeer?=nil,instance:String?=nil,correlation:String?=nil,owners:Int?=nil)->NativeRequestLineageSample {
        NativeRequestLineageSample(peer:source ?? peer,sampledAt:at,
            lineage:NativeRequestLineage(instance:instance ?? epoch,correlationID:correlation ?? id,sampleSequence:sequence,
                rootSequence:found ? root:0,found:found,uncertain:uncertain,references:found ? 1:0,
                owners:owners ?? (found ? 1:0),ingress:0,preparing:found ? 1:0,active:0,responding:0))
    }
    func unknown(_ value:NativeRequestLineageObservation){guard case .unknown=value else {fatalError("Uncertain lineage became live")}}
    func live(_ value:NativeRequestLineageObservation){guard case .live(let sample)=value,sample.found,!sample.uncertain else {fatalError("Valid lineage lost")}}
    var observed=try consumer()
    live(observed.accept(sample(1),now:10000))
    unknown(observed.accept(sample(1),now:10000))
    unknown(observed.accept(nil,now:10001))
    unknown(observed.accept(sample(2,at:10002,found:false,uncertain:true),now:10002))
    guard observed.rootSequence==10 else {fatalError("Unknown gap cleared original native root")}
    unknown(observed.accept(sample(1,at:10003),now:10003))
    live(observed.accept(sample(3,at:10004),now:10004))
    guard case .unknown=observed.accept(sample(4,at:10005,root:11),now:10005) else {fatalError("Native request root was rebound")}
    guard observed.fenced,observed.rootSequence==10 else {fatalError("Reused opaque ID rebound original request")}
    unknown(observed.accept(sample(5,at:10006),now:10006))
    for age:Int64 in [-1001,-1000,5000,5001] {
        var fresh=try consumer();let value=fresh.accept(sample(1),now:10000+age)
        if (-1000...5000).contains(age){live(value)}else{unknown(value)}
    }
    var times=try consumer();live(times.accept(sample(1),now:10000))
    unknown(times.accept(sample(2,at:9999),now:10001))
    live(times.accept(sample(3,at:10001),now:10001))
    unknown(times.accept(nil,now:10000));guard times.fenced else {fatalError("Lineage clock rollback did not fence")}
    unknown(times.accept(sample(4,at:10002),now:10002))
    let peers=[NativeControlPeer(pid:43,start:peer.start,executable:peer.executable),
               NativeControlPeer(pid:peer.pid,start:100,executable:peer.executable),
               NativeControlPeer(pid:peer.pid,start:peer.start,executable:try VerifiedExecutable(path:"/fixture/other",sha256:peer.executable.sha256)),
               NativeControlPeer(pid:peer.pid,start:peer.start,executable:try VerifiedExecutable(path:peer.executable.path,sha256:String(repeating:"d",count:64)))]
    for changed in peers {
        var pinned=try consumer();live(pinned.accept(sample(1),now:10000))
        unknown(pinned.accept(sample(2,source:changed),now:10000));guard pinned.fenced else {fatalError("Native peer generation rebound")}
        unknown(pinned.accept(sample(3),now:10000))
    }
    for bad in [sample(2,instance:String(repeating:"2",count:32)),sample(2,correlation:String(repeating:"e",count:64))] {
        var pinned=try consumer();live(pinned.accept(sample(1),now:10000));unknown(pinned.accept(bad,now:10000))
        guard pinned.fenced else {fatalError("Native scope/request identity rebound")}
    }
    var malformed=try consumer();unknown(malformed.accept(sample(1,owners:-1),now:10000))
    guard malformed.rootSequence==nil else {fatalError("Malformed typed sample adopted root")}
    live(malformed.accept(sample(2),now:10000))
    var uncertain=try consumer();unknown(uncertain.accept(sample(1,uncertain:true),now:10000))
    unknown(uncertain.accept(sample(2,root:11),now:10000));guard uncertain.fenced else {fatalError("Uncertain root was silently replaced")}
    print("PASS: original request/source/peer/root binding, strict replay/original-time age, unknown-gap retention and sticky clock/generation fences; volatile observation only")
}
