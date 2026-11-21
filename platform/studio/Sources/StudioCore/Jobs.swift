import Foundation

struct JobLease: Codable, Sendable {
    let created: Int64
    let deadline: Int64
    private(set) var expires: Int64
    private(set) var revoked = false
    private var previous: Int64

    init(created: Int64, lifetime: Int64 = 900_000) throws {
        guard created >= 0, created <= ActivityPolicy.maximumTimestamp - 1_800_000,
              (1...1_800_000).contains(lifetime) else { throw AdmissionError.invalid }
        self.created = created
        deadline = created + lifetime
        expires = min(created + 30_000, deadline)
        previous = created
    }
    func validateRestored() throws {
        guard created>=0,created<=ActivityPolicy.maximumTimestamp-1_800_000,
              deadline>created,deadline<=ActivityPolicy.maximumTimestamp,deadline-created<=1_800_000,
              expires>created,expires<=deadline,previous>=created,
              revoked || previous<expires else {throw JournalError.invalid}
    }
    mutating func valid(now: Int64) -> Bool {
        if now < previous || now >= expires || now >= deadline { revoked = true }
        previous = max(previous, now)
        return !revoked
    }
    mutating func renew(now: Int64) throws {
        guard valid(now: now) else { throw AdmissionError.expired }
        expires = min(now + 30_000, deadline)
    }
    mutating func revoke() { revoked = true }
}

extension JobState {
    public func permits(_ next: JobState) -> Bool {
        switch self {
        case .reserved: return [.creating,.running,.revoking,.reconciling].contains(next)
        case .creating: return [.running,.revoking,.reconciling].contains(next)
        case .running: return [.revoking,.reconciling].contains(next)
        case .revoking: return [.stopping,.removed,.reconciling].contains(next)
        case .stopping: return [.removing,.reconciling].contains(next)
        case .removing: return [.removed,.reconciling].contains(next)
        case .reconciling: return [.revoking,.stopping,.removing,.removed].contains(next)
        case .removed: return false
        }
    }
}
