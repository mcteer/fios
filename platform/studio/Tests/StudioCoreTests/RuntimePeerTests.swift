import Foundation
import Darwin
import CryptoKit

func runtimePeerTestExecutable()throws->VerifiedExecutable {
    var buffer=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
    guard proc_pidpath(getpid(),&buffer,UInt32(buffer.count))>0,
          let image=String(bytes:buffer.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {fatalError("Missing actual test kernel image")}
    let sha=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:image))).map {String(format:"%02x",$0)}.joined()
    return try VerifiedExecutable(path:image,sha256:sha)
}

func runRuntimePeerTests()throws {
    let directory="/private/tmp/f9-peer-"+UUID().uuidString.lowercased()
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(atPath:directory)}
    let path=directory+"/fixture.sock",listener=try UnixControlSocket(path:path)
    defer {withExtendedLifetime(listener){}}
    let executable=try runtimePeerTestExecutable(),image=executable.path,sha=executable.sha256
    let policy=try RuntimePeerPolicy(uid:geteuid(),executable:executable)
    let connection=try policy.connect(path:path,deadline:ProcessInfo.processInfo.systemUptime+2)
    defer {withExtendedLifetime(connection){}}
    let identity=try connection.verify(deadline:ProcessInfo.processInfo.systemUptime+2)
    guard identity.pid==getpid(),identity.start==(try WorkerResources.startIdentifier(pid:getpid())),identity.sha256==sha else {fatalError("Runtime peer did not bind the actual kernel process")}
    for expected in [try VerifiedExecutable(path:image,sha256:String(repeating:"0",count:64)),try VerifiedExecutable(path:"/usr/bin/true",sha256:sha)] {
        do {_=try RuntimePeerPolicy(uid:geteuid(),executable:expected).connect(path:path,deadline:ProcessInfo.processInfo.systemUptime+2);fatalError("Same-UID foreign runtime image accepted")}catch RuntimeError.identity {}
    }
    do {_=try policy.connect(path:path,deadline:ProcessInfo.processInfo.systemUptime-1);fatalError("Expired peer authentication restarted its deadline")}catch RuntimeError.deadline {}
    guard let accepted=try listener.acceptPeer() else {fatalError("Fixture peer connection missing")}
    defer {Darwin.close(accepted)}
    let pending=try RuntimePeerAuthentication(policy:policy,fd:accepted,deadline:ProcessInfo.processInfo.systemUptime+2)
    var outcome:Result<ServiceIdentity,RuntimeError>?
    let limit=ProcessInfo.processInfo.systemUptime+2
    while outcome==nil && ProcessInfo.processInfo.systemUptime<limit {outcome=pending.take();if outcome==nil {Thread.sleep(forTimeInterval:0.001)}}
    guard let outcome,try outcome.get()==identity else {fatalError("Off-loop runtime peer result lost its kernel identity")}
    var byte:UInt8=0
    guard Darwin.read(accepted,&byte,1)<0,[EAGAIN,EWOULDBLOCK].contains(errno) else {fatalError("Passive runtime identity probe sent daemon bytes")}
    print("PASS: actual Unix kernel UID/PID/start/path/byte-hash runtime peer binding, foreign same-UID image/hash and expired deadline refusal, passive probe sends zero bytes; private fixture only")
}
