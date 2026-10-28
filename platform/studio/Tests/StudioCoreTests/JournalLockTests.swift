import Foundation
import Darwin

func runJournalLockTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)}
    let sentinel=root.appendingPathComponent("unrelated-sentinel"),bytes=Data("LOCK_METADATA_ONLY".utf8)
    try bytes.write(to:sentinel)
    guard chmod(sentinel.path,0o600)==0 else {throw JournalError.storage}
    var failures:[String]=[]
    for name in ["hardlinked","writable","setid"] {
        let directory:URL
        if name=="setid" {
            guard let path=ProcessInfo.processInfo.environment["FIOS_PLATFORM_LOCK_SETID_FIXTURE"],URL(fileURLWithPath:path).lastPathComponent=="manager.lock" else {fatalError("Missing runner-prepared lock metadata fixture")}
            directory=URL(fileURLWithPath:path).deletingLastPathComponent()
            var actual=stat()
            guard lstat(path,&actual)==0,actual.st_uid==geteuid(),actual.st_mode&0o7777==0o4700 else {fatalError("Lock set-ID metadata stripped; no refusal coverage")}
        } else {
            directory=root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let lock=directory.appendingPathComponent("manager.lock")
            if name=="hardlinked" {try FileManager.default.linkItem(at:sentinel,to:lock)}
            else {try Data().write(to:lock);guard chmod(lock.path,0o666)==0 else {throw JournalError.storage}}
        }
        do {_ = try Journal(directory:directory);failures.append("Unsafe manager lock accepted: "+name)}
        catch JournalError.invalid {}
        guard try Data(contentsOf:sentinel)==bytes else {fatalError("Lock metadata probe changed unrelated sentinel")}
    }
    guard failures.isEmpty else {fatalError(failures.joined(separator:"; "))}
    let directory=root.appendingPathComponent("valid")
    do {
        let owned=try Journal(directory:directory)
        try withExtendedLifetime(owned) {
            do {_ = try Journal(directory:directory);fatalError("Duplicate writer admitted")}
            catch JournalError.locked {}
        }
    }
    _ = try Journal(directory:directory)
    print("PASS: private regular single-link manager lock refuses hardlink/writable/set-ID metadata, preserves sentinel and enforces writer lifetime")
}
