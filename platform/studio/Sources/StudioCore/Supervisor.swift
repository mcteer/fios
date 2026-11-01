import Foundation
import Darwin

public enum SupervisorRuntime {
    public static func run(directory:URL,manager:URL,telemetry:any PlatformTelemetry=NoopPlatformTelemetry()) throws {
        try run(directory:directory,manager:manager,custodyFactory:nil,telemetry:telemetry)
    }
    // Reviewed code-only composition inside the existing supervisor process.
    // Public startup has no native configuration/credential/reservation issuer.
    static func run(directory:URL,manager:URL,custodyFactory:(@Sendable()throws->ServingCustodyServer)?,telemetry:any PlatformTelemetry=NoopPlatformTelemetry()) throws {
        guard geteuid() != 0 else { throw ControlError.unauthorized }
        umask(0o077)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var info=stat()
        guard lstat(directory.path,&info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw ControlError.unauthorized }
        let singleton=try PrivateWriterLock(directory:directory,kind:.supervisor)
        defer {singleton.release()}
        // The installed companion is reviewed/root-owned. Never take a
        // command, shell string or executable choice from the control socket.
        guard manager.lastPathComponent == "studio-manager", FileManager.default.isExecutableFile(atPath:manager.path) else { throw RuntimeError.identity }
        let custody=try custodyFactory?()
        guard custody?.acceptsManager(at:manager) ?? true else {throw ControlError.unauthorized}
        var custodyFailed=false
        let boot=try HostBoot.identity()
        let birth=try WorkerResources.startIdentifier(pid:getpid())
        let budgetFile=directory.appendingPathComponent("restart-budget.json")
        var policy=WatchdogPolicy()
        if let stored=try SupervisorRestartBudget.read(directory:directory) {
            policy=try stored.policy(currentBoot:boot)
        }
        telemetry.event(.started)
        defer {telemetry.supervisor(nil);telemetry.event(.stopped)}
        var child:Process?
        defer {
            if let child, child.isRunning {
                child.terminate()
                let deadline=ProcessInfo.processInfo.systemUptime + 1
                while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval:0.01) }
                if child.isRunning { kill(child.processIdentifier,SIGKILL) }
                child.waitUntilExit()
            }
        }
        // Revoke pre-dispatch validation before terminating the manager. Native
        // custody/results survive manager exit; no native child is signalled here.
        defer {try? custody?.bindSupervisedManager(nil)}
        var state=PlatformSupervisorState.starting
        var publishedState:PlatformSupervisorState?
        var publishedStarts:Int?
        var publishedAt:Int64 = -1000
        let termination=Termination()
        while !termination.requested {
            try autoreleasepool {
            if !custodyFailed {
                do {try custody?.poll()}
                catch {
                    custodyFailed=true;try? custody?.bindSupervisedManager(nil)
                    telemetry.event(.rejected)
                    // Retain the server/runtime and its writer lock. Failure
                    // cannot manufacture absence or rearm a new custodian.
                }
            }
            let now=Int64(ProcessInfo.processInfo.systemUptime * 1000)
            var progress:Int64?
            if let child, child.isRunning {
                let url=directory.appendingPathComponent("progress.json")
                if let data=try? Data(contentsOf:url), data.count <= 4096,
                   let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                   let pid=obj["pid"] as? Int32, pid == child.processIdentifier,
                   let value=obj["progress"] as? Double, value.isFinite, value >= 0, value * 1000 <= Double(now) {
                    progress=Int64(value*1000)
                }
            }
            let alive=child?.isRunning ?? false
            if let child, !alive {child.waitUntilExit();try custody?.bindSupervisedManager(nil)}
            switch try policy.tick(now:now,managerAlive:alive,lastProgress:progress) {
            case .start:
                try AtomicState.write(JSONEncoder().encode(SupervisorRestartBudget(boot:boot,starts:policy.startHistory)),to:budgetFile)
                let next=Process(); next.executableURL=manager; next.arguments=["--state",directory.path]
                next.environment=["PATH":"/usr/bin:/bin","LANG":"C"]
                next.standardInput=FileHandle.nullDevice; next.standardOutput=FileHandle.nullDevice; next.standardError=FileHandle.nullDevice
                do {try next.run();child=next;state = .running;telemetry.event(.reconciled)}
                catch {child=nil;state = .degraded;telemetry.event(.rejected)}
                if child === next,!custodyFailed {
                    do {try custody?.bindSupervisedManager(next)}
                    catch {
                        custodyFailed=true;try? custody?.bindSupervisedManager(nil)
                        state = .degraded;telemetry.event(.rejected)
                        // Keep the already running manager reference. Binding
                        // failure must not orphan it or bypass the watchdog.
                    }
                }
            case .terminate:
                try custody?.bindSupervisedManager(nil)
                child?.terminate();state = .recovering;telemetry.event(.revoked)
            case .kill:
                try custody?.bindSupervisedManager(nil)
                if let child,child.isRunning {kill(child.processIdentifier,SIGKILL);telemetry.event(.revoked)}
            case .degraded:
                try custody?.bindSupervisedManager(nil)
                if state != .degraded {telemetry.event(.rejected)}
                state = .degraded
            case .observe: break
            }
            if custodyFailed {state = .degraded}
            // Keep 250ms watchdog polling, but unchanged telemetry needs only
            // 1s durability (reader freshness is 5s). Publish every transition.
            if state != publishedState || policy.startHistory.count != publishedStarts || now-publishedAt >= 1000 {
                let sampledAt=HostResources.nowMilliseconds()
                let status:[String:Any] = ["version":1,"boot":boot,"pid":getpid(),"process_start":birth,"state":state.rawValue,"starts":policy.startHistory.count,"sampled_uptime_ms":now]
                try AtomicState.write(JSONSerialization.data(withJSONObject:status),to:directory.appendingPathComponent("supervisor.json"))
                telemetry.supervisor(PlatformSupervisorSample(state:state,starts:policy.startHistory.count,sampledAt:sampledAt))
                publishedState=state;publishedStarts=policy.startHistory.count;publishedAt=now
            }
            }
            Thread.sleep(forTimeInterval:0.25)
        }
    }
}
