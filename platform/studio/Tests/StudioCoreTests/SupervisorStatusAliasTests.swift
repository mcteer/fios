import Foundation
import Darwin

// Genuine own-process identity and ordinary macOS temporary-path aliases.
func runSupervisorStatusAliasTests()throws {
    let directory=URL(fileURLWithPath:"/private/tmp/fios-009-supervisor-alias-"+UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let executable=CommandLine.arguments[0]
    let status:[String:Any]=["version":1,"boot":try HostBoot.identity(),"pid":getpid(),
        "process_start":try WorkerResources.startIdentifier(pid:getpid()),"state":"running","starts":1,
        "sampled_uptime_ms":Int64(ProcessInfo.processInfo.systemUptime*1000)]
    try AtomicState.write(JSONSerialization.data(withJSONObject:status),to:directory.appendingPathComponent("supervisor.json"))
    for path in [executable,URL(fileURLWithPath:executable).resolvingSymlinksInPath().path] {
        let value=try SupervisorStatus.read(directory:directory,expectedExecutable:path)
        guard value["ok"] as? Bool==true else {throw ControlError.internal_error}
    }
    print("PASS: supervisor status accepts ordinary canonical/Foundation aliases for the same genuine process")
}
