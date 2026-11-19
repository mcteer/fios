import Foundation

// Read-only, present-process status composition. Run off the manager loop:
// two finite census calls bracket a fixed no-inference health probe.
// Matching observations do not prove ownership of the HTTP listening socket. A
// scoped absence is deliberately not promoted into a recovery permission.
// Trusted read-only adapters are transferred together to one collection slot.
// Serialize calls even if an internal fixture retains the collector reference.
final class ServiceHealthCollector:@unchecked Sendable {
    let service:ManagedService
    private let lock=NSLock()
    private let presence:()->ServiceProcessSample
    private let health:()->ServiceHealthState
    private let listener:((ServiceIdentity)->ServiceListenerIdentity?)?
    private let now:()->Int64
    private let uptime:()->TimeInterval

    convenience init(mlxServing profile:MLXServingProcessProfile,probe:ServiceHealthProbe)throws {
        let census=try profile.makeCensus()
        self.init(service:.mlx,presence:census.capture,health:probe.probe,listener:probe.listenerIdentity,
                  now:HostResources.nowMilliseconds,uptime:{ProcessInfo.processInfo.systemUptime})
    }
    convenience init(census:ServiceProcessCensus,probe:OrbStackHealthProbe) {
        self.init(service:.orbstack,presence:census.capture,health:probe.probe,
                  now:HostResources.nowMilliseconds,uptime:{ProcessInfo.processInfo.systemUptime})
    }
    // Internal trusted adapters for ordinary isolated source fixtures only.
    init(service:ManagedService = .mlx,presence:@escaping ()->ServiceProcessSample,health:@escaping ()->ServiceHealthState,listener:((ServiceIdentity)->ServiceListenerIdentity?)?=nil,
         now:@escaping ()->Int64,uptime:@escaping ()->TimeInterval) {
        self.service=service;self.presence=presence;self.health=health;self.listener=listener;self.now=now;self.uptime=uptime
    }
    func capture(sessionReady:Bool,credentialsReady:Bool)->ServiceObservation? {
        lock.lock();defer {lock.unlock()}
        let began=uptime(),collectedAt=now()
        guard began.isFinite,began>=0,(0...ActivityPolicy.maximumTimestamp).contains(collectedAt) else {return nil}
        var previousWall=collectedAt,previousTick=began
        // A slow earlier step cannot start another observation after the
        // collection budget. Compare both clocks between dependent steps.
        func checkpoint()->Int64? {
            let wall=now(),tick=uptime()
            guard (previousWall...ActivityPolicy.maximumTimestamp).contains(wall),tick.isFinite,
                  tick>=previousTick,tick-began<4 else {return nil}
            previousWall=wall;previousTick=tick
            return wall
        }
        let before=presence()
        guard let firstFinished=checkpoint(),case .present(let identity)=before.presence,identity.valid,
              let firstAt=before.sampledAt,(0...firstFinished).contains(firstAt),
              (-1000...5000).contains(collectedAt-firstAt) else {return nil}
        let originalListener=listener?(identity)
        guard (listener==nil || originalListener != nil),checkpoint() != nil else {return nil}
        let state=health()
        guard checkpoint() != nil else {return nil}
        let after=presence()
        guard let lastFinished=checkpoint(),case .present(let current)=after.presence,current==identity,
              after.reviewDigest==before.reviewDigest,after.uid==before.uid,
              let lastAt=after.sampledAt,lastAt>=firstAt,lastAt<=lastFinished else {return nil}
        let currentListener=listener?(identity)
        guard let finished=checkpoint(),listener==nil || currentListener==originalListener else {return nil}
        let original=min(collectedAt,firstAt)
        guard finished-original<=5000 else {return nil}
        return ServiceObservation(identity:identity,responding:state == .healthy,
            sessionReady:sessionReady,credentialsReady:credentialsReady && state != .waitingCredentials,
            nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:original,health:state)
    }
}

// Preserve the existing internal MLX composition label.
typealias MLXServiceHealthCollector = ServiceHealthCollector
