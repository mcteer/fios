import Foundation
import Darwin
import CryptoKit

func runServiceIdentityTests() throws {
    let binary="/bin/sleep"
    let hash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:binary))).map{String(format:"%02x",$0)}.joined()
    let process=Process();process.executableURL=URL(fileURLWithPath:binary);process.arguments=["1"]
    process.environment=["PATH":"/usr/bin:/bin","LANG":"C"];process.standardInput=FileHandle.nullDevice
    process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
    try process.run();defer {process.waitUntilExit()}
    let start=try WorkerResources.startIdentifier(pid:process.processIdentifier)
    let executable=try VerifiedExecutable(path:binary,sha256:hash)
    let peer=NativeControlPeer(pid:process.processIdentifier,start:start,executable:executable)
    let identity=try ServiceIdentity.verified(peer:peer,expectedUID:geteuid(),deadline:ProcessInfo.processInfo.systemUptime+0.8)
    guard identity.pid==process.processIdentifier,identity.start==start,identity.sha256==hash else {fatalError("Service identity lost kernel binding")}
    for bad in [NativeControlPeer(pid:peer.pid,start:start+1,executable:executable),
                NativeControlPeer(pid:peer.pid,start:start,executable:try VerifiedExecutable(path:binary,sha256:String(repeating:"0",count:64)))] {
        do {_ = try ServiceIdentity.verified(peer:bad,expectedUID:geteuid(),deadline:ProcessInfo.processInfo.systemUptime+0.8);fatalError("Unverified service process adopted")}
        catch {}
    }
    do {_ = try ServiceIdentity.verified(peer:peer,expectedUID:0,deadline:ProcessInfo.processInfo.systemUptime+0.8);fatalError("Root service principal accepted")}
    catch {}
    process.waitUntilExit()
    do {_ = try ServiceIdentity.verified(peer:peer,expectedUID:geteuid(),deadline:ProcessInfo.processInfo.systemUptime+0.8);fatalError("Exited process adopted")}
    catch {}
    print("PASS: real disposable process UID/start/path/FD-hash binding, changed identity/root/exited-process refusal; no native app action")
}
