import Foundation
import Darwin
import CoreFoundation

public enum SupervisorRuntime {
    // Bound the progress read before parsing; a nonregular entry is not
    // evidence about the live child and must not block the watchdog loop.
    static func progress(directory:URL,pid:Int32,now:Int64)->Int64? {
        let path=directory.appendingPathComponent("progress.json").path
        let fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard fd>=0 else {return nil};defer {close(fd)}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode&S_IFMT==S_IFREG,info.st_uid==geteuid(),
              info.st_mode&0o077==0,info.st_nlink==1,(1...4096).contains(info.st_size) else {return nil}
        var bytes=[UInt8](repeating:0,count:4097)
        let count=pread(fd,&bytes,4097,0)
        guard count==info.st_size else {return nil}
        let data=Data(bytes.prefix(count))
        guard (try? StrictJSON.validate(data,maximum:4096)) != nil,
              let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              WireScalar.integer(object["pid"])==Int64(pid),let number=object["progress"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {return nil}
        let value=number.doubleValue
        guard value.isFinite,value>=0,(0...ActivityPolicy.maximumTimestamp).contains(now),value*1000<=Double(now) else {return nil}
        return Int64(value*1000)
    }
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
        var publicationFailedAt:Int64?
        let termination=Termination()
        while !termination.requested {
            try autoreleasepool {
            if custodyFailed {custody?.observeOwnedExit()}
            else {
                do {try custody?.poll()}
                catch {
                    custodyFailed=true;try? custody?.bindSupervisedManager(nil)
                    telemetry.event(.rejected)
                    // Retain the server/runtime and its writer lock. Failure
                    // cannot manufacture absence or rearm a new custodian.
                }
            }
            let now=Int64(ProcessInfo.processInfo.systemUptime * 1000)
            let progress=child.flatMap { child in
                child.isRunning ? Self.progress(directory:directory,pid:child.processIdentifier,now:now):nil
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
            let publicationRetryReady=publicationFailedAt.map {now-$0>=1000} ?? true
            if publicationRetryReady && (state != publishedState || policy.startHistory.count != publishedStarts || now-publishedAt >= 1000 || publicationFailedAt != nil) {
                let sampledAt=HostResources.nowMilliseconds()
                let status:[String:Any] = ["version":1,"boot":boot,"pid":getpid(),"process_start":birth,"state":state.rawValue,"starts":policy.startHistory.count,"sampled_uptime_ms":now]
                do {
                    try AtomicState.write(JSONSerialization.data(withJSONObject:status),to:directory.appendingPathComponent("supervisor.json"))
                    telemetry.supervisor(PlatformSupervisorSample(state:state,starts:policy.startHistory.count,sampledAt:sampledAt))
                    publishedState=state;publishedStarts=policy.startHistory.count;publishedAt=now;publicationFailedAt=nil
                } catch JournalError.storage {
                    // Output loss is not child failure. Do not drop custody or
                    // restart the manager; retry status only, at bounded cadence.
                    if publicationFailedAt==nil {telemetry.supervisor(nil);telemetry.event(.rejected)}
                    publicationFailedAt=now
                }
            }
            }
            Thread.sleep(forTimeInterval:0.25)
        }
    }
}
