import Foundation

protocol NativeLineageReading:Sendable {
    var peer:NativeControlPeer {get}
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample
}
extension NativeControlClient:NativeLineageReading {}

struct NativeLineageRequest:Sendable {
    let job:String
    let attempt:Int
    let scope:InferenceScope
}

// The manager owns journal/cursor access. Only the fixed readonly native call
// runs off-loop; its one result slot remains occupied until actually consumed.
// No model, lifecycle action, retry, terminal proof or admission is issued.
final class NativeLineagePoller:@unchecked Sendable {
    private struct Reply:Sendable {
        let request:NativeLineageRequest
        let sample:NativeRequestLineageSample?
        let events:NativeRequestEventsSample?
    }
    private struct Key:Hashable {let job:String;let attempt:Int}
    private struct EventRecord {let request:NativeLineageRequest;let sample:NativeRequestEventsSample;let lineage:NativeRequestLineageSample?}
    private let journal:Journal
    private let source:any NativeLineageReading
    private let peer:NativeControlPeer
    private let lock=NSLock()
    private var busy=false
    private var reply:Reply?
    private var lastPolled:Key?
    // Current diagnostics only; deliberately absent from journal checkpoints.
    private var eventSamples:[Key:EventRecord]=[:]
    init(journal:Journal,source:any NativeLineageReading) {
        self.journal=journal;self.source=source;peer=source.peer
    }
    @discardableResult func beginNext()throws->Bool {
        lock.lock();let available = !busy && reply==nil;lock.unlock()
        guard available else {return false}
        let requests=try journal.lineageRequests()
        let current=Set(requests.map {Key(job:$0.job,attempt:$0.attempt)})
        eventSamples=eventSamples.filter {current.contains($0.key)}
        guard let first=requests.first else {lastPolled=nil;return false}
        // Journal rows are ordered by job and attempt. Preserve that order
        // across requests completing while a read is in flight.
        let request=lastPolled.flatMap { previous in
            requests.first { ($0.job,$0.attempt) > (previous.job,previous.attempt) }
        } ?? first
        let correlation=try request.scope.nativeRequestCorrelationID(job:request.job,attempt:request.attempt)
        let eventSource=source as? any NativeRequestEventsReading
        let collectEvents=eventSource?.observesRequestEvents == true
        let originalRoot=collectEvents ? try journal.originalNativeRoot(job:request.job,attempt:request.attempt,scope:request.scope,peer:peer):nil
        lock.lock()
        guard !busy,reply==nil else {lock.unlock();return false}
        busy=true;lock.unlock()
        lastPolled=Key(job:request.job,attempt:request.attempt)
        Thread.detachNewThread { [self] in
            let sample=try? source.lineage(instance:request.scope.nativeEpoch,correlationID:correlation)
            let root=sample.flatMap {$0.lineage.found ? $0.lineage.rootSequence:nil} ?? originalRoot
            let events:NativeRequestEventsSample?
            if collectEvents,let root,let eventSource {
                events=try? eventSource.requestEvents(instance:request.scope.nativeEpoch,correlationID:correlation,rootSequence:root)
            }else {events=nil}
            lock.lock();reply=Reply(request:request,sample:sample,events:events);busy=false;lock.unlock()
        }
        return true
    }
    @discardableResult func drain(now:Int64)throws->Bool {
        lock.lock();let completed=reply;reply=nil;lock.unlock()
        guard let completed else {return false}
        let request=completed.request
        let key=Key(job:request.job,attempt:request.attempt)
        eventSamples.removeValue(forKey:key)
        // Normal completion/pruning can happen while the readonly call runs.
        // A late diagnostic must never resurrect or rewrite terminal ownership.
        guard let current=try journal.inferenceScope(job:request.job,attempt:request.attempt),
              [.dispatched,.uncertain].contains(current.state),
              try current.scope.encoded()==request.scope.encoded() else {return true}
        let observation=try journal.observeLineage(job:request.job,attempt:request.attempt,scope:request.scope,
            peer:peer,sample:completed.sample,now:now)
        if let sample=completed.events {
            let lineage:NativeRequestLineageSample?
            if case .live=observation {lineage=completed.sample}else {lineage=nil}
            eventSamples[key]=EventRecord(request:request,sample:sample,lineage:lineage)
            if try requestEvents(job:request.job,attempt:request.attempt,now:now)==nil {eventSamples.removeValue(forKey:key)}
        }
        return true
    }
    // Read on the manager's journal thread. Callback retirement is diagnostic;
    // this method never resolves an inference or changes its reservation.
    func requestEvents(job:String,attempt:Int,now:Int64)throws->NativeRequestEventsSample? {
        guard let record=eventSamples[Key(job:job,attempt:attempt)] else {return nil}
        let request=record.request,sample=record.sample,value=sample.events
        guard let current=try journal.inferenceScope(job:job,attempt:attempt),
              [.dispatched,.uncertain].contains(current.state),try current.scope.encoded()==request.scope.encoded(),
              let root=try journal.originalNativeRoot(job:job,attempt:attempt,scope:request.scope,peer:peer),
              root==value.rootSequence,value.instance==request.scope.nativeEpoch,
              value.correlationID == (try request.scope.nativeRequestCorrelationID(job:job,attempt:attempt)),
              sample.peer.pid==peer.pid,sample.peer.start==peer.start,
              sample.peer.executable.path.utf8.elementsEqual(peer.executable.path.utf8),sample.peer.executable.sha256==peer.executable.sha256,
              [now,sample.requestedAt,sample.receivedAt,value.sampledAt].allSatisfy({(0...ActivityPolicy.maximumTimestamp).contains($0)}),
              sample.requestedAt<=sample.receivedAt,sample.receivedAt-sample.requestedAt<=5000,
              (-1000...5000).contains(now-sample.receivedAt),(-1000...5000).contains(now-value.sampledAt),
              (try? value.validate()) != nil else {return nil}
        return sample
    }
    func requestEventStatuses(job:String,now:Int64)throws->[NativeRequestEventStatus] {
        var result:[NativeRequestEventStatus]=[]
        for request in try journal.lineageRequests() where request.job==job {
            if let sample=try requestEvents(job:job,attempt:request.attempt,now:now) {
                let cached=eventSamples[Key(job:job,attempt:request.attempt)]?.lineage
                let lineage=cached.flatMap { value->NativeRequestLineageSample? in
                    guard (-1000...5000).contains(now-value.sampledAt) else {return nil}
                    if let captured=value.lineage.sourceCapturedAt,!(-1000...5000).contains(now-captured) {return nil}
                    return value
                }
                result.append(NativeRequestEventStatus(attempt:request.attempt,sample:sample,lineage:lineage))
            }
        }
        return result
    }
}
