import Foundation

protocol NativePreparationReserving:NativeLineageReading {
    func reservePreparation(instance:String,correlationID:String,model:String,lifetimeMilliseconds:UInt32,after sequence:UInt64)throws->NativePreparationSample
}
protocol NativePreparationManaging:NativePreparationReserving {
    func primaryActivity(instance:String,after sequence:UInt64)throws->NativePrimaryActivitySample
    func withdrawPreparation(instance:String,correlationID:String,model:String,rootSequence:UInt64,after sequence:UInt64)throws->NativePreparationSample
}
extension NativeControlClient:NativePreparationManaging {}

// Opaque once-verified receipt identity. Persistence may outlive its timing
// window; neither identity nor a current window is native admission authority.
struct VerifiedNativePreparationRegistration:Sendable {
    let sample:NativePreparationSample
    let verifiedAt:Int64
    fileprivate init(sample:NativePreparationSample,verifiedAt:Int64) {self.sample=sample;self.verifiedAt=verifiedAt}
    var peer:NativeControlPeer {sample.peer}
    var acknowledgement:NativePreparationAcknowledgement {sample.acknowledgement}
    // Necessary timing condition only. Independent all-client compatibility,
    // resource/budget checks and original-plan/native consumption remain needed.
    func leaseWindowIsCurrent(now:Int64)->Bool {
        let start=sample.requestedAt,lifetime=Int64(acknowledgement.lifetimeMilliseconds)
        guard (0...ActivityPolicy.maximumTimestamp).contains(now),now>=verifiedAt,
              let captured=acknowledgement.sourceSampledAt,captured>=start,captured<=sample.receivedAt,
              now>=captured,start<=ActivityPolicy.maximumTimestamp-lifetime else {return false}
        return now<start+lifetime
    }
}
struct PreparedNativeReservation:Sendable {
    let registration:VerifiedNativePreparationRegistration
    // Failure/mismatch does not discard an already verified original identity.
    // Nil cannot authorize launch or resolve independent native uncertainty.
    let lineage:NativeRequestLineageSample?
    let activity:NativePrimaryActivitySample?
    init(registration:VerifiedNativePreparationRegistration,lineage:NativeRequestLineageSample?,activity:NativePrimaryActivitySample?=nil) {
        self.registration=registration;self.lineage=lineage;self.activity=activity
    }
}
final class PendingNativePreparation:@unchecked Sendable {
    private let lock=NSLock()
    private var result:Result<PreparedNativeReservation,NativeControlError>?
    init(source:any NativePreparationReserving,instance:String,correlationID:String,model:String,
         lifetimeMilliseconds:UInt32=5000,after sequence:UInt64) {
        let expectedPeer=source.peer
        Thread.detachNewThread { [self] in
            let completed:Result<PreparedNativeReservation,NativeControlError>
            do {
                guard sequence<=UInt64(ActivityPolicy.maximumTimestamp),expectedPeer.pid>1,expectedPeer.start>0 else {throw NativeControlError.invalid}
                _=try NativePreparationWire.request(operation:.reserve,instance:instance,correlationID:correlationID,model:model,lifetimeMilliseconds:lifetimeMilliseconds)
                let sample=try source.reservePreparation(instance:instance,correlationID:correlationID,model:model,lifetimeMilliseconds:lifetimeMilliseconds,after:sequence)
                let received=HostResources.nowMilliseconds(),ack=sample.acknowledgement
                func samePeer(_ peer:NativeControlPeer)->Bool {
                    peer.pid==expectedPeer.pid && peer.start==expectedPeer.start &&
                    peer.executable.sha256==expectedPeer.executable.sha256 &&
                    peer.executable.path.utf8.elementsEqual(expectedPeer.executable.path.utf8)
                }
                guard samePeer(sample.peer),ack.operation == .reserve,ack.instance==instance,
                      ack.correlationID==correlationID,ack.model.utf8.elementsEqual(model.utf8),ack.rootSequence>0,
                      ack.sampleSequence>sequence,ack.sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
                      ack.lifetimeMilliseconds==lifetimeMilliseconds,
                      (0...ActivityPolicy.maximumTimestamp).contains(received),
                      (0...ActivityPolicy.maximumTimestamp).contains(sample.requestedAt),
                      received>=sample.requestedAt,sample.receivedAt>=sample.requestedAt,sample.receivedAt<=received,
                      received-sample.requestedAt<=5000,
                      ack.sourceSampledAt.map({(1...ActivityPolicy.maximumTimestamp).contains($0)}) ?? true else {throw NativeControlError.invalid}
                let registration=VerifiedNativePreparationRegistration(sample:sample,verifiedAt:received)
                let lineage:NativeRequestLineageSample?
                do {
                    let value=try source.lineage(instance:instance,correlationID:correlationID)
                    let now=HostResources.nowMilliseconds()
                    guard samePeer(value.peer),value.lineage.instance==instance,value.lineage.correlationID==correlationID,
                          value.lineage.rootSequence==ack.rootSequence,value.lineage.found,!value.lineage.uncertain,
                          value.lineage.sampleSequence>ack.sampleSequence,
                          (0...ActivityPolicy.maximumTimestamp).contains(value.sampledAt),
                          (0...ActivityPolicy.maximumTimestamp).contains(now),now>=received,
                          (0...5000).contains(now-value.sampledAt) else {throw NativeControlError.invalid}
                    try value.lineage.validate();lineage=value
                } catch {lineage=nil}
                var activity:NativePrimaryActivitySample?
                if let lineage,let observing=source as? any NativePreparationManaging {
                    do {
                        let sample=try observing.primaryActivity(instance:instance,after:lineage.lineage.sampleSequence)
                        guard samePeer(sample.peer),sample.activity.instance==instance,
                              sample.activity.sampleSequence>lineage.lineage.sampleSequence else {throw NativeControlError.invalid}
                        try sample.activity.validate();try sample.registry?.validate()
                        activity=sample
                    }catch {activity=nil} // Preserve original identity on observation loss.
                }
                completed = .success(PreparedNativeReservation(registration:registration,lineage:lineage,activity:activity))
            } catch {completed = .failure(.unavailable)}
            lock.lock();result=completed;lock.unlock()
        }
    }
    func take()->Result<PreparedNativeReservation,NativeControlError>? {
        lock.lock();defer {lock.unlock()}
        let value=result;result=nil;return value
    }
}

// Cleanup of one known original unconsumed CPU claim only. The result is
// metadata, never not_sent/terminal proof and never a reason to clear a journal.
final class PendingNativePreparationWithdrawal:@unchecked Sendable {
    private let lock=NSLock()
    private var result:Result<NativePreparationSample,NativeControlError>?
    init(source:any NativePreparationManaging,instance:String,correlationID:String,model:String,root:UInt64,after sequence:UInt64) {
        let expected=source.peer
        Thread.detachNewThread { [self] in
            let value:Result<NativePreparationSample,NativeControlError>
            do {
                let sample=try source.withdrawPreparation(instance:instance,correlationID:correlationID,model:model,rootSequence:root,after:sequence)
                let ack=sample.acknowledgement
                guard sample.peer.pid==expected.pid,sample.peer.start==expected.start,
                      sample.peer.executable.path.utf8.elementsEqual(expected.executable.path.utf8),sample.peer.executable.sha256==expected.executable.sha256,
                      ack.operation == .withdraw,ack.instance==instance,ack.correlationID==correlationID,
                      ack.model.utf8.elementsEqual(model.utf8),ack.rootSequence==root,ack.lifetimeMilliseconds==0,ack.sampleSequence>sequence else {throw NativeControlError.invalid}
                value = .success(sample)
            }catch {value = .failure((error as? NativeControlError) ?? .unavailable)}
            lock.lock();result=value;lock.unlock()
        }
    }
    func take()->Result<NativePreparationSample,NativeControlError>? {
        lock.lock();defer {lock.unlock()};let value=result;result=nil;return value
    }
}
