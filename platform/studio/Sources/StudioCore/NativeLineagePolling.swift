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
    }
    private let journal:Journal
    private let source:any NativeLineageReading
    private let peer:NativeControlPeer
    private let lock=NSLock()
    private var busy=false
    private var reply:Reply?
    private var cursor=0
    init(journal:Journal,source:any NativeLineageReading) {
        self.journal=journal;self.source=source;peer=source.peer
    }
    @discardableResult func beginNext()throws->Bool {
        lock.lock();let available = !busy && reply==nil;lock.unlock()
        guard available else {return false}
        let requests=try journal.lineageRequests()
        guard !requests.isEmpty else {cursor=0;return false}
        let index=cursor % requests.count,request=requests[index]
        let correlation=try request.scope.nativeRequestCorrelationID(job:request.job,attempt:request.attempt)
        lock.lock()
        guard !busy,reply==nil else {lock.unlock();return false}
        busy=true;lock.unlock()
        cursor=(index+1)%requests.count
        Thread.detachNewThread { [self] in
            let sample=try? source.lineage(instance:request.scope.nativeEpoch,correlationID:correlation)
            lock.lock();reply=Reply(request:request,sample:sample);busy=false;lock.unlock()
        }
        return true
    }
    @discardableResult func drain(now:Int64)throws->Bool {
        lock.lock();let completed=reply;reply=nil;lock.unlock()
        guard let completed else {return false}
        let request=completed.request
        // Normal completion/pruning can happen while the readonly call runs.
        // A late diagnostic must never resurrect or rewrite terminal ownership.
        guard let current=try journal.inferenceScope(job:request.job,attempt:request.attempt),
              [.dispatched,.uncertain].contains(current.state),
              try current.scope.encoded()==request.scope.encoded() else {return true}
        _=try journal.observeLineage(job:request.job,attempt:request.attempt,scope:request.scope,
            peer:peer,sample:completed.sample,now:now)
        return true
    }
}
