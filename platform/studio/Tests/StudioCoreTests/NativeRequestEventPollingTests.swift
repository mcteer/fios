import Foundation
import Darwin

private final class NormalRequestEventSource:NativeRequestEventsReading,@unchecked Sendable {
    let peer:NativeControlPeer
    let observesRequestEvents:Bool
    private let lock=NSLock()
    private var sequence:UInt64=0
    private var reads=0
    private let replacementRoot:UInt64?
    private let eventCapture:Int64
    private let replayAfterOutage:Bool
    private var lastRoot:UInt64?
    init(peer:NativeControlPeer,enabled:Bool,replacementRoot:UInt64?=nil,eventCapture:Int64=10000,replayAfterOutage:Bool=false) {
        self.peer=peer;observesRequestEvents=enabled;self.replacementRoot=replacementRoot;self.eventCapture=eventCapture;self.replayAfterOutage=replayAfterOutage
    }
    var eventReads:Int {lock.lock();defer {lock.unlock()};return reads}
    var lastEventRoot:UInt64? {lock.lock();defer {lock.unlock()};return lastRoot}
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample {
        lock.lock();sequence+=1;let next=sequence;lock.unlock()
        return NativeRequestLineageSample(peer:peer,sampledAt:10000,lineage:NativeRequestLineage(instance:instance,correlationID:correlationID,
            sampleSequence:next,rootSequence:next<4 ? (replacementRoot ?? UInt64.max):0,found:next<4,uncertain:next>=4,references:next<4 ? 1:0,owners:next<4 ? 1:0,ingress:0,preparing:0,active:next<4 ? 1:0,responding:0))
    }
    func requestEvents(instance:String,correlationID:String,rootSequence:UInt64)throws->NativeRequestEventsSample {
        lock.lock();reads+=1;lastRoot=rootSequence;let next=reads;lock.unlock()
        if next==3 {throw NativeControlError.unavailable}
        let counts=NativeRequestEventCounts(sequence:UInt64(next),originated:2,retired:next==1 ? 1:2,pending:next==1 ? 1:0,historyRetained:true,uncertain:false)
        return NativeRequestEventsSample(peer:peer,requestedAt:10000,receivedAt:10001,
            events:NativeRequestEvents(instance:instance,correlationID:correlationID,rootSequence:rootSequence,sampleSequence:replayAfterOutage && next==4 ? 3 : UInt64(next+1),sampledAt:eventCapture,
                identityKnown:true,sdkInitialized:true,sourceUncertain:false,host:nil,metal:counts))
    }
}

func runNativeRequestEventPollingTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),job=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:String(repeating:"1",count:32),canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"c",count:64)))
    let token=TaskOwner.newToken(),owner=try TaskOwner(token:token,peerUID:geteuid()).hash
    _=try journal.reserveJob(DurableJob(id:job,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"d",count:64),created:1000))
    try journal.transitionJob(id:job,to:.running)
    try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope);try journal.markDispatched(job:job,attempt:0)
    func poll(_ poller:NativeLineagePoller,between:()->Void={})throws {
        guard try poller.beginNext() else {throw JournalError.invalid}
        between()
        let end=ProcessInfo.processInfo.systemUptime+2
        while ProcessInfo.processInfo.systemUptime<end {
            if try poller.drain(now:10001) {return}
            Thread.sleep(forTimeInterval:0.001)
        }
        throw NativeControlError.deadline
    }
    let source=NormalRequestEventSource(peer:peer,enabled:true,replayAfterOutage:true),poller=NativeLineagePoller(journal:journal,source:source)
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let jobs=JobController(journal:journal,executor:UnavailableSandboxRuntime())
    let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("exports"),availableBytes:{50<<30}))
    let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,socket:"/fixture/unused.sock",peerUID:geteuid())
    let commands=TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[],peerUID:geteuid(),
        nativeRequestEvents:{job,now in try poller.requestEventStatuses(job:job,now:now)})
    var admission=AdmissionPolicy()
    let resources=ResourceSample(sampledAt:10001,physical:24<<30,available:16<<30,vmAvailable:nil,diskFree:50<<30,cpu:10,pressure:.normal,thermal:.nominal)
    func status()throws->[String:Any] {
        let request=try ControlRequest.decode(JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":"job.status","payload":["owner":token,"job":job]]))
        return try commands.handle(request,role:.task,sample:resources,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:10001,uptime:10001)
    }
    try poll(poller)
    guard let pending=try poller.requestEvents(job:job,attempt:0,now:10001),pending.events.rootSequence==UInt64.max,
          pending.events.metal?.pending==1,source.eventReads==1 else {throw JournalError.invalid}
    try poll(poller)
    guard let retired=try poller.requestEvents(job:job,attempt:0,now:10001),retired.events.metal?.retired==2,
          retired.events.metal?.pending==0,try journal.inferenceScope(job:job,attempt:0)?.state == .dispatched,
          try journal.unresolvedCount()==1 else {throw JournalError.invalid}
    let response=try status()
    guard let rows=response["native_request_events"] as? [[String:Any]],rows.count==1,
          rows[0]["root_sequence"] as? String == String(UInt64.max),let metal=rows[0]["metal"] as? [String:Any],
          metal["pending"] as? UInt64 == 0,(rows[0]["request"] as? [String:Any])?["state"] as? String=="active",response["unresolved_managed_requests"] as? Int==1,
          response["state"] as? String == "running" else {throw JournalError.invalid}
    _=try JSONSerialization.data(withJSONObject:response)
    guard try poller.requestEvents(job:job,attempt:0,now:16001)==nil else {throw JournalError.invalid}
    // A normal source outage replaces the current observation with absence.
    try poll(poller)
    guard try poller.requestEvents(job:job,attempt:0,now:10001)==nil,try status()["native_request_events"]==nil,try journal.unresolvedCount()==1 else {throw JournalError.invalid}
    // After native lineage disappears, retained callback history stays separate
    // from an unknown current native request phase.
    try poll(poller)
    guard try status()["native_request_events"]==nil else {fatalError("Native callback observation replay survived a source outage")}
    try poll(poller)
    let closed=try status()
    guard let history=closed["native_request_events"] as? [[String:Any]],history.count==1,
          (history[0]["request"] as? [String:Any])?["state"] as? String=="unknown",
          (history[0]["metal"] as? [String:Any])?["retired"] as? UInt64==2,
          try journal.unresolvedCount()==1 else {throw JournalError.invalid}
    poller.nativeSourceUnavailable()
    try poll(poller)
    guard try status()["native_request_events"]==nil,try journal.unresolvedCount()==1 else {
        fatalError("Unavailable ingress source left callback diagnostics current")
    }
    poller.observeNativeInstance(scope.nativeEpoch)
    try poll(poller,between:{
        poller.nativeSourceUnavailable()
        poller.observeNativeInstance(scope.nativeEpoch)
    })
    guard try status()["native_request_events"]==nil else {fatalError("Ingress revalidation republished an in-flight callback reply")}
    try poll(poller)
    guard try status()["native_request_events"] != nil else {fatalError("New correlated callback sample did not restore diagnostics")}
    poller.observeNativeInstance(String(repeating:"2",count:32))
    guard try status()["native_request_events"]==nil,try journal.unresolvedCount()==1 else {
        fatalError("Changed native instance left old callback observations visible or released ownership")
    }
    try poll(poller)
    guard try status()["native_request_events"]==nil,try journal.unresolvedCount()==1 else {
        fatalError("Old-instance callback lookup restored invalidated diagnostics")
    }
    let disabled=NormalRequestEventSource(peer:peer,enabled:false),plain=NativeLineagePoller(journal:journal,source:disabled)
    try poll(plain)
    guard disabled.eventReads==0,try plain.requestEvents(job:job,attempt:0,now:10001)==nil else {throw JournalError.invalid}
    let replacement=NativeLineagePoller(journal:journal,source:source)
    guard try replacement.requestEvents(job:job,attempt:0,now:10001)==nil else {throw JournalError.invalid}
    for (capture,expected) in [(9000,true),(8999,false)] {
        let source=NormalRequestEventSource(peer:peer,enabled:true,eventCapture:Int64(capture))
        let observer=NativeLineagePoller(journal:journal,source:source)
        try poll(observer)
        let present=try observer.requestEvents(job:job,attempt:0,now:10001) != nil
        guard source.eventReads==1,present==expected else {fatalError("Event capture outside its request window exported as current")}
    }
    let changedRoot=NormalRequestEventSource(peer:peer,enabled:true,replacementRoot:7)
    try poll(NativeLineagePoller(journal:journal,source:changedRoot))
    guard changedRoot.lastEventRoot==UInt64.max,try journal.unresolvedCount()==1 else {
        fatalError("Event lookup followed a replacement root instead of the original journal root")
    }
    print("PASS: optional off-loop original-request SDK observations progress pending to retired without completing the journal request; unavailable and expired observations remain absent")
}
