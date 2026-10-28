import Foundation
import Darwin
import CryptoKit

func runRootPolicyFileTests() throws {
    // Public OS metadata, not a credential/config file. No privileged writes.
    let path="/System/Library/CoreServices/SystemVersion.plist"
    let expected=try Data(contentsOf:URL(fileURLWithPath:path))
    let hash=SHA256.hash(data:expected).map {String(format:"%02x",$0)}.joined()
    guard try RootPolicyFile.read(path:path,maximum:65536,expectedSHA256:hash)==expected else {fatalError("Root-owned metadata could not be read through anchored immutable parents")}
    do {_=try RootPolicyFile.read(path:path,maximum:65536,expectedSHA256:String(repeating:"0",count:64));fatalError("Root policy digest mismatch accepted")}catch ControlError.unauthorized {}
    do {_=try RootPolicyFile.read(path:path,maximum:1);fatalError("Root policy size limit ignored")}catch ControlError.unauthorized {}
    for alias in ["/System//Library/CoreServices/SystemVersion.plist","/System/Library/../Library/CoreServices/SystemVersion.plist",path+"\0ignored"] {
        do {_=try RootPolicyFile.read(path:alias,maximum:65536);fatalError("Root policy path alias accepted")}catch ControlError.unauthorized {}
    }
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let file=directory.appendingPathComponent("policy.json")
    try expected.write(to:file);try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:file.path)
    do {_=try RootPolicyFile.read(path:file.path,maximum:65536,expectedSHA256:hash);fatalError("Same-user copy minted root enrollment authority")}catch ControlError.unauthorized {}
    let link=directory.appendingPathComponent("root-policy-alias")
    try FileManager.default.createSymbolicLink(atPath:link.path,withDestinationPath:path)
    do {_=try RootPolicyFile.read(path:link.path,maximum:65536,expectedSHA256:hash);fatalError("User alias minted root enrollment authority")}catch ControlError.unauthorized {}
    print("PASS: anchored root-owned immutable policy-file read, genuine public OS metadata/hash proof, size/path alias and same-user/symlink refusal; no installation or privileged writes")
}
