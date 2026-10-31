import Foundation
import CryptoKit
import Darwin

func runRuntimeTests() throws {
    let trueURL = URL(fileURLWithPath: "/usr/bin/true")
    let digest = SHA256.hash(data: try Data(contentsOf: trueURL)).map { String(format:"%02x",$0) }.joined()
    let runtime = try VerifiedExecutable(path: trueURL.path, sha256: digest)
    let result = try runtime.run(arguments: [], timeout: 2, maximumOutput: 1024)
    precondition(result.status == 0 && result.output.isEmpty)
    do {
        let bad = try VerifiedExecutable(path: trueURL.path, sha256: String(repeating:"0",count:64))
        _ = try bad.run(arguments: [], timeout: 2, maximumOutput: 1024)
        preconditionFailure("Changed executable identity accepted")
    } catch RuntimeError.identity {}
    guard let path=ProcessInfo.processInfo.environment["FIOS_PLATFORM_SETID_FIXTURE"],
          URL(fileURLWithPath:path).lastPathComponent=="never-executed" else {fatalError("Missing runner-owned metadata-only fixture")}
    let privileged=URL(fileURLWithPath:path)
    var info=stat()
    guard lstat(path,&info)==0,info.st_uid==geteuid(),info.st_mode & S_IFMT == S_IFREG,
          info.st_mode & 0o6000 != 0 else {fatalError("Set-ID metadata fixture was stripped; cannot claim refusal coverage")}
    do {
        // Metadata-only refusal. Never execute this mode-marked fixture.
        try VerifiedExecutable(path:privileged.path,sha256:digest).verify()
        preconditionFailure("Set-ID executable accepted by unprivileged runtime")
    } catch RuntimeError.identity {}
    var identityFailures:[String]=[]
    for unsafe in ["/usr/bin/true\0ignored","/usr/bin/../bin/true","//usr/bin/true"] {
        do {_ = try VerifiedExecutable(path:unsafe,sha256:digest);identityFailures.append("Noncanonical/NUL executable path accepted")}
        catch RuntimeError.invalid {}
    }
    // Darwin's approved /tmp spelling must not be rejected merely because
    // Foundation standardization resolves it to /private/tmp.
    let aliasDirectory=URL(fileURLWithPath:"/tmp").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:aliasDirectory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:aliasDirectory)}
    let aliasExecutable=aliasDirectory.appendingPathComponent("metadata-only")
    try FileManager.default.copyItem(at:trueURL,to:aliasExecutable)
    try VerifiedExecutable(path:aliasExecutable.path,sha256:digest).verify()
    let metadata=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:metadata,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:metadata)}
    let original=metadata.appendingPathComponent("metadata-only"),alias=metadata.appendingPathComponent("linked")
    try FileManager.default.copyItem(at:trueURL,to:original)
    try FileManager.default.linkItem(at:original,to:alias)
    do {try VerifiedExecutable(path:original.path,sha256:digest).verify();identityFailures.append("Hardlinked executable accepted")}
    catch RuntimeError.identity {}
    let fifo=metadata.appendingPathComponent("never-open-blocking")
    guard mkfifo(fifo.path,0o600)==0 else {fatalError("FIFO metadata fixture unavailable")}
    let began=ProcessInfo.processInfo.systemUptime
    do {try VerifiedExecutable(path:fifo.path,sha256:digest).verify();fatalError("Nonregular executable accepted")}
    catch RuntimeError.identity {}
    guard ProcessInfo.processInfo.systemUptime-began<1 else {fatalError("Executable metadata open blocked on FIFO")}
    for deadline in [-Double.infinity,Double.nan,ProcessInfo.processInfo.systemUptime-1] {
        do {try runtime.verify(deadline:deadline);fatalError("Invalid executable verification deadline accepted")}
        catch RuntimeError.deadline {}
    }
    guard identityFailures.isEmpty else {fatalError(identityFailures.joined(separator:"; "))}
    let sanitized=try CommandEnvironment.sanitized(["HOME":"/fixture/home","DOCKER_CONFIG":"/var/empty","DOCKER_CLI_HINTS":"false"])
    guard sanitized == ["PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C","HOME":"/fixture/home","DOCKER_CONFIG":"/var/empty","DOCKER_CLI_HINTS":"false"],
          try CommandEnvironment.sanitized([:]) == ["PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C"] else {fatalError("Runtime environment inherited or changed configuration")}
    for unsafeEnvironment in [["PATH":"/tmp"],["DYLD_INSERT_LIBRARIES":"/fixture/never-load"],
                              ["DOCKER_HOST":"tcp://127.0.0.1:1"],["DOCKER_CONTEXT":"foreign"],
                              ["DOCKER_CONFIG":"/tmp"],["DOCKER_CLI_HINTS":"true"],
                              ["HOME":"relative"],["HOME":"/tmp/../private"],["HOME":"/tmp\0suffix"]] {
        do {
            _ = try runtime.run(arguments:[],timeout:2,environment:unsafeEnvironment)
            fatalError("Runtime accepted an environment override outside fixed policy")
        } catch RuntimeError.invalid {}
    }
    let config = try SandboxConfiguration(job: UUID().uuidString.lowercased(), nonce: String(repeating:"b",count:64), image: "sha256:" + String(repeating:"a",count:64), memory: 512 << 20, cpus: 1)
    let argv = config.createArguments
    precondition(argv.contains("--network=none") && argv.contains("--read-only") && argv.contains("--cap-drop=ALL"))
    precondition(argv.contains("--pull=never") && argv.contains("--pids-limit=64"))
    precondition(!argv.contains("--privileged") && !argv.contains("--volume"))
    print("PASS: verified subprocess and fixed hardened sandbox arguments")
}
