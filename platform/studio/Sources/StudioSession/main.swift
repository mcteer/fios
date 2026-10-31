import Foundation
import AppKit
import SystemConfiguration
import Darwin
import StudioCore

// Development/unenrolled and --once runs observe only. The installed helper
// can expose fixed launch-only RPC after independent root enrollment; ordinary
// native lifecycle/idle authority remains separate. Never starts a login.
let args=CommandLine.arguments
if !(args.count==3 || args.count==4) || args[1] != "--state" || !args[2].hasPrefix("/") || (args.count==4 && args[3] != "--once") {
    FileHandle.standardError.write(Data("Usage: studio-session --state ABSOLUTE_PRIVATE_DIRECTORY [--once]\n".utf8));exit(2)
}
do {
    guard getuid() != 0,getuid()==geteuid() else { throw ControlError.unauthorized }
    umask(0o077)
    let directory=URL(fileURLWithPath:args[2])
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    var info=stat()
    guard lstat(directory.path,&info)==0,info.st_mode & S_IFMT == S_IFDIR,
          info.st_uid==geteuid(),info.st_mode & 0o077==0 else { throw ControlError.unauthorized }
    let operations=SessionNativeOperations(consoleReady:{
        var uid:uid_t=0,gid:gid_t=0
        return SCDynamicStoreCopyConsoleUser(nil,&uid,&gid) != nil && uid==geteuid() && uid != 0
    },alreadyRunning:{application in
        NSWorkspace.shared.runningApplications.contains {!$0.isTerminated && $0.bundleIdentifier==application.identifier}
    },open:{application,completion in
        let configuration=NSWorkspace.OpenConfiguration()
        configuration.activates=false;configuration.hides=true
        configuration.createsNewApplicationInstance=false;configuration.promptsUserIfNeeded=false
        configuration.arguments=[];configuration.environment=["PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C"]
        NSWorkspace.shared.openApplication(at:application.bundle,configuration:configuration) {app,error in
            let pid=app?.processIdentifier,success=error==nil && app?.isTerminated==false
            Task { @MainActor in completion(pid,success) }
        }
    })
    let driver=args.count==3 ? try EnrolledSessionDriver.enrolled(directory:directory,operations:operations):nil
    let instance=driver == nil ? try SessionInstanceLock(directory:directory):nil
    defer {driver?.shutdown();instance?.release()}
    let termination=Termination()
    let boot=try HostBoot.identity()
    let processStart=try HostBoot.processStartIdentifier(pid:getpid())
    var lastSample:TimeInterval = -2
    var ready=false
    repeat {
        try autoreleasepool {
        let now=ProcessInfo.processInfo.systemUptime
        if now-lastSample>=2 {
        var uid:uid_t=0,gid:gid_t=0
        let user=SCDynamicStoreCopyConsoleUser(nil,&uid,&gid)
        ready=user != nil && uid==geteuid() && uid != 0
        let apps=ready ? NSWorkspace.shared.runningApplications : []
        let mlx=apps.contains { !$0.isTerminated && $0.bundleIdentifier=="com.dalcu.mlx-core" && $0.bundleURL?.path=="/Applications/MLX-Serve.app" }
        let orb=apps.contains { !$0.isTerminated && $0.bundleIdentifier=="dev.kdrag0n.MacVirt" && $0.bundleURL?.path=="/Applications/OrbStack.app" }
        let body:[String:Any] = ["version":2,"uid":geteuid(),"pid":getpid(),"process_start":processStart,"boot":boot,"console_session":ready,
                               "sampled_uptime_ms":Int64(ProcessInfo.processInfo.systemUptime*1000),
                               "mlx_present":mlx,"orbstack_present":orb,"lifecycle_enabled":false]
        // This observation file never grants lifecycle authority. The separate
        // kernel-authenticated RPC descriptor advertises the scoped transport.
        try AtomicState.write(JSONSerialization.data(withJSONObject:body,options:[.sortedKeys]),to:directory.appendingPathComponent("session.json"))
        lastSample=now
        }
        try driver?.poll(consoleReady:ready,now:HostResources.nowMilliseconds())
        }
        if args.count==4 { break }
        if driver != nil {RunLoop.current.run(until:Date(timeIntervalSinceNow:0.02))}
        else {Thread.sleep(forTimeInterval:2)}
    } while !termination.requested
} catch {
    FileHandle.standardError.write(Data("studio-session: observation unavailable\n".utf8));exit(1)
}
