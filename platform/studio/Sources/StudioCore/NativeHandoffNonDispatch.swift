import Foundation

// Neither branch is constructible from a counter, IPC payload or a census.
// The producers preserve the live original handoff and exact local history.
enum WorkerNoPostEvidence:Sendable {
    case neverSpawned(WorkerNeverSpawnedEvidence)
    case reaped(WorkerZeroPostEvidence)
    func binding()throws->WorkerHandoffBinding {
        switch self {
        case .neverSpawned(let proof):
            guard let binding=proof.handoff else {throw RuntimeError.identity}
            try binding.validate(plan:proof.plan,scope:proof.plan.scope)
            return binding
        case .reaped(let proof):return proof.handoff
        }
    }
}

protocol NativeHandoffClosing:Sendable {
    var peer:NativeControlPeer {get}
    func cancelHandoff(instance:String,correlationID:String,rootSequence:UInt64)throws->NativeHandoffSample
}
extension NativeControlClient:NativeHandoffClosing {}

// One in-flight native cancellation, at most32 retained subjects. No retry,
// local exit inference, host-idle proof or device-completion interpretation.
final class NativeHandoffNonDispatch {
    private let source:any NativeHandoffClosing
    private let journal:Journal
    private var queued:[WorkerNoPostEvidence]=[]
    private var keys:Set<WorkerLaunchKey>=[]
    private var current:WorkerNoPostEvidence?
    private let slot=NativeHandoffCancellationSlot()
    init(journal:Journal,source:any NativeHandoffClosing) {self.journal=journal;self.source=source}
    func enqueue(_ evidence:WorkerNoPostEvidence)throws {
        let binding=try evidence.binding(),subject=binding.subject
        guard let record=try journal.inferenceScope(job:subject.job,attempt:subject.attempt),
              [.dispatched,.uncertain].contains(record.state) else {return}
        let key=WorkerLaunchKey(job:subject.job,attempt:subject.attempt)
        guard !keys.contains(key),keys.count<32 else {throw JournalError.conflict}
        keys.insert(key);queued.append(evidence)
    }
    func poll(now:Int64)throws {
        if let current,let reply=slot.peek() {
            // Keep the result across journal contention; never resend the RPC.
            let subject=try current.binding().subject
            if let record=try journal.inferenceScope(job:subject.job,attempt:subject.attempt),[.complete,.not_sent].contains(record.state) {
                guard try record.scope.encoded()==subject.scope.encoded() else {throw JournalError.conflict}
            }else {
                do {_=try journal.resolveClosedHandoff(evidence:current,sample:reply.sample,now:now)}
                catch JournalError.conflict { /* Invalidated subject stays unresolved; no retry or release. */ }
            }
            keys.remove(WorkerLaunchKey(job:subject.job,attempt:subject.attempt))
            self.current=nil;slot.clear()
        }
        if current==nil,!queued.isEmpty {
            let evidence=queued.removeFirst(),binding=try evidence.binding()
            current=evidence
            slot.begin(source:source,binding:binding)
        }
    }
    var pending:Bool {current != nil || !queued.isEmpty}
}

private final class NativeHandoffCancellationSlot:@unchecked Sendable {
    struct Reply:Sendable {let sample:NativeHandoffSample?}
    private let lock=NSLock()
    private var result:Reply?
    func begin(source:any NativeHandoffClosing,binding:WorkerHandoffBinding) {
        let peer=source.peer,expected=binding.peer
        guard peer.pid==expected.pid,peer.start==expected.start,peer.executable.sha256==expected.executable.sha256,
              peer.executable.path.utf8.elementsEqual(expected.executable.path.utf8) else {
            lock.lock();result=Reply(sample:nil);lock.unlock();return
        }
        Thread.detachNewThread { [self] in
            let value=try? source.cancelHandoff(instance:binding.subject.scope.nativeEpoch,correlationID:binding.correlationID,rootSequence:binding.rootSequence)
            lock.lock();result=Reply(sample:value);lock.unlock()
        }
    }
    func peek()->Reply? {lock.lock();defer {lock.unlock()};return result}
    func clear() {lock.lock();result=nil;lock.unlock()}
}
