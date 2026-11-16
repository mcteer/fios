import Foundation

protocol NativeHandoffPreparing:NativeLineageReading {
    func registerHandoff(instance:String,correlationID:String)throws->NativeHandoffSample
}
extension NativeControlClient:NativeHandoffPreparing {}

struct PreparedNativeHandoff:Sendable {
    let registration:NativeHandoffSample
    let lineage:NativeRequestLineageSample
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
                let lineage=try source.lineage(instance:instance,correlationID:correlationID)
                func samePeer(_ peer:NativeControlPeer)->Bool {
                    peer.pid==expectedPeer.pid && peer.start==expectedPeer.start &&
                    peer.executable.sha256==expectedPeer.executable.sha256 &&
                    peer.executable.path.utf8.elementsEqual(expectedPeer.executable.path.utf8)
                }
                guard samePeer(registration.peer),samePeer(lineage.peer),
                      registration.result.operation == .register,registration.result.state == .pending,
                      !registration.result.uncertain,registration.result.instance==instance,
                      registration.result.correlationID==correlationID,registration.result.rootSequence>0,
                      registration.result.sampleSequence>0,registration.result.sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
                      lineage.lineage.instance==instance,lineage.lineage.correlationID==correlationID,
                      lineage.lineage.rootSequence==registration.result.rootSequence,
                      lineage.lineage.found,!lineage.lineage.uncertain,
                      lineage.lineage.sampleSequence>registration.result.sampleSequence else {throw NativeControlError.invalid}
                try lineage.lineage.validate()
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
