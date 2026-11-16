import Foundation

// Original native identity, not model admission or completion evidence. Only
// a live original launch plan and its already-checkpointed scope can bind it.
struct WorkerHandoffBinding:Sendable {
    private let plan:PlannedWorkerStart
    let peer:NativeControlPeer
    let rootSequence:UInt64
    let correlationID:String
    private init(plan:PlannedWorkerStart,peer:NativeControlPeer,rootSequence:UInt64,correlationID:String) {
        self.plan=plan;self.peer=peer;self.rootSequence=rootSequence;self.correlationID=correlationID
    }
    static func capture(plan:PlannedWorkerStart,journal:Journal,peer:NativeControlPeer)throws->Self {
        guard let record=try journal.inferenceScope(job:plan.job,attempt:plan.attempt),record.state == .dispatched,
              try record.scope.encoded()==plan.scope.encoded(),
              try journal.activeLaunches().contains(where:{$0.job==plan.job && $0.attempt==plan.attempt && $0.nonce==plan.nonce}),
              let root=try journal.originalNativeRoot(job:plan.job,attempt:plan.attempt,scope:plan.scope,peer:peer) else {throw RuntimeError.identity}
        _=try NativeControlWire.instanceBytes(plan.scope.nativeEpoch)
        return Self(plan:plan,peer:peer,rootSequence:root,correlationID:try plan.scope.nativeRequestCorrelationID(job:plan.job,attempt:plan.attempt))
    }
    func validate(plan expected:PlannedWorkerStart,scope:InferenceScope)throws {
        guard plan===expected else {throw RuntimeError.identity}
        try validate(job:expected.job,attempt:expected.attempt,scope:scope)
    }
    func validate(job:String,attempt:Int,scope:InferenceScope)throws {
        guard job==plan.job,attempt==plan.attempt,try scope.encoded()==plan.scope.encoded(),
              rootSequence>0,correlationID == (try scope.nativeRequestCorrelationID(job:job,attempt:attempt)) else {throw RuntimeError.identity}
    }
}
