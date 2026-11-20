import Foundation
import CryptoKit
import Darwin

func runRuntimeTests() throws {
    let trueURL = URL(fileURLWithPath: "/usr/bin/true")
    let digest = SHA256.hash(data: try Data(contentsOf: trueURL)).map { String(format:"%02x",$0) }.joined()
    let runtime = try VerifiedExecutable(path: trueURL.path, sha256: digest)
    let result = try runtime.run(arguments: [], timeout: 2, maximumOutput: 1024)
    precondition(result.status == 0 && result.output.isEmpty)
    for terminal in [101.999,102,-1,Double.nan,Double.infinity] {
        var readExit=false
        do {
            let checked=try VerifiedExecutable.terminalResult(deadline:102,output:result.output,status:{readExit=true;return result.status},uptime:{
                precondition(readExit,"Terminal clock was checked before observing child status")
                return terminal
            })
            guard terminal==101.999,checked.status==0,checked.output.isEmpty else {fatalError("Invalid terminal clock returned child success")}
        } catch RuntimeError.deadline {guard terminal != 101.999 else {throw RuntimeError.deadline}}
    }
    guard case .outputLimit?=VerifiedExecutable.outputFailure(now:101.999,deadline:102,count:8,error:0,remaining:7),
          case .deadline?=VerifiedExecutable.outputFailure(now:102,deadline:102,count:8,error:0,remaining:7),
          case .launch?=VerifiedExecutable.outputFailure(now:101.999,deadline:102,count:-1,error:EIO,remaining:7),
          case .deadline?=VerifiedExecutable.outputFailure(now:102,deadline:102,count:-1,error:EIO,remaining:7),
          VerifiedExecutable.outputFailure(now:101.999,deadline:102,count:7,error:0,remaining:7)==nil,
          VerifiedExecutable.outputFailure(now:101.999,deadline:102,count:-1,error:EAGAIN,remaining:7)==nil else {
        fatalError("Command read classified output against a renewed or ambiguous cutoff")
    }
    var checks=0
    do {
        _=try runtime.runChecked(arguments:[],timeout:2,checkpoint:{checks+=1;throw RuntimeError.deadline})
        fatalError("Runtime command ignored publication checkpoint")
    } catch RuntimeError.deadline {}
    guard checks==1,try runtime.run(arguments:[],timeout:2).status==0 else {
        fatalError("Refused runtime publication did not return command capacity")
    }
    var expiredChecks=0
    do {
        _=try runtime.runChecked(arguments:[],timeout:0.5,checkpoint:{
            expiredChecks+=1
            Thread.sleep(forTimeInterval:0.51)
        })
        fatalError("Runtime publication returned success after its original deadline")
    } catch RuntimeError.deadline {}
    guard expiredChecks==1,try runtime.run(arguments:[],timeout:2).status==0 else {
        fatalError("Expired publication checkpoint did not return command capacity")
    }
    let echoPath="/bin/echo"
    let echoHash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:echoPath))).map {String(format:"%02x",$0)}.joined()
    let writer=try VerifiedExecutable(path:echoPath,sha256:echoHash)
    let exact=try writer.run(arguments:["fixture"],timeout:2,maximumOutput:8)
    guard exact.status==0,exact.output==Data("fixture\n".utf8) else {
        fatalError("Command output was truncated at the exact byte boundary")
    }
    do {
        _=try writer.run(arguments:["fixture"],timeout:2,maximumOutput:7)
        fatalError("Command returned partial success past its output budget")
    } catch RuntimeError.outputLimit {}
    for _ in 0..<2 {
        do {
            _=try writer.run(arguments:["fixture"],timeout:2,maximumOutput:0)
            fatalError("Spawned command returned bytes against a zero output budget")
        } catch RuntimeError.outputLimit {}
        let empty=try runtime.run(arguments:[],timeout:2,maximumOutput:0)
        guard empty.status==0,empty.output.isEmpty else {fatalError("Output refusal leaked a command slot or confused empty output")}
    }
    // /bin/ls emits only stderr for a missing file; the fixed runtime
    // pipe must account for those bytes just like stdout from echo.
    let listPath="/bin/ls"
    let listHash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:listPath))).map {String(format:"%02x",$0)}.joined()
    let listReader=try VerifiedExecutable(path:listPath,sha256:listHash)
    let missing="/var/empty/fios-runtime-\(UUID().uuidString.lowercased())"
    let stderr=try listReader.run(arguments:[missing],timeout:2,maximumOutput:4096)
    guard stderr.status != 0,!stderr.output.isEmpty else {fatalError("Missing inert file did not produce a diagnostic")}
    let exactStderr=try listReader.run(arguments:[missing],timeout:2,maximumOutput:stderr.output.count)
    guard exactStderr.status==stderr.status,exactStderr.output==stderr.output else {fatalError("Exact stderr limit altered diagnostic bytes")}
    do {
        _=try listReader.run(arguments:[missing],timeout:2,maximumOutput:stderr.output.count-1)
        fatalError("Stderr bypassed the fixed output budget")
    } catch RuntimeError.outputLimit {}
    // A silent child must not keep the actor blocked in output collection.
    let sleepURL=URL(fileURLWithPath:"/bin/sleep")
    let sleepDigest=SHA256.hash(data:try Data(contentsOf:sleepURL)).map {String(format:"%02x",$0)}.joined()
    let sleeper=try VerifiedExecutable(path:sleepURL.path,sha256:sleepDigest)
    let sleepBegan=ProcessInfo.processInfo.systemUptime
    do {
        _=try sleeper.run(arguments:["8"],timeout:0.5,maximumOutput:64)
        fatalError("Silent runtime command exceeded its deadline without refusal")
    } catch RuntimeError.deadline {}
    guard ProcessInfo.processInfo.systemUptime-sleepBegan<3 else {fatalError("Silent runtime command blocked bounded output collection")}
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
