import Foundation

struct ServiceForceChallenge {
    let token:String
    let scopeDigest:String
}

// Serialized manager-side consent coordination, not an actuator or native
// quiescence permit. Inputs must come from a trusted in-process scope issuer.
// No public startup issuer is wired; task/model JSON cannot construct scope.
final class ServiceForceController {
    private let journal:Journal
    private let managerEpoch:String
    private let observations:ServiceDrainObservationCache
    private var policy:ServicePolicy
    private var challenges:[ManagedService:(token:String,generation:UInt64,intentGeneration:UInt64)]=[:]
    init(journal:Journal,managerEpoch:String,observations:ServiceDrainObservationCache,
         uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime})throws {
        guard WireScalar.uuid(managerEpoch) else {throw ServiceError.invalid}
        self.journal=journal;self.managerEpoch=managerEpoch;self.observations=observations
        policy=ServicePolicy(uptime:uptime)
    }
    private func current(_ service:ManagedService,now:Int64)throws->ServiceDrainCacheSnapshot {
        guard let current=observations.versionedSnapshot(for:service) else {throw ServiceError.invalid}
        let value=current.value
        guard value.scope.service==service,
              value.scope.managerEpoch==managerEpoch,value.scope.complete,value.scope.fresh(now:now),
              value.nativeIdle != nil,value.externalNativeWork != nil,
              service != .orbstack || value.unmanagedRuntimeWork != nil else {throw ServiceError.invalid}
        let known=Set(try journal.jobs().map(\.id))
        guard Set(value.scope.ownedJobs).isSubset(of:known),
              value.scope.unresolvedManagedRequests.count == (try journal.unresolvedCount()) else {throw ServiceError.invalid}
        return current
    }
    func prepare(service:ManagedService,role:ControlRole,now:Int64)throws->ServiceForceChallenge {
        guard role == .operator else {throw ServiceError.invalid}
        let current=try current(service,now:now),scope=current.value.scope
        // Durable admission closure precedes even issuing consent. A failure
        // leaves no new token and never restores a previous running intent.
        try journal.setDesired(service:service.rawValue,desired:ServiceDesired.maintenance.rawValue)
        guard let intentGeneration=journal.serviceIntentGeneration(service:service) else {throw ServiceError.invalid}
        let token=try policy.prepareForce(scope:scope,role:role,now:now)
        challenges[service]=(token,current.generation,intentGeneration)
        return ServiceForceChallenge(token:token,scopeDigest:scope.digest)
    }
    private func consume(token:String) {
        policy.discardForce(token:token)
        for key in Array(challenges.keys) where challenges[key]?.token==token {challenges.removeValue(forKey:key)}
    }
    func confirm(service:ManagedService,role:ControlRole,token:String,scopeDigest:String,now:Int64)throws->ServiceAction {
        // Every attempted confirmation consumes both volatile bindings, even
        // if source/role/intent/digest validation fails before policy lookup.
        defer {consume(token:token)}
        guard role == .operator,WireScalar.sha256(scopeDigest),
              try journal.recordedDesired(service:service) == .maintenance else {throw ServiceError.invalid}
        let current=try current(service,now:now),scope=current.value.scope
        guard let challenge=challenges[service],challenge.token==token,challenge.generation==current.generation,
              challenge.intentGeneration==journal.serviceIntentGeneration(service:service),
              scope.digest==scopeDigest else {throw ServiceError.invalid}
        // Returned action is an intent only. A separately enrolled actuator
        // must revalidate immutable image, exact process and affected scope.
        return try policy.confirmForce(scope:scope,role:role,token:token,now:now)
    }
}
