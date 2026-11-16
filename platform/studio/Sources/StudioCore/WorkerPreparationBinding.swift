import Foundation

// Original live plan/receipt binding only. Not a replacement for independent
// compatibility, current source/readiness, budget/resource or native guard checks.
// It creates no process and is not a Codable/bearer dispatch permission.
struct WorkerPreparationBinding:Sendable {
    private let plan:PlannedWorkerStart
    private let registration:VerifiedNativePreparationRegistration
    private let checkpoint:PreparationBindingCheckpoint
    let peer:NativeControlPeer
    let rootSequence:UInt64
    let correlationID:String
    private init(plan:PlannedWorkerStart,registration:VerifiedNativePreparationRegistration,checkpoint:PreparationBindingCheckpoint) {
        self.plan=plan;self.registration=registration;self.checkpoint=checkpoint;peer=registration.peer
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
        return Self(plan:plan,registration:registration,checkpoint:try journal.preparationBindingCheckpoint(plan:plan,peer:registration.peer,root:ack.rootSequence))
    }
    var launchNonce:String {plan.nonce}
    func validateIdentity(plan expected:PlannedWorkerStart,scope:InferenceScope)throws {
        guard plan===expected else {throw RuntimeError.identity}
        try validateIdentity(job:plan.job,attempt:plan.attempt,scope:scope)
    }
    // Identity only, for an already-started/reaped child or unused-plan cleanup.
    // This cannot renew a lease or authorize launch after a source change.
    func validateIdentity(job:String,attempt:Int,scope:InferenceScope)throws {
        guard job==plan.job,attempt==plan.attempt,try plan.scope.encoded()==scope.encoded(),rootSequence>0,
              scope.nativeEpoch==registration.acknowledgement.instance,
              scope.nativeModel.utf8.elementsEqual(registration.acknowledgement.model.utf8),
              correlationID == (try scope.nativeRequestCorrelationID(job:job,attempt:attempt)) else {throw RuntimeError.identity}
    }
    func validate(plan expected:PlannedWorkerStart,scope:InferenceScope,journal:Journal,now:Int64)throws {
        guard plan===expected,try plan.scope.encoded()==scope.encoded(),
              try journal.preparationBindingCheckpoint(plan:plan,peer:peer,root:rootSequence)==checkpoint,
              registration.leaseWindowIsCurrent(now:now),rootSequence>0,
              scope.nativeEpoch==registration.acknowledgement.instance,
              scope.nativeModel.utf8.elementsEqual(registration.acknowledgement.model.utf8),
              correlationID == (try scope.nativeRequestCorrelationID(job:plan.job,attempt:plan.attempt)) else {throw RuntimeError.identity}
    }
}

// Readonly subject only. No endpoint, model, lease or authority can be selected
// by this request; the original live plan supplies all of those identities.
struct NativePreparationSubject:Sendable,Equatable {
    let job:String
    let attempt:Int
    let rootSequence:UInt64
    let correlationID:String
    init(payload:[String:Any])throws {
        guard Set(payload.keys)==Set(["job_id","attempt","root_sequence","correlation_id"]),
              let job=payload["job_id"] as? String,WireScalar.uuid(job),
              let attempt=WireScalar.integer(payload["attempt"],maximum:3),
              let text=payload["root_sequence"] as? String,(1...20).contains(text.utf8.count),text.first != "0",
              text.utf8.allSatisfy({(48...57).contains($0)}),let root=UInt64(text),root>0,String(root)==text,
              let correlation=payload["correlation_id"] as? String,WireScalar.sha256(correlation) else {throw ControlError.invalid_request}
        self.job=job;self.attempt=Int(attempt);rootSequence=root;correlationID=correlation
    }
}

// A checked original-scope observation, not a bearer/native dispatch grant.
// Only the original binding's evaluator below constructs it. A cached result
// cannot survive a later journal observation/state change or renew its lease.
struct NativePreparationObservation:Sendable {
    private let plan:PlannedWorkerStart
    private let registration:VerifiedNativePreparationRegistration
    private let checkpoint:PreparationBindingCheckpoint
    private let sourceSampledAt:Int64
    private let payload:Data
    fileprivate init(plan:PlannedWorkerStart,registration:VerifiedNativePreparationRegistration,checkpoint:PreparationBindingCheckpoint,
                     sourceSampledAt:Int64,payload:Data) {
        self.plan=plan;self.registration=registration;self.checkpoint=checkpoint;self.sourceSampledAt=sourceSampledAt;self.payload=payload
    }
    func encoded(subject:NativePreparationSubject,managerEpoch:String,journal:Journal,now:Int64)throws->Data {
        let ack=registration.acknowledgement
        guard subject.job==plan.job,subject.attempt==plan.attempt,subject.rootSequence==ack.rootSequence,
              subject.correlationID==ack.correlationID,managerEpoch==plan.scope.managerEpoch,
              registration.leaseWindowIsCurrent(now:now),(0...5000).contains(now-sourceSampledAt),
              try journal.unresolvedCount()==1,
              try journal.preparationBindingCheckpoint(plan:plan,peer:registration.peer,root:ack.rootSequence)==checkpoint,
              var job=try journal.jobs().first(where:{$0.id==plan.job}),job.state == .running,job.lease.valid(now:now) else {throw RuntimeError.identity}
        return payload
    }
}
extension WorkerPreparationBinding {
    func observation(lineage:NativeRequestLineageSample,activity:NativePrimaryActivitySample,journal:Journal,
                     sourceCoverage:NativeCoverage = .unknown,now:Int64)throws->NativePreparationObservation? {
        guard let value=NativeOwnedPreparationCoherence.evaluate(registration:registration,lineage:lineage,activity:activity,sourceCoverage:sourceCoverage,now:now),
              let stamp=activity.registry?.primary.sampledAt,try journal.unresolvedCount()==1,
              var job=try journal.jobs().first(where:{$0.id==plan.job}),job.state == .running,job.lease.valid(now:now) else {return nil}
        let ack=registration.acknowledgement
        let current=try journal.preparationBindingCheckpoint(plan:plan,peer:peer,root:rootSequence)
        guard current==checkpoint else {return nil}
        let object:[String:Any]=["version":1,"host":plan.scope.host,"endpoint_hash":plan.scope.endpointHash,
            "profile_hash":plan.scope.profileHash,"manager_epoch":plan.scope.managerEpoch,"native_epoch":plan.scope.nativeEpoch,
            "job_id":plan.job,"attempt":plan.attempt,"canonical_model":plan.scope.canonicalModel,"native_model":ack.model,
            "root_sequence":String(rootSequence),"correlation_id":correlationID,"source_coverage":"all_clients",
            "reservation_sequence":ack.sampleSequence,"lineage_sequence":lineage.lineage.sampleSequence,"native_sequence":value.sourceSequence,
            "source_sampled_at":stamp,"lease_requested_at":registration.sample.requestedAt,
            "lease_expires_at":registration.sample.requestedAt+Int64(ack.lifetimeMilliseconds),
            "registry_generation":value.registryGeneration,"registry_ready_model":value.registryReadyModel.map{$0 as Any} ?? NSNull()]
        let data=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
        guard data.count<=8192 else {throw RuntimeError.invalid}
        return NativePreparationObservation(plan:plan,registration:registration,checkpoint:current,sourceSampledAt:stamp,payload:data)
    }
}
