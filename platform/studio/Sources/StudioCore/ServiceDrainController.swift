import Foundation

// Trusted in-process observation cache only. It is not Codable, has no public
// startup issuer and supplies no native quiescence or action capability.
// Compose ledger fields on the serialized manager owner; background native
// producers must never read Journal/open another SQLite connection.
struct ServiceDrainCacheSnapshot {let value:ServiceDrainSnapshot;let generation:UInt64}

final class ServiceDrainObservationCache:@unchecked Sendable {
    private let lock=NSLock()
    private var values:[ManagedService:ServiceDrainSnapshot]=[:]
    private var generations:[ManagedService:UInt64]=[:]
    private var fenced:Set<ManagedService>=[]
    func publish(_ snapshot:ServiceDrainSnapshot?,for service:ManagedService) {
        lock.lock();defer {lock.unlock()}
        guard !fenced.contains(service) else {return}
        let accepted=snapshot?.scope.service==service ? snapshot:nil
        let same:Bool
        if let old=values[service],let accepted {
            same=old.scope.digest==accepted.scope.digest && old.nativeIdle==accepted.nativeIdle &&
                old.externalNativeWork==accepted.externalNativeWork && old.unmanagedRuntimeWork==accepted.unmanagedRuntimeWork
        }else {same=false}
        if !same {
            let next=(generations[service] ?? 0).addingReportingOverflow(1)
            guard !next.overflow else {fenced.insert(service);values.removeValue(forKey:service);return}
            generations[service]=next.partialValue
        }
        values[service]=accepted
    }
    func versionedSnapshot(for service:ManagedService)->ServiceDrainCacheSnapshot? {
        lock.lock();defer {lock.unlock()}
        guard !fenced.contains(service),let value=values[service],let generation=generations[service] else {return nil}
        return ServiceDrainCacheSnapshot(value:value,generation:generation)
    }
    func snapshot(for service:ManagedService)->ServiceDrainSnapshot? {versionedSnapshot(for:service)?.value}

}

// Serialized manager-side drain coordination. A ready report remains a
// diagnostic decision, never a stop/force permit. There is no native actuator.
final class ServiceDrainController {
    private let journal:Journal
    private let tasks:TaskController
    private let managerEpoch:String
    private let observations:ServiceDrainObservationCache
    private var policy:ServiceDrainPolicy
    private var reports:[ManagedService:ServiceDrainProgress]=[:]
    private var originalOwned:[ManagedService:Set<String>]=[:]
    init(journal:Journal,tasks:TaskController,managerEpoch:String,observations:ServiceDrainObservationCache,
         uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime})throws {
        guard WireScalar.uuid(managerEpoch) else {throw ServiceError.invalid}
        self.journal=journal;self.tasks=tasks;self.managerEpoch=managerEpoch;self.observations=observations
        policy=ServiceDrainPolicy(uptime:uptime)
    }
    private func current(_ service:ManagedService,now:Int64,original:Set<String>?=nil)throws->ServiceDrainSnapshot {
        guard let value=observations.snapshot(for:service),value.scope.service==service,
              value.scope.managerEpoch==managerEpoch,value.scope.fresh(now:now) else {throw ServiceError.stale}
        let jobs=try journal.jobs(),known=Set(jobs.map(\.id))
        // Never revoke a caller/cache-invented job or accept omitted durable
        // uncertainty as drain readiness. Full native proof remains separate.
        guard let requests=try journal.unresolvedRequestIDs(),
              Set(value.scope.ownedJobs).isSubset(of:known),
              Set(value.scope.unresolvedManagedRequests)==Set(requests) else {throw ServiceError.invalid}
        if let original {
            let remaining=Set(jobs.filter {original.contains($0.id) && $0.state != .removed}.map(\.id))
            guard remaining.isSubset(of:Set(value.scope.ownedJobs)) else {throw ServiceError.invalid}
        }
        return value
    }
    private func revoke(_ progress:ServiceDrainProgress,now:Int64,uptime:Int64)throws {
        let owned=Dictionary(uniqueKeysWithValues:try journal.jobs().map {($0.id,$0.ownerHash)})
        for id in progress.revokeOwned {
            guard let owner=owned[id] else {throw ServiceError.invalid}
            try tasks.cancel(id:id,owner:owner,now:now,uptime:uptime)
        }
    }
    func begin(service:ManagedService,role:ControlRole,now:Int64,uptime:Int64)throws->ServiceDrainProgress {
        guard role == .operator else {throw ServiceError.invalid}
        let snapshot=try current(service,now:now)
        // Commit this independent admission fence before any owned job can be
        // cancelled. Failure never rolls maintenance back or clears claims.
        try journal.setDesired(service:service.rawValue,desired:ServiceDesired.maintenance.rawValue)
        let progress=try policy.begin(snapshot:snapshot,role:role,now:now)
        reports[service]=progress;originalOwned[service]=Set(snapshot.scope.ownedJobs)
        try revoke(progress,now:now,uptime:uptime)
        return progress
    }
    func poll(service:ManagedService,now:Int64,uptime:Int64)throws->ServiceDrainProgress {
        guard reports[service] != nil,let original=originalOwned[service] else {throw ServiceError.invalid}
        let snapshot:ServiceDrainSnapshot
        do {snapshot=try current(service,now:now,original:original)}
        catch ServiceError.stale {let value=try policy.invalidate(service:service);reports[service]=value;return value}
        catch ServiceError.invalid {let value=try policy.invalidate(service:service);reports[service]=value;return value}
        let progress=try policy.poll(snapshot:snapshot,now:now)
        reports[service]=progress
        try revoke(progress,now:now,uptime:uptime)
        return progress
    }
    func pollAll(now:Int64,uptime:Int64)throws {
        for service in Array(reports.keys) {_=try poll(service:service,now:now,uptime:uptime)}
    }
    // A newer explicit operator desired-running intent supersedes the drain
    // report. Already revoked jobs/uncertainty are never resumed/refunded.
    func supersede(service:ManagedService) {reports.removeValue(forKey:service);originalOwned.removeValue(forKey:service)}
    func status(service:ManagedService)->ServiceDrainProgress? {reports[service]}
    static func summary(_ progress:ServiceDrainProgress)->[String:Any] {
        var result:[String:Any]=["admission_closed":true,"revocations_requested":progress.revokeOwned.count,"native_action_applied":false]
        switch progress.state {
        case .draining:result["state"]="draining"
        case .ready:result["state"]="ready"
        case .refused(let reason):
            result["state"]="refused"
            switch reason {
            case .activityUnknown:result["reason"]="activity_unknown"
            case .activeWork:result["reason"]="active_work"
            case .deadline:result["reason"]="deadline"
            case .scopeChanged:result["reason"]="scope_changed"
            }
        }
        return result
    }
}
