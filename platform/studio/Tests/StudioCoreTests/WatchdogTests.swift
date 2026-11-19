import Foundation
import Darwin

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
    var stable=WatchdogPolicy()
    expect(try stable.tick(now:0,managerAlive:false,lastProgress:nil) == .start)
    expect(try stable.tick(now:599_999,managerAlive:true,lastProgress:599_999) == .observe)
    expect(try stable.tick(now:600_000,managerAlive:true,lastProgress:nil) == .terminate)
    expect(try stable.tick(now:600_999,managerAlive:true,lastProgress:nil) == .observe)
    expect(try stable.tick(now:601_000,managerAlive:true,lastProgress:nil) == .kill)
    expect(try stable.tick(now:601_001,managerAlive:true,lastProgress:nil) == .observe)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-watchdog-progress-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let progress=directory.appendingPathComponent("progress.json")
    guard mkfifo(progress.path,0o600)==0 else {throw RuntimeError.launch}
    expect(SupervisorRuntime.progress(directory:directory,pid:42,now:1000)==nil)
    try FileManager.default.removeItem(at:progress)
    for (data,expected):(Data,Int64?) in [(Data(repeating:0,count:4097),nil),
        (Data("{\"pid\":43,\"progress\":0.5}".utf8),nil),(Data("{\"pid\":42,\"progress\":1.001}".utf8),nil),
        (Data("{\"pid\":42,\"progress\":true}".utf8),nil),
        (Data("{\"pid\":42,\"progress\":0,\"progress\":0.5}".utf8),nil),
        (Data("{\"pid\":42,\"progress\":0.5}".utf8),500)] {
        try data.write(to:progress)
        guard chmod(progress.path,0o600)==0 else {throw RuntimeError.launch}
        expect(SupervisorRuntime.progress(directory:directory,pid:42,now:1000)==expected)
    }
    var progressBudget=WatchdogPolicy()
    expect(try progressBudget.tick(now:0,managerAlive:false,lastProgress:nil) == .start)
    let before=SupervisorRuntime.progress(directory:directory,pid:42,now:6499)
    let boundary=SupervisorRuntime.progress(directory:directory,pid:42,now:6500)
    expect(before==500 && boundary==500)
    expect(try progressBudget.tick(now:6499,managerAlive:true,lastProgress:before) == .observe)
    expect(try progressBudget.tick(now:6500,managerAlive:true,lastProgress:boundary) == .terminate)
    var turnover=WatchdogPolicy()
    expect(try turnover.tick(now:0,managerAlive:false,lastProgress:nil) == .start)
    expect(try turnover.tick(now:10000,managerAlive:false,lastProgress:nil) == .start)
    expect(try turnover.tick(now:15999,managerAlive:true,lastProgress:9000) == .observe)
    var progressing=turnover
    expect(try turnover.tick(now:16000,managerAlive:true,lastProgress:9000) == .terminate)
    expect(try progressing.tick(now:16000,managerAlive:true,lastProgress:10001) == .observe)
    expect(try progressing.tick(now:16001,managerAlive:true,lastProgress:10001) == .terminate)
    let oldBoot=UUID().uuidString.lowercased(),currentBoot=UUID().uuidString.lowercased()
    let malformed=SupervisorRestartBudget(boot:oldBoot,starts:[1000,10999])
    do {_=try malformed.policy(currentBoot:currentBoot);fatalError("Boot turnover erased an impossible persisted restart sequence")}
    catch PolicyError.invalidObservation {}
    let valid=SupervisorRestartBudget(boot:oldBoot,starts:[1000,11000])
    expect(try valid.policy(currentBoot:oldBoot).startHistory==[1000,11000])
    expect(try valid.policy(currentBoot:currentBoot).startHistory.isEmpty)
    let budgetPath=directory.appendingPathComponent("restart-budget.json")
    let malformedBytes=try JSONEncoder().encode(malformed)
    try malformedBytes.write(to:budgetPath)
    guard chmod(budgetPath.path,0o600)==0 else {throw RuntimeError.launch}
    do {_=try SupervisorRestartBudget.read(directory:directory);fatalError("Impossible persisted spacing accepted from disk")}
    catch PolicyError.invalidObservation {}
    expect(try Data(contentsOf:budgetPath)==malformedBytes)
    try JSONEncoder().encode(valid).write(to:budgetPath)
    expect(try SupervisorRestartBudget.read(directory:directory)?.starts==valid.starts)
    let status=directory.appendingPathComponent("supervisor.json")
    guard mkfifo(status.path,0o600)==0 else {throw RuntimeError.launch}
    do {_=try SupervisorStatus.read(directory:directory,expectedExecutable:"/bin/false");fatalError("Nonregular supervisor status admitted")}
    catch ControlError.unauthorized {}
    try FileManager.default.removeItem(at:status)
    let record:[String:Any]=["version":1,"boot":try HostBoot.identity(),"pid":getpid(),
        "process_start":try WorkerResources.startIdentifier(pid:getpid()),"state":"running","starts":1,"sampled_uptime_ms":10000]
    try JSONSerialization.data(withJSONObject:record).write(to:status)
    guard chmod(status.path,0o600)==0 else {throw RuntimeError.launch}
    let expected=ProcessInfo.processInfo.arguments[0]
    for accepted:Int64 in [9000,15000] {
        expect(try SupervisorStatus.read(directory:directory,expectedExecutable:expected,now:{accepted})["ok"] as? Bool == true)
    }
    for samples:[Int64] in [[8999,9000],[15001,15001],[15000,15001],[11000,10999],[11000,.max]] {
        var readings=samples
        do {_=try SupervisorStatus.read(directory:directory,expectedExecutable:expected,now:{readings.removeFirst()})
            fatalError("Supervisor status published outside its original clock window")
        } catch ControlError.busy {}
    }
    print("PASS: watchdog restart, hang, reap fence, durable-budget and clock tests")
}
