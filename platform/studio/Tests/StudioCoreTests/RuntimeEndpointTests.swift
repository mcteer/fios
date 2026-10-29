import Foundation
import Darwin
import CryptoKit

func runRuntimeEndpointTests()throws {
    let home="/private/tmp/fios009-endpoint-"+UUID().uuidString.lowercased()
    try FileManager.default.createDirectory(atPath:home,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(atPath:home)}
    let hidden=home+"/.orbstack",run=hidden+"/run",path=run+"/docker.sock"
    try FileManager.default.createDirectory(atPath:run,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    let listener=try UnixControlSocket(path:path)
    defer {withExtendedLifetime(listener) {}}
    let policy=try RuntimeEndpointPolicy(home:home,uid:geteuid(),peer:RuntimePeerPolicy(uid:geteuid(),executable:runtimePeerTestExecutable()))
    let original=try policy.capture(deadline:ProcessInfo.processInfo.systemUptime+2)
    try original.verify(deadline:ProcessInfo.processInfo.systemUptime+2)
    func refused(_ operation:()throws->Void)throws {
        do {try operation();fatalError("Unsafe runtime endpoint accepted")}catch RuntimeError.identity {}
    }
    let harmless="/usr/bin/true"
    let digest=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:harmless))).map {String(format:"%02x",$0)}.joined()
    let runtime=DockerRuntime(executable:try VerifiedExecutable(path:harmless,sha256:digest),endpoint:policy)
    let own=try runtimePeerTestExecutable()
    let wrongPeer=try RuntimePeerPolicy(uid:geteuid(),executable:VerifiedExecutable(path:own.path,sha256:String(repeating:"0",count:64)))
    let wrongRuntime=DockerRuntime(executable:try VerifiedExecutable(path:harmless,sha256:digest),endpoint:try RuntimeEndpointPolicy(home:home,uid:geteuid(),peer:wrongPeer))
    try refused {_=try wrongRuntime.command(["version"],timeout:2)}
    guard chmod(run,0o755)==0 else {fatalError("Fixture chmod failed")}
    try refused {_=try policy.capture(deadline:ProcessInfo.processInfo.systemUptime+2)}
    try refused {try original.verify(deadline:ProcessInfo.processInfo.systemUptime+2)}
    try refused {_=try runtime.command(["version"],timeout:2)}
    guard chmod(run,0o700)==0 else {fatalError("Fixture restore failed")}
    func acl(_ arguments:[String])throws {
        let command=Process();command.executableURL=URL(fileURLWithPath:"/bin/chmod");command.arguments=arguments
        command.environment=["PATH":"/usr/bin:/bin"];command.standardInput=FileHandle.nullDevice;command.standardOutput=FileHandle.nullDevice;command.standardError=FileHandle.nullDevice
        try command.run();command.waitUntilExit();guard command.terminationStatus==0 else {fatalError("Fixture ACL unavailable")}
    }
    try acl(["+a","everyone allow write",run])
    try refused {_=try policy.capture(deadline:ProcessInfo.processInfo.systemUptime+2)}
    try acl(["-N",run])
    try acl(["+a","everyone deny delete",home])
    _=try policy.capture(deadline:ProcessInfo.processInfo.systemUptime+2)
    try acl(["-N",home])
    let held=run+"/held.sock"
    guard rename(path,held)==0,symlink(held,path)==0 else {fatalError("Fixture socket alias failed")}
    try refused {_=try policy.capture(deadline:ProcessInfo.processInfo.systemUptime+2)}
    try refused {try original.verify(deadline:ProcessInfo.processInfo.systemUptime+2)}
    guard unlink(path)==0,rename(held,path)==0 else {fatalError("Fixture socket restore failed")}
    guard let executable=ProcessInfo.processInfo.environment["FIOS_PLATFORM_ENDPOINT_FIXTURE"],
          URL(fileURLWithPath:executable).lastPathComponent=="runtime-endpoint-command" else {fatalError("Missing runner-owned finite endpoint command")}
    let fakeSHA=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:executable))).map {String(format:"%02x",$0)}.joined()
    let fake=DockerRuntime(executable:try VerifiedExecutable(path:executable,sha256:fakeSHA),endpoint:policy)
    guard try fake.command(["fixture-safe"],timeout:2).status==0 else {fatalError("Unchanged guarded fixture command refused")}
    var beforeMutation=stat()
    guard lstat(path,&beforeMutation)==0 else {fatalError("Missing original fixture socket")}
    do {
        let completed=try fake.command(["fixture-mutate"],timeout:2)
        var changed=stat(),heldSocket=stat()
        guard completed.status==0,lstat(path,&changed)==0,changed.st_mode&S_IFMT==S_IFLNK,
              lstat(path+".fixture-held",&heldSocket)==0,heldSocket.st_ino==beforeMutation.st_ino,heldSocket.st_dev==beforeMutation.st_dev else {
            fatalError("Finite fake command did not perform its successful exact socket mutation")
        }
        fatalError("Successful local command hid a changed runtime endpoint")
    } catch RuntimeError.identity {}
    var mutated=stat(),heldSocket=stat()
    guard lstat(path,&mutated)==0,mutated.st_mode&S_IFMT==S_IFLNK,
          lstat(path+".fixture-held",&heldSocket)==0,heldSocket.st_ino==beforeMutation.st_ino,heldSocket.st_dev==beforeMutation.st_dev,
          unlink(path)==0,rename(path+".fixture-held",path)==0 else {fatalError("Finite fake command did not execute/restore its exact fixture mutation")}
    let moved=hidden+"/previous-run"
    guard rename(run,moved)==0 else {fatalError("Fixture directory rename failed")}
    try FileManager.default.createDirectory(atPath:run,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let replacement=try UnixControlSocket(path:path)
    defer {withExtendedLifetime(replacement) {}}
    try refused {try original.verify(deadline:ProcessInfo.processInfo.systemUptime+2)}
    _=try policy.capture(deadline:ProcessInfo.processInfo.systemUptime+2)
    print("PASS: descriptor-pinned private runtime socket chain, unsafe mode/ACL/symlink and replaced-directory/socket refusal, deny-only account ACL accepted; no daemon request")
}
