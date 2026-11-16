import Foundation

// Original live plan/receipt binding only. Not a replacement for independent
// compatibility, current source/readiness, budget/resource or native guard checks.
// It creates no process and is not a Codable/bearer dispatch permission.
struct WorkerPreparationBinding:Sendable {
    private let plan:PlannedWorkerStart
    private let registration:VerifiedNativePreparationRegistration
    let peer:NativeControlPeer
    let rootSequence:UInt64
    let correlationID:String
    private init(plan:PlannedWorkerStart,registration:VerifiedNativePreparationRegistration) {
        self.plan=plan;self.registration=registration;peer=registration.peer
        rootSequence=registration.acknowledgement.rootSequence;correlationID=registration.acknowledgement.correlationID
    }
    static func capture(plan:PlannedWorkerStart,journal:Journal,prepared:PreparedNativeReservation,now:Int64)throws->Self {
        let registration=prepared.registration,ack=registration.acknowledgement
        guard registration.leaseWindowIsCurrent(now:now),let lineage=prepared.lineage,
              lineage.peer.pid==registration.peer.pid,lineage.peer.start==registration.peer.start,
              lineage.peer.executable.path.utf8.elementsEqual(registration.peer.executable.path.utf8),
              lineage.peer.executable.sha256==registration.peer.executable.sha256,
              lineage.lineage.instance==ack.instance,lineage.lineage.correlationID==ack.correlationID,
              lineage.lineage.rootSequence==ack.rootSequence,lineage.lineage.found,!lineage.lineage.uncertain,
              lineage.lineage.sampleSequence>ack.sampleSequence,
              lineage.sampledAt>=registration.sample.requestedAt,(0...5000).contains(now-lineage.sampledAt),
              let record=try journal.inferenceScope(job:plan.job,attempt:plan.attempt),record.state == .dispatched,
              try record.scope.encoded()==plan.scope.encoded(),
              ack.instance==plan.scope.nativeEpoch,ack.model.utf8.elementsEqual(plan.scope.nativeModel.utf8),
              ack.correlationID == (try plan.scope.nativeRequestCorrelationID(job:plan.job,attempt:plan.attempt)),
              try journal.activeLaunches().contains(where:{$0.job==plan.job && $0.attempt==plan.attempt && $0.nonce==plan.nonce}),
              try journal.originalNativeRoot(job:plan.job,attempt:plan.attempt,scope:plan.scope,peer:registration.peer)==ack.rootSequence else {throw RuntimeError.identity}
        try lineage.lineage.validate()
        return Self(plan:plan,registration:registration)
    }
    var launchNonce:String {plan.nonce}
    func validate(plan expected:PlannedWorkerStart,scope:InferenceScope,now:Int64)throws {
        guard plan===expected,try plan.scope.encoded()==scope.encoded(),
              registration.leaseWindowIsCurrent(now:now),rootSequence>0,
              scope.nativeEpoch==registration.acknowledgement.instance,
              scope.nativeModel.utf8.elementsEqual(registration.acknowledgement.model.utf8),
              correlationID == (try scope.nativeRequestCorrelationID(job:plan.job,attempt:plan.attempt)) else {throw RuntimeError.identity}
    }
}
