import Foundation

protocol NativeHandoffPreparing:NativeLineageReading,NativeHandoffClosing {
    func registerHandoff(instance:String,correlationID:String)throws->NativeHandoffSample
}
extension NativeControlClient:NativeHandoffPreparing {}

struct PreparedNativeHandoff:Sendable {
    let registration:NativeHandoffSample
    // A verified registration survives a failed later readonly lookup. Missing
    // lineage is identity metadata only and can never start a worker.
    let lineage:NativeRequestLineageSample?
}
// One finite registration/read sequence, off the serialized manager loop.
// No SQLite, spawn, permission bytes, retry, cancellation ACK or claim release.
final class PendingNativeHandoff:@unchecked Sendable {
    private let lock=NSLock()
    private var result:Result<PreparedNativeHandoff,NativeControlError>?
    init(source:any NativeHandoffPreparing,instance:String,correlationID:String) {
        let expectedPeer=source.peer
        Thread.detachNewThread { [self] in
            let completed:Result<PreparedNativeHandoff,NativeControlError>
            do {
                let registration=try source.registerHandoff(instance:instance,correlationID:correlationID)
                func samePeer(_ peer:NativeControlPeer)->Bool {
                    peer.pid==expectedPeer.pid && peer.start==expectedPeer.start &&
                    peer.executable.sha256==expectedPeer.executable.sha256 &&
                    peer.executable.path.utf8.elementsEqual(expectedPeer.executable.path.utf8)
                }
                guard samePeer(registration.peer),
                      registration.result.operation == .register,registration.result.state == .pending,
                      !registration.result.uncertain,registration.result.instance==instance,
                      registration.result.correlationID==correlationID,registration.result.rootSequence>0,
                      registration.result.sampleSequence>0,registration.result.sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp) else {throw NativeControlError.invalid}
                let lineage:NativeRequestLineageSample?
                do {
                    let sample=try source.lineage(instance:instance,correlationID:correlationID)
                    guard samePeer(sample.peer),sample.lineage.instance==instance,
                          sample.lineage.correlationID==correlationID,
                          sample.lineage.rootSequence==registration.result.rootSequence,
                          sample.lineage.found,!sample.lineage.uncertain,
                          sample.lineage.sampleSequence>registration.result.sampleSequence else {throw NativeControlError.invalid}
                    try sample.lineage.validate()
                    lineage=sample
                }catch {lineage=nil}
                completed = .success(PreparedNativeHandoff(registration:registration,lineage:lineage))
            }catch {completed = .failure(.unavailable)}
            lock.lock();result=completed;lock.unlock()
        }
    }
    func take()->Result<PreparedNativeHandoff,NativeControlError>? {
        lock.lock();defer {lock.unlock()}
        let value=result;result=nil;return value
    }
}
