enum WatchdogAction: Equatable, Sendable {
    case observe, start, terminate, kill, degraded
}

// Decision state only: the supervisor must durably write startHistory before
// spawning, and managerAlive=false means verified reaped/absent, not timeout.
struct WatchdogPolicy: Sendable {
    private(set) var startHistory: [Int64] = []
    private var previousTick: Int64?
    private var terminateAt: Int64?
    private var killIssued = false

    init() {}

    init(restoringStarts: [Int64]) throws {
        guard restoringStarts.count <= 3,
              restoringStarts.allSatisfy({ (0...ActivityPolicy.maximumTimestamp).contains($0) }),
              zip(restoringStarts, restoringStarts.dropFirst()).allSatisfy({ $0 < $1 })
        else { throw PolicyError.invalidObservation }
        startHistory = restoringStarts
        previousTick = restoringStarts.last
    }

    mutating func tick(now: Int64, managerAlive: Bool, lastProgress: Int64?) throws -> WatchdogAction {
        guard (0...ActivityPolicy.maximumTimestamp).contains(now),
              previousTick.map({ now >= $0 }) ?? true
        else { throw PolicyError.invalidObservation }
        if let lastProgress {
            guard lastProgress >= 0, lastProgress <= now else { throw PolicyError.invalidObservation }
        }
        previousTick = now
        startHistory.removeAll { now - $0 >= 600_000 }
        if !managerAlive {
            terminateAt = nil
            killIssued = false
            guard startHistory.count < 3 else { return .degraded }
            guard startHistory.last.map({ now - $0 >= 10_000 }) ?? true else { return .observe }
            startHistory.append(now)
            return .start
        }
        if let terminateAt {
            if !killIssued && now - terminateAt >= 1_000 {
                killIssued = true
                return .kill
            }
            return .observe // Await verified reap. Never spawn alongside old process.
        }
        let progress = lastProgress ?? startHistory.last
        guard let progress, now - progress >= 6_000 else { return .observe }
        terminateAt = now
        return .terminate
    }
}
