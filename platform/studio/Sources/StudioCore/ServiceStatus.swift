import Foundation

// Observation classification only. No returned state is native terminality,
// a launch/stop permit, or authority to clear uncertainty. Inputs must come
// from trusted identity-bound adapters; nil explicitly means no such source.
// Bounded precollected metadata only: the manager never invokes adapter I/O
// on its control loop. This cache is per-manager, not restored across epochs.
final class ServiceObservationCache:@unchecked Sendable {
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
    static func summary(desired:ServiceDesired,observation:ServiceObservation?,launchPending:Bool,now:Int64,restartWaiting:Bool=false)->[String:Any] {
        let observed=observed(desired:desired,observation:observation,launchPending:launchPending,now:now,restartWaiting:restartWaiting)
        var value:[String:Any]=["desired":desired.rawValue,"observed":observed.rawValue,"launch_pending":launchPending,
                                "message":message(desired:desired,observed:observed,observation:observation,restartWaiting:restartWaiting),
                                "sampled_at":NSNull(),"age_ms":NSNull()]
        if let time=observation?.sampledAt,(0...ActivityPolicy.maximumTimestamp).contains(time),
           (0...ActivityPolicy.maximumTimestamp).contains(now) {
            value["sampled_at"]=time;value["age_ms"]=now-time
        }
        if observed != .unknown,observation?.identity?.valid==true,let health=observation?.health {
            value["health"]=health.statusLabel
        }
        return value
    }
    private static func message(desired:ServiceDesired,observed:ServiceObserved,observation:ServiceObservation?,restartWaiting:Bool)->String {
        if observed == .unknown {return "Service status is unavailable."}
        if observed == .ready {
            switch desired {
            case .running:return "Service is running."
            case .stopped:return "Service is still running; stop is requested."
            case .maintenance:return "Service is running; maintenance is requested."
            }
        }
        if observed == .stopped {
            switch desired {
            case .running:return "Service is stopped; running is requested."
            case .stopped:return "Service is stopped."
            case .maintenance:return "Service is stopped; maintenance is requested."
            }
        }
        let detail:String
        switch observed {
        case .starting:
            detail=observation?.health == .loading ? "Service is loading.":
                observation?.identity == nil ? "Service startup is pending.":"Service is starting."
        case .waiting_session:detail="Waiting for a user session."
        case .waiting_credentials:detail="Waiting for service credentials."
        case .degraded:
            if desired == .running && restartWaiting {
                detail=observation?.identity == nil ?
                    "Service is stopped; automatic startup is waiting for the restart limit to reset.":
                    "Service is not responding; automatic recovery is waiting for the restart limit to reset."
            } else {detail="Service is present but not responding."}
        case .ready,.stopped,.unknown:return "Service status is unavailable."
        }
        switch desired {
        case .running:return detail
        case .stopped:return detail+" Stop is requested."
        case .maintenance:return detail+" Maintenance is requested."
        }
    }
    static func observed(desired:ServiceDesired,observation:ServiceObservation?,launchPending:Bool,now:Int64,restartWaiting:Bool=false)->ServiceObserved {
        guard let observation,observation.fresh(now:now) else {return .unknown}
        if let identity=observation.identity {
            guard identity.valid else {return .unknown}
            if desired == .running && !observation.responding && !observation.sessionReady {return .waiting_session}
            if !observation.credentialsReady {return .waiting_credentials}
            if observation.responding {return .ready}
            if observation.health == .loading {return .starting}
            return launchPending ? .starting:.degraded
        }
        // Identity=nil is the adapter's proven absence, NOT a failed probe.
        guard !observation.responding else {return .unknown}
        if desired == .running {
            if !observation.sessionReady {return .waiting_session}
            if !observation.credentialsReady {return .waiting_credentials}
            if restartWaiting && !launchPending {return .degraded}
        }
        // Desired-running is not evidence that launch has actually begun.
        return launchPending ? .starting:.stopped
    }
}
