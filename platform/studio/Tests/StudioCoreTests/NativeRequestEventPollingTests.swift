import Foundation

private final class NormalRequestEventSource:NativeRequestEventsReading,@unchecked Sendable {
    let peer:NativeControlPeer
    let observesRequestEvents:Bool
    private let lock=NSLock()
    private var sequence:UInt64=0
    private var reads=0
    init(peer:NativeControlPeer,enabled:Bool) {self.peer=peer;observesRequestEvents=enabled}
    var eventReads:Int {lock.lock();defer {lock.unlock()};return reads}
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample {
        lock.lock();sequence+=1;let next=sequence;lock.unlock()
        return NativeRequestLineageSample(peer:peer,sampledAt:10000,lineage:NativeRequestLineage(instance:instance,correlationID:correlationID,
            sampleSequence:next,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:0,active:1,responding:0))
    }
    func requestEvents(instance:String,correlationID:String,rootSequence:UInt64)throws->NativeRequestEventsSample {
        lock.lock();reads+=1;let next=reads;lock.unlock()
        if next==3 {throw NativeControlError.unavailable}
        let counts=NativeRequestEventCounts(sequence:UInt64(next),originated:2,retired:next==1 ? 1:2,pending:next==1 ? 1:0,historyRetained:true,uncertain:false)
        return NativeRequestEventsSample(peer:peer,requestedAt:10000,receivedAt:10001,
            events:NativeRequestEvents(instance:instance,correlationID:correlationID,rootSequence:rootSequence,sampleSequence:UInt64(next+1),sampledAt:10000,
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
    try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope);try journal.markDispatched(job:job,attempt:0)
    func poll(_ poller:NativeLineagePoller)throws {
        guard try poller.beginNext() else {throw JournalError.invalid}
        let end=ProcessInfo.processInfo.systemUptime+2
        while ProcessInfo.processInfo.systemUptime<end {
            if try poller.drain(now:10001) {return}
            Thread.sleep(forTimeInterval:0.001)
        }
        throw NativeControlError.deadline
    }
    let source=NormalRequestEventSource(peer:peer,enabled:true),poller=NativeLineagePoller(journal:journal,source:source)
    try poll(poller)
    guard let pending=try poller.requestEvents(job:job,attempt:0,now:10001),pending.events.rootSequence==UInt64.max,
          pending.events.metal?.pending==1,source.eventReads==1 else {throw JournalError.invalid}
    try poll(poller)
    guard let retired=try poller.requestEvents(job:job,attempt:0,now:10001),retired.events.metal?.retired==2,
          retired.events.metal?.pending==0,try journal.inferenceScope(job:job,attempt:0)?.state == .dispatched,
          try journal.unresolvedCount()==1 else {throw JournalError.invalid}
    guard try poller.requestEvents(job:job,attempt:0,now:16001)==nil else {throw JournalError.invalid}
    // A normal source outage replaces the current observation with absence.
    try poll(poller)
    guard try poller.requestEvents(job:job,attempt:0,now:10001)==nil,try journal.unresolvedCount()==1 else {throw JournalError.invalid}
    let disabled=NormalRequestEventSource(peer:peer,enabled:false),plain=NativeLineagePoller(journal:journal,source:disabled)
    try poll(plain)
    guard disabled.eventReads==0,try plain.requestEvents(job:job,attempt:0,now:10001)==nil else {throw JournalError.invalid}
    let replacement=NativeLineagePoller(journal:journal,source:source)
    guard try replacement.requestEvents(job:job,attempt:0,now:10001)==nil else {throw JournalError.invalid}
    print("PASS: optional off-loop original-request SDK observations progress pending to retired without completing the journal request; unavailable and expired observations remain absent")
}
