import Foundation
import Darwin
import CryptoKit

func runReleaseStagingTests()throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("fios-stage-test-"+UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)} // Private artifact bytes only; no process/runtime/state.
    let source=root.appendingPathComponent("source"),target=root.appendingPathComponent("staged")
    try FileManager.default.createDirectory(at:source,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let modes:[String:Int] = ["bin/studio-manager":0o755,"bin/studio-supervisor":0o755,"bin/studio-session":0o755,"bin/studioctl":0o755,
        "sandbox/runner.py":0o644,"sandbox/Dockerfile":0o644,"python/uv.lock":0o644,"launchd/lab.fios.studio.supervisor.plist":0o644,"launchd/lab.fios.studio.session.plist":0o644]
    var artifacts:[[String:Any]]=[]
    for (name,mode) in modes.sorted(by:{$0.key<$1.key}) {
        let file=source.appendingPathComponent(name)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var bytes=Data(repeating:0,count:32)
        if name.hasPrefix("bin/") {bytes.replaceSubrange(0..<8,with:[0xcf,0xfa,0xed,0xfe,0x0c,0,0,1])}
        try bytes.write(to:file);try FileManager.default.setAttributes([.posixPermissions:mode],ofItemAtPath:file.path)
        artifacts.append(["path":name,"bytes":bytes.count,"mode":mode,"sha256":SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()])
    }
    let data=try JSONSerialization.data(withJSONObject:["schema":1,"journal_schema":8,"approval":"development_observation_only","package_complete":false,
        "activation":["managed_inference":false,"sandbox_tasks":false,"native_lifecycle":false,"launchd_installation":false],"artifacts":artifacts],options:[.sortedKeys])
    let receipt=source.appendingPathComponent("release.json")
    try data.write(to:receipt);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:receipt.path)
    let hash=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
    let result=try PlatformReleaseStaging.create(source:source,expectedSHA256:hash,destination:target)
    guard result.artifacts==9,result.manifestSHA256==hash,try Data(contentsOf:target.appendingPathComponent("release.json"))==data else {fatalError("Staged release did not retain reviewed bytes")}
    do {_=try PlatformReleaseStaging.create(source:source,expectedSHA256:hash,destination:target);fatalError("Release staging replaced existing directory")}catch PlatformReleaseStagingError.invalid {}
    let nested=source.appendingPathComponent("nested")
    do {_=try PlatformReleaseStaging.create(source:source,expectedSHA256:hash,destination:nested);fatalError("Release staging accepted a nested destination")}catch PlatformReleaseStagingError.invalid {}
    guard let resolved=realpath(source.path,nil) else {throw ControlError.internal_error}
    let canonicalSource=String(cString:resolved);free(resolved)
    let aliasedNested=URL(fileURLWithPath:canonicalSource).appendingPathComponent("bin/nested-copy")
    do {_=try PlatformReleaseStaging.create(source:source,expectedSHA256:hash,destination:aliasedNested);fatalError("Release staging missed canonical nested destination")}
    catch PlatformReleaseStagingError.invalid {}
    guard !FileManager.default.fileExists(atPath:aliasedNested.path) else {fatalError("Nested destination refusal wrote source bytes")}
    let linked=root.appendingPathComponent("linked");try FileManager.default.createSymbolicLink(at:linked,withDestinationURL:target)
    do {_=try PlatformReleaseStaging.create(source:source,expectedSHA256:hash,destination:linked);fatalError("Release staging replaced symlink destination")}catch PlatformReleaseStagingError.invalid {}
    let artifact=source.appendingPathComponent("sandbox/runner.py")
    let original=try Data(contentsOf:artifact)
    try Data(repeating:1,count:original.count).write(to:artifact)
    do {_=try PlatformReleaseStaging.create(source:source,expectedSHA256:hash,destination:root.appendingPathComponent("wrong-hash"));fatalError("Release staging accepted changed artifact bytes")}
    catch PlatformReleaseStagingError.retained {}
    guard !FileManager.default.fileExists(atPath:root.appendingPathComponent("wrong-hash").path) else {fatalError("Failed artifact copy was published")}
    try FileManager.default.removeItem(at:artifact)
    guard mkfifo(artifact.path,0o600)==0 else {throw ControlError.internal_error}
    let began=ProcessInfo.processInfo.systemUptime
    do {_=try PlatformReleaseStaging.create(source:source,expectedSHA256:hash,destination:root.appendingPathComponent("fifo-result"));fatalError("Release staging accepted a FIFO")}
    catch PlatformReleaseStagingError.retained(let name) {guard name.hasPrefix(".fios-stage-"),ProcessInfo.processInfo.systemUptime-began<1 else {fatalError("Special file blocked staging")}}
    catch PlatformReleaseStagingError.invalid {}
    guard try Data(contentsOf:target.appendingPathComponent("release.json"))==data else {fatalError("Failure mutated previously staged artifact")}
    print("PASS: descriptor-relative hash-bound artifact staging, exact private copy, no-replace/nesting/link/special-file refusal; no installation or execution")
}
