import Foundation
import CryptoKit
import Darwin

func runPythonTreeTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let data=Data("ordinary declared runtime fixture".utf8)
    try data.write(to:directory.appendingPathComponent("module.py"));chmod(directory.appendingPathComponent("module.py").path,0o644)
    let hash=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
    let value:[String:Any]=["version":1,"purpose":"python_worker_runtime_candidate","python_version":"3.11.17","platform":"macos/arm64",
        "uv_lock_sha256":String(repeating:"a",count:64),"producer_sha256":String(repeating:"b",count:64),"release_template_sha256":String(repeating:"c",count:64),
        "agent_sources":[:],"distributions":[],"files":["module.py":["bytes":data.count,"sha256":hash,"mode":0o644]],"bytes":data.count,
        "console_wrappers_excluded":0,"probe":[:],"scope":"declared_installed_runtime_bytes_not_publisher_build_or_whole_os_provenance",
        "immutable_tree_enrolled":false,"approved":false,"activation":false]
    let manifest=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
    try manifest.write(to:directory.appendingPathComponent("candidate.json"));chmod(directory.appendingPathComponent("candidate.json").path,0o644)
    let digest=SHA256.hash(data:manifest).map {String(format:"%02x",$0)}.joined()
    let review=try PythonRuntimeTreeReview.privateCandidate(directory:directory,manifestSHA256:digest)
    guard review.files==1,review.bytes==data.count,!review.rootProtected else {throw RuntimeError.identity}
    do {_=try PythonRuntimeTreeReview.rootProtectedCandidate(directory:directory,manifestSHA256:digest);throw RuntimeError.identity}
    catch ControlError.unauthorized {}
    try Data("changed ordinary data".utf8).write(to:directory.appendingPathComponent("module.py"))
    do {_=try PythonRuntimeTreeReview.privateCandidate(directory:directory,manifestSHA256:digest);throw RuntimeError.identity}
    catch ControlError.unauthorized {}
    try data.write(to:directory.appendingPathComponent("module.py"));chmod(directory.appendingPathComponent("module.py").path,0o644)
    try Data("extra ordinary file".utf8).write(to:directory.appendingPathComponent("notes.txt"))
    do {_=try PythonRuntimeTreeReview.privateCandidate(directory:directory,manifestSHA256:digest);throw RuntimeError.identity}
    catch ControlError.unauthorized {}
    print("PASS: declared Python tree bytes bind private review, changes/unlisted data refuse and private data cannot pass root protection; no execution or enrollment")
}
