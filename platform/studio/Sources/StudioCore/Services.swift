import Foundation

// Kernel process-start token, not a UTC timestamp or JSON number. Keep this
// internal type non-Codable; any future wire representation must use a strict
// decimal string, as the token may exceed JavaScript's safe-integer range.
struct ServiceIdentity:Equatable,Sendable {
    let pid:Int32
    let start:UInt64
    let sha256:String
    var valid:Bool {
        pid>1 && start>0 && sha256.utf8.count==64 &&
        sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
struct ServiceObservation {
    // nil identity means proven absent, not an unsuccessful/partial probe.
    let identity:ServiceIdentity?
    let responding:Bool
    let sessionReady:Bool
    let credentialsReady:Bool
    let nativeIdle:Bool?
    let runtimeUnmanaged:Bool?
    let sampledAt:Int64
}
enum ServiceAction:Equatable {
    case observe, launch, quit(ServiceIdentity), forceQuit(ServiceIdentity)
    case waitForSession, waitForCredentials, waitForIdle, waitForUnmanaged
}
enum ServiceError:Error { case invalid, stale }

struct ServicePolicy {
    private struct Grant { let service:ManagedService;let identity:ServiceIdentity;let scopeDigest:String;let expires:Int64;let created:Int64;let uptime:TimeInterval }
    private var grants:[String:Grant]=[:]
    private let uptime:@Sendable()->TimeInterval
    init(uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {self.uptime=uptime}
    func action(service:ManagedService,desired:ServiceDesired,observation:ServiceObservation,now:Int64) throws -> ServiceAction {
        guard now>=0,now<=ActivityPolicy.maximumTimestamp,observation.sampledAt>=0,
              (-1000...5000).contains(now-observation.sampledAt) else { throw ServiceError.stale }
        if let identity=observation.identity, !identity.valid { throw ServiceError.invalid }
        guard observation.identity != nil || !observation.responding else {throw ServiceError.invalid}
        if desired == .running && observation.identity == nil {
            if !observation.sessionReady { return .waitForSession }
            if !observation.credentialsReady { return .waitForCredentials }
            return .launch
        }
        guard observation.identity != nil else { return .observe }
        if desired == .maintenance { return .observe } // Drain admissions; retain app/runtime.
        if desired == .running && observation.responding { return .observe }
        guard observation.nativeIdle == true else { return .waitForIdle }
        if service == .orbstack && observation.runtimeUnmanaged != false { return .waitForUnmanaged }
        // A sampled idle boolean is observation, not an admission-closed,
        // process/registry/device-terminal reservation. Until that enrolled
        // native authority is integrated, ordinary stop/restart stays closed.
        // Scope-bound, explicit force remains a separate operator decision.
        return .waitForIdle
    }
    mutating func prepareForce(scope:ServiceAffectedScope,role:ControlRole,now:Int64) throws -> String {
        let tick=uptime()
        guard role == .operator,scope.complete,scope.fresh(now:now),now<=ActivityPolicy.maximumTimestamp-30_000,tick.isFinite,tick>=0 else { throw ServiceError.invalid }
        // At most one outstanding confirmation for each fixed service.
        grants=grants.filter { $0.value.service != scope.service && $0.value.expires>now && tick >= $0.value.uptime && tick-$0.value.uptime<30 }
        let token=UUID().uuidString.lowercased()
        grants[token]=Grant(service:scope.service,identity:scope.identity,scopeDigest:scope.digest,expires:now+30_000,created:now,uptime:tick)
        return token
    }
    mutating func confirmForce(scope:ServiceAffectedScope,role:ControlRole,token:String,now:Int64) throws -> ServiceAction {
        // Consume even a rejected confirmation; no guessing/replay/retargeting.
        let grant=grants.removeValue(forKey:token),tick=uptime()
        guard let grant,role == .operator,scope.complete,scope.fresh(now:now),tick.isFinite,tick>=grant.uptime,tick-grant.uptime<30,
              grant.service==scope.service,grant.identity==scope.identity,grant.scopeDigest==scope.digest,
              now>=grant.created,now<grant.expires else { throw ServiceError.invalid }
        return .forceQuit(scope.identity)
    }
}
