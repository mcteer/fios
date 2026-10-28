import Foundation

public enum PolicyError: Error, Sendable {
    case invalidObservation, staleObservation, conflictingModel, duplicateRequest
    case unknownRequest, trackingLimit
}

// Internal normalized input from a trusted adapter, not a caller-authorized
// wire object. Setting coverage requires native compatibility evidence.
struct NativeSnapshot: Sendable {
    let host: String
    let endpointHash: String
    let nativeEpoch: String
    let sequence: UInt64
    let sampledAt: Int64
    let allClientLifecycleCoverage: Bool
    let residentModel: String?
    let outstandingOwners: Int
    let loading: Bool
}

enum HostActivity: Equatable, Sendable {
    case idle, preparing, busy(model: String), unknown
}

enum ActivityPolicy {
    static let maximumTimestamp: Int64 = WireScalar.maximumTimestamp

    static func evaluate(_ snapshot: NativeSnapshot, now: Int64) throws -> HostActivity {
        guard (0...maximumTimestamp).contains(now),
              (0...maximumTimestamp).contains(snapshot.sampledAt),
              WireScalar.host(snapshot.host),WireScalar.sha256(snapshot.endpointHash),
              !snapshot.nativeEpoch.isEmpty, snapshot.nativeEpoch.utf8.count <= 128,
              snapshot.sequence > 0,
              (0...2_147_483_647).contains(snapshot.outstandingOwners)
        else { throw PolicyError.invalidObservation }
        if let model = snapshot.residentModel {
            guard WireScalar.model(model) else { throw PolicyError.invalidObservation }
        }
        let age = now - snapshot.sampledAt // Both operands bounded safely above.
        guard (-1000...5000).contains(age) else { throw PolicyError.staleObservation }
        guard snapshot.allClientLifecycleCoverage else { return .unknown }
        if snapshot.loading { return .preparing }
        if snapshot.outstandingOwners > 0 {
            guard let model = snapshot.residentModel else { return .unknown }
            return .busy(model: model)
        }
        return .idle
    }

    // Advisory eligibility only. Native ownership/admission must close the
    // observation-to-dispatch race. This is NOT a native model reservation.
    static func permits(target: String, snapshot: NativeSnapshot, now: Int64) throws -> Bool {
        guard WireScalar.model(target) else { throw PolicyError.invalidObservation }
        switch try evaluate(snapshot, now: now) {
        case .idle: return true // Idle resident replacement is intentionally allowed.
        case .busy(let model): return WireScalar.exactModel(model,target)
        case .preparing, .unknown: return false
        }
    }
}
