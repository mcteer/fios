import Foundation

private func expect(_ value: Bool) { precondition(value) }

func runWatchdogTests() throws {
    var watchdog = WatchdogPolicy()
    expect(try watchdog.tick(now: 0, managerAlive: false, lastProgress: nil) == .start)
    expect(try watchdog.tick(now: 2_000, managerAlive: true, lastProgress: 1_000) == .observe)
    expect(try watchdog.tick(now: 8_000, managerAlive: true, lastProgress: 1_000) == .terminate)
    expect(try watchdog.tick(now: 8_500, managerAlive: true, lastProgress: 1_000) == .observe)
    expect(try watchdog.tick(now: 9_000, managerAlive: true, lastProgress: 1_000) == .kill)
    // No second manager may start before its predecessor is reaped.
    expect(try watchdog.tick(now: 10_000, managerAlive: true, lastProgress: nil) == .observe)
    expect(try watchdog.tick(now: 10_001, managerAlive: false, lastProgress: nil) == .start)
    expect(try watchdog.tick(now: 12_000, managerAlive: false, lastProgress: nil) == .observe)
    expect(try watchdog.tick(now: 20_001, managerAlive: false, lastProgress: nil) == .start)
    expect(try watchdog.tick(now: 30_001, managerAlive: false, lastProgress: nil) == .degraded)
    // Restore restart budget instead of silently resetting it on supervisor restart.
    var restored = try WatchdogPolicy(restoringStarts: watchdog.startHistory)
    expect(try restored.tick(now: 40_001, managerAlive: false, lastProgress: nil) == .degraded)
    expect(try restored.tick(now: 600_001, managerAlive: false, lastProgress: nil) == .start)
    do {
        _ = try restored.tick(now: 1, managerAlive: false, lastProgress: nil)
        preconditionFailure("Clock rollback must reject")
    } catch PolicyError.invalidObservation {}
    print("PASS: watchdog restart, hang, reap fence, durable-budget and clock tests")
}
