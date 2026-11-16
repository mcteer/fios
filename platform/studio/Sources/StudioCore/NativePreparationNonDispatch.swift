import Foundation

protocol NativePristinePreparationClosing:Sendable {
    var peer:NativeControlPeer {get}
    func closePristinePreparation(instance:String,correlationID:String,model:String,rootSequence:UInt64,after sequence:UInt64)throws->NativePristinePreparationSample
}
extension NativeControlClient:NativePristinePreparationClosing {}

// Original factory no-spawn evidence plus a never-consumed/never-shared native
// lease close. No device completion, all-client idle or capacity interpretation.
final class NativePreparationNonDispatch {
    private let journal:Journal
    private let source:any NativePristinePreparationClosing
    private var queued:[WorkerNeverSpawnedEvidence]=[]
    private var keys:Set<WorkerLaunchKey>=[]
    private var current:WorkerNeverSpawnedEvidence?
    private let slot=PristinePreparationCloseSlot()
    init(journal:Journal,source:any NativePristinePreparationClosing) {self.journal=journal;self.source=source}
    func enqueue(_ evidence:WorkerNeverSpawnedEvidence)throws {
        guard evidence.workerMetadataVersion==3,evidence.handoff==nil,let binding=evidence.preparation else {throw JournalError.conflict}
        try binding.validateIdentity(plan:evidence.plan,scope:evidence.plan.scope)
        let key=WorkerLaunchKey(job:evidence.plan.job,attempt:evidence.plan.attempt)
        guard !keys.contains(key),keys.count<32 else {throw JournalError.conflict}
        keys.insert(key);queued.append(evidence)
    }
    func poll(now:Int64)throws {
        if let current,let reply=slot.peek() {
            // A storage error retains this exact result; no second source call.
            do {_=try journal.resolvePristinePreparationClose(evidence:current,sample:reply.sample,now:now)}
            catch JournalError.conflict { /* Changed/fenced subject remains unresolved. */ }
            keys.remove(WorkerLaunchKey(job:current.plan.job,attempt:current.plan.attempt))
            self.current=nil;slot.clear()
        }
        if current==nil,let evidence=queued.first {
            // Keep queued evidence through a failed intent write. No RPC yet.
            let permitted:Bool
            do {permitted=try journal.beginPristinePreparationClose(evidence:evidence)}
            catch JournalError.conflict {queued.removeFirst();keys.remove(WorkerLaunchKey(job:evidence.plan.job,attempt:evidence.plan.attempt));return}
            queued.removeFirst()
            if permitted {current=evidence;slot.begin(source:source,evidence:evidence)}
            else {keys.remove(WorkerLaunchKey(job:evidence.plan.job,attempt:evidence.plan.attempt))}
        }
    }
    var pending:Bool {current != nil || !queued.isEmpty}
}
private final class PristinePreparationCloseSlot:@unchecked Sendable {
    struct Reply:Sendable {let sample:NativePristinePreparationSample?}
    private let lock=NSLock()
    private var result:Reply?
    func begin(source:any NativePristinePreparationClosing,evidence:WorkerNeverSpawnedEvidence) {
        guard let binding=evidence.preparation else {finish(nil);return}
        let peer=source.peer,expected=binding.peer
        guard peer.pid==expected.pid,peer.start==expected.start,peer.executable.sha256==expected.executable.sha256,
              peer.executable.path.utf8.elementsEqual(expected.executable.path.utf8) else {finish(nil);return}
        Thread.detachNewThread { [self] in
            let scope=evidence.plan.scope
            finish(try? source.closePristinePreparation(instance:scope.nativeEpoch,correlationID:binding.correlationID,
                model:scope.nativeModel,rootSequence:binding.rootSequence,after:binding.registrationSequence))
        }
    }
    private func finish(_ sample:NativePristinePreparationSample?) {lock.lock();result=Reply(sample:sample);lock.unlock()}
    func peek()->Reply? {lock.lock();defer {lock.unlock()};return result}
    func clear() {lock.lock();result=nil;lock.unlock()}
}
