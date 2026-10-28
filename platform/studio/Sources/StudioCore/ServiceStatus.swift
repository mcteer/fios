import Foundation

// Observation classification only. No returned state is native terminality,
// a launch/stop permit, or authority to clear uncertainty. Inputs must come
// from trusted identity-bound adapters; nil explicitly means no such source.
// Bounded precollected metadata only: the manager never invokes adapter I/O
// on its control loop. This cache is per-manager, not restored across epochs.
final class ServiceObservationCache {
    private let lock=NSLock()
    private var values:[ManagedService:ServiceObservation]=[:]
    func publish(_ value:ServiceObservation?,for service:ManagedService) {
        lock.lock();defer {lock.unlock()};values[service]=value
    }
    func snapshot(for service:ManagedService)->ServiceObservation? {
        lock.lock();defer {lock.unlock()};return values[service]
    }
}

enum ServiceStatusPolicy {
    static func observed(desired:ServiceDesired,observation:ServiceObservation?,launchPending:Bool,now:Int64)->ServiceObserved {
        guard let observation,now>=0,now<=ActivityPolicy.maximumTimestamp,
              observation.sampledAt>=0,observation.sampledAt<=ActivityPolicy.maximumTimestamp,
              (-1000...5000).contains(now-observation.sampledAt) else {return .unknown}
        if let identity=observation.identity {
            guard identity.valid else {return .unknown}
            if !observation.credentialsReady {return .waiting_credentials}
            if observation.responding {return .ready}
            return launchPending ? .starting:.degraded
        }
        // Identity=nil is the adapter's proven absence, NOT a failed probe.
        guard !observation.responding else {return .unknown}
        if desired == .running {
            if !observation.sessionReady {return .waiting_session}
            if !observation.credentialsReady {return .waiting_credentials}
        }
        // Desired-running is not evidence that launch has actually begun.
        return launchPending ? .starting:.stopped
    }
}
