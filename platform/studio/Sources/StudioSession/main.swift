import Foundation
import AppKit
import SystemConfiguration
import Darwin
import StudioCore

// GUI-session observation only until enrolled identities and the native
// activity gate activate fixed lifecycle operations. Never starts a login.
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
    let instance=try SessionInstanceLock(directory:directory)
    defer {instance.release()}
    let termination=Termination()
    let boot=try HostBoot.identity()
    let processStart=try HostBoot.processStartIdentifier(pid:getpid())
    repeat {
        try autoreleasepool {
        var uid:uid_t=0,gid:gid_t=0
        let user=SCDynamicStoreCopyConsoleUser(nil,&uid,&gid)
        let ready=user != nil && uid==geteuid() && uid != 0
        let apps=ready ? NSWorkspace.shared.runningApplications : []
        let mlx=apps.contains { !$0.isTerminated && $0.bundleIdentifier=="com.dalcu.mlx-core" && $0.bundleURL?.path=="/Applications/MLX-Serve.app" }
        let orb=apps.contains { !$0.isTerminated && $0.bundleIdentifier=="dev.kdrag0n.MacVirt" && $0.bundleURL?.path=="/Applications/OrbStack.app" }
        let body:[String:Any] = ["version":2,"uid":geteuid(),"pid":getpid(),"process_start":processStart,"boot":boot,"console_session":ready,
                               "sampled_uptime_ms":Int64(ProcessInfo.processInfo.systemUptime*1000),
                               "mlx_present":mlx,"orbstack_present":orb,"lifecycle_enabled":false]
        try AtomicState.write(JSONSerialization.data(withJSONObject:body,options:[.sortedKeys]),to:directory.appendingPathComponent("session.json"))
        }
        if args.count==4 { break }
        Thread.sleep(forTimeInterval:2)
    } while !termination.requested
} catch {
    FileHandle.standardError.write(Data("studio-session: observation unavailable\n".utf8));exit(1)
}
