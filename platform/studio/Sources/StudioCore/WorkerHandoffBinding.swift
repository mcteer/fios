import Foundation

// Original native identity, not model admission or completion evidence. Only
// a live original launch plan and its already-checkpointed scope can bind it.
struct WorkerHandoffBinding:Sendable {
    private let plan:PlannedWorkerStart
    private let allowsLaunch:Bool
    let peer:NativeControlPeer
    let rootSequence:UInt64
    let correlationID:String
    private init(plan:PlannedWorkerStart,peer:NativeControlPeer,rootSequence:UInt64,correlationID:String,allowsLaunch:Bool) {
        self.plan=plan;self.peer=peer;self.rootSequence=rootSequence;self.correlationID=correlationID;self.allowsLaunch=allowsLaunch
    }
    static func capture(plan:PlannedWorkerStart,journal:Journal,peer:NativeControlPeer)throws->Self {
        try capture(plan:plan,journal:journal,peer:peer,allowsLaunch:true)
    }
    static func captureForNonDispatch(plan:PlannedWorkerStart,journal:Journal,peer:NativeControlPeer)throws->Self {
        try capture(plan:plan,journal:journal,peer:peer,allowsLaunch:false)
    }
    private static func capture(plan:PlannedWorkerStart,journal:Journal,peer:NativeControlPeer,allowsLaunch:Bool)throws->Self {
        guard let record=try journal.inferenceScope(job:plan.job,attempt:plan.attempt),
              (allowsLaunch ? record.state == .dispatched:[.dispatched,.uncertain].contains(record.state)),
              try record.scope.encoded()==plan.scope.encoded(),
              try journal.activeLaunches().contains(where:{$0.job==plan.job && $0.attempt==plan.attempt && $0.nonce==plan.nonce}),
              let root=try journal.originalNativeRoot(job:plan.job,attempt:plan.attempt,scope:plan.scope,peer:peer) else {throw RuntimeError.identity}
        _=try NativeControlWire.instanceBytes(plan.scope.nativeEpoch)
        return Self(plan:plan,peer:peer,rootSequence:root,correlationID:try plan.scope.nativeRequestCorrelationID(job:plan.job,attempt:plan.attempt),allowsLaunch:allowsLaunch)
    }
    var subject:NativeLineageRequest {NativeLineageRequest(job:plan.job,attempt:plan.attempt,scope:plan.scope)}
    var launchNonce:String {plan.nonce}
    func validateForLaunch(plan:PlannedWorkerStart,scope:InferenceScope)throws {
        guard allowsLaunch else {throw RuntimeError.identity}
        try validate(plan:plan,scope:scope)
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
