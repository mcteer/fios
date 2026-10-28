import Foundation
import Darwin

public enum SupervisorRuntime {
    public static func run(directory:URL,manager:URL) throws {
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
        let boot=try HostBoot.identity()
        let birth=try WorkerResources.startIdentifier(pid:getpid())
        let budgetFile=directory.appendingPathComponent("restart-budget.json")
        var policy=WatchdogPolicy()
        if let stored=try SupervisorRestartBudget.read(directory:directory) {
            policy=try stored.policy(currentBoot:boot)
        }
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
        var state="starting"
        var publishedState:String?
        var publishedStarts:Int?
        var publishedAt:Int64 = -1000
        let termination=Termination()
        while !termination.requested {
            try autoreleasepool {
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
            if let child, !alive { child.waitUntilExit() }
            switch try policy.tick(now:now,managerAlive:alive,lastProgress:progress) {
            case .start:
                try AtomicState.write(JSONEncoder().encode(SupervisorRestartBudget(boot:boot,starts:policy.startHistory)),to:budgetFile)
                let next=Process(); next.executableURL=manager; next.arguments=["--state",directory.path]
                next.environment=["PATH":"/usr/bin:/bin","LANG":"C"]
                next.standardInput=FileHandle.nullDevice; next.standardOutput=FileHandle.nullDevice; next.standardError=FileHandle.nullDevice
                do { try next.run(); child=next; state="running" } catch { child=nil; state="degraded" }
            case .terminate: child?.terminate(); state="recovering"
            case .kill: if let child, child.isRunning { kill(child.processIdentifier,SIGKILL) }
            case .degraded: state="degraded"
            case .observe: break
            }
            // Keep 250ms watchdog polling, but unchanged telemetry needs only
            // 1s durability (reader freshness is 5s). Publish every transition.
            if state != publishedState || policy.startHistory.count != publishedStarts || now-publishedAt >= 1000 {
                let status:[String:Any] = ["version":1,"boot":boot,"pid":getpid(),"process_start":birth,"state":state,"starts":policy.startHistory.count,"sampled_uptime_ms":now]
                try AtomicState.write(JSONSerialization.data(withJSONObject:status),to:directory.appendingPathComponent("supervisor.json"))
                publishedState=state;publishedStarts=policy.startHistory.count;publishedAt=now
            }
            }
            Thread.sleep(forTimeInterval:0.25)
        }
    }
}
