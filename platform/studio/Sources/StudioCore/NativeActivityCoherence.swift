import Foundation

// Source-adapter inputs only. These types do not deserialize a wire claim into
// native authority. The independent sourceCoverage ceiling must come from the
// reviewed adapter, never from the observation or its authenticated transport.
struct NativePhaseCounts: Equatable, Sendable {
    let ingress: Int
    let preparing: Int
    let queued: Int
    let active: Int
    let responding: Int

    static let zero = Self(ingress:0,preparing:0,queued:0,active:0,responding:0)
    var values: [Int] { [ingress,preparing,queued,active,responding] }
}

struct NativeModelActivity: Sendable {
    let model: String
    let resident: Bool
    let counts: NativePhaseCounts
}

struct CoherentNativeActivity: Equatable, Sendable {
    let coverage: NativeCoverage
    let state: NativeActivityState
    let model: String?
    let owners: Int?

    // Advisory only; the native atomic admission boundary must still close
    // external-client and snapshot-to-dispatch races.
    func permits(target: String) -> Bool {
        guard WireScalar.model(target),coverage == .all_clients else { return false }
        switch state {
        case .idle: return true
        case .queued,.active: return model.map { WireScalar.exactModel($0,target) } ?? false
        case .preparing,.unknown: return false
        }
    }
}

enum NativeActivityCoherence {
    static func evaluate(coverage: NativeCoverage, sourceCoverage: NativeCoverage,
                         totals: NativePhaseCounts, unattributed: NativePhaseCounts,
                         models: [NativeModelActivity], transitioning: Bool) -> CoherentNativeActivity {
        let effective: NativeCoverage = sourceCoverage == .unsupported || coverage == .unsupported
            ? .unsupported : sourceCoverage == .all_clients && coverage == .all_clients ? .all_clients : .unknown
        let unknown = CoherentNativeActivity(coverage:effective,state:.unknown,model:nil,owners:nil)
        guard effective == .all_clients,models.count <= 64 else { return unknown }
        // Validate every scalar before summation. At most66 bounded vectors are
        // examined; overflow is never truncated into a plausible idle result.
        let vectors = [totals,unattributed] + models.map(\.counts)
        guard vectors.allSatisfy({ $0.values.allSatisfy { (0...Int(Int32.max)).contains($0) } }) else { return unknown }
        var identities = Set<Data>()
        guard models.allSatisfy({ WireScalar.model($0.model) && identities.insert(Data($0.model.utf8)).inserted }) else { return unknown }
        var combined = unattributed.values
        for model in models {
            for index in combined.indices {
                let (sum,overflow) = combined[index].addingReportingOverflow(model.counts.values[index])
                guard !overflow,sum <= Int32.max else { return unknown }
                combined[index] = sum
            }
        }
        guard combined == totals.values else { return unknown }
        var owners = 0
        for count in combined {
            let (sum,overflow) = owners.addingReportingOverflow(count)
            guard !overflow,sum <= Int32.max else { return unknown }
            owners = sum
        }
        let residents = models.filter(\.resident)
        guard residents.count <= 1,!transitioning,unattributed == .zero else { return unknown }
        let busy = models.filter { $0.counts != .zero }
        guard busy.count <= 1 else { return unknown }
        if let owner = busy.first,let resident = residents.first,
           !WireScalar.exactModel(owner.model,resident.model) { return unknown }
        let model = busy.first?.model ?? residents.first?.model
        let state: NativeActivityState
        if totals.ingress > 0 || totals.preparing > 0 { state = .preparing }
        else if totals.active > 0 || totals.responding > 0 { state = .active }
        else if totals.queued > 0 { state = .queued }
        else { state = .idle }
        return CoherentNativeActivity(coverage:effective,state:state,model:model,owners:owners)
    }
}
