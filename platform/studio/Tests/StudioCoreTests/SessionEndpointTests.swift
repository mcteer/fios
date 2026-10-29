import Foundation
import Darwin
import CryptoKit

func runSessionEndpointTests()throws {
    let hash=String(repeating:"a",count:64),pins:[ManagedService:String]=[.mlx:hash,.orbstack:hash]
    let profile=try ServiceLaunchProfile.digest(pins),boot=try HostBoot.identity(),instance=UUID().uuidString.lowercased()
    let start=String(try WorkerResources.startIdentifier(pid:getpid()))
    let base:[String:Any]=["version":1,"pid":getpid(),"uid":geteuid(),"process_start":start,"boot":boot,"instance":instance,"profile":profile]
    func packet(_ changes:[String:Any]=[:])throws->Data {
        var value=base;for (key,item) in changes {value[key]=item};return try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
    }
    let descriptor=try SessionEndpointDescriptor(packet(),expectedBoot:boot,expectedProfile:profile,expectedUID:geteuid())
    guard descriptor.pid==getpid(),descriptor.start==UInt64(start),descriptor.instance==instance else {fatalError("Session endpoint tuple lost its exact identity")}
    for changes:[String:Any] in [["version":2],["uid":true],["uid":0],["pid":1],["pid":1.5],["process_start":"01"],["process_start":1],
        ["boot":UUID().uuidString.lowercased()],["instance":"arbitrary"],["profile":String(repeating:"b",count:64)],["path":"/tmp/other"],["role":"manager"]] {
        do {_=try SessionEndpointDescriptor(packet(changes),expectedBoot:boot,expectedProfile:profile,expectedUID:geteuid());fatalError("Unbound or widened endpoint metadata accepted")}catch ControlError.unauthorized {}
    }
    let text=String(decoding:try packet(),as:UTF8.self)
    for bytes in [Data(text.replacingOccurrences(of:"\"version\":1",with:"\"version\":1.0").utf8),
                  Data(("{\"version\":1,"+text.dropFirst()).utf8),Data(repeating:32,count:2049)] {
        do {_=try SessionEndpointDescriptor(bytes,expectedBoot:boot,expectedProfile:profile,expectedUID:geteuid());fatalError("Ambiguous or oversized endpoint metadata accepted")}catch ControlError.unauthorized {}
    }
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)}
    let image=try VerifiedExecutable(path:"/usr/bin/true",sha256:hash)
    guard try SessionControlClient.discover(directory:root,helper:image,approvedHashes:pins)==nil else {fatalError("Missing endpoint became authority")}
    let file=root.appendingPathComponent("session-control.json")
    try AtomicState.write(packet(),to:file)
    guard try SessionControlClient.discover(directory:root,helper:image,approvedHashes:pins) != nil else {fatalError("Private endpoint bootstrap failed")}
    // Discover only parses protected metadata. The deliberately wrong helper
    // pin cannot pass the separate connection's actual kernel verification.
    try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:file.path)
    do {_=try SessionControlClient.discover(directory:root,helper:image,approvedHashes:pins);fatalError("Public endpoint metadata accepted")}catch ControlError.unauthorized {}
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    let alias=root.appendingPathComponent("alias")
    try FileManager.default.linkItem(at:file,to:alias)
    do {_=try SessionControlClient.discover(directory:root,helper:image,approvedHashes:pins);fatalError("Hardlinked endpoint metadata accepted")}catch ControlError.unauthorized {}
    try FileManager.default.removeItem(at:file)
    try FileManager.default.createSymbolicLink(at:file,withDestinationURL:alias)
    do {_=try SessionControlClient.discover(directory:root,helper:image,approvedHashes:pins);fatalError("Symlink endpoint metadata accepted")}catch ControlError.unauthorized {}
    print("PASS: bounded private session endpoint boot/user/profile/PID/start/nonce decoding, missing/widened/coerced/foreign refusal; bootstrap metadata never substitutes for authenticated peer readiness")
}
