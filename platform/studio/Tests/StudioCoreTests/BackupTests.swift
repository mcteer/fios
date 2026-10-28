import Foundation
import CSQLite
import CryptoKit
import Darwin

func runBackupTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let state=root.appendingPathComponent("state"),backup=root.appendingPathComponent("backup.sqlite")
    let job=UUID().uuidString.lowercased()
    do {
        let journal=try Journal(directory:state)
        try journal.claim(job:job,attempt:0,model:"fixture/model")
        var refused=false
        do {_=try StoppedJournalBackup.create(directory:state,destination:backup)} catch {refused=true}
        guard refused else {fatalError("Live single-writer database was backed up as stopped")}
    }
    do {
        let supervisor=open(state.appendingPathComponent("supervisor.lock").path,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard supervisor>=0,flock(supervisor,LOCK_EX|LOCK_NB)==0 else {throw JournalError.storage}
        defer {flock(supervisor,LOCK_UN);close(supervisor)}
        do {_=try StoppedJournalBackup.create(directory:state,destination:backup);fatalError("Backup accepted a live supervisor capable of restarting the manager")}catch JournalError.locked {}
    }
    do {
        let stopped=try StoppedPlatformState(directory:state)
        let contender=open(state.appendingPathComponent("supervisor.lock").path,O_RDWR|O_NOFOLLOW|O_CLOEXEC)
        guard contender>=0 else {throw JournalError.storage}
        defer {close(contender)}
        try withExtendedLifetime(stopped) {
            guard flock(contender,LOCK_EX|LOCK_NB) != 0 else {fatalError("Supervisor could restart while offline writer fence was held")}
            do {_=try Journal(directory:state);fatalError("Manager opened state during offline writer fence")}catch JournalError.locked {}
        }
    }
    let receipt=try StoppedJournalBackup.create(directory:state,destination:backup)
    guard receipt.schema==7,receipt.sha256.count==64,receipt.bytes>100 else {fatalError("No bounded integrity receipt")}
    let copy=root.appendingPathComponent("restored")
    try FileManager.default.createDirectory(at:copy,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    try FileManager.default.copyItem(at:backup,to:copy.appendingPathComponent("state.sqlite"))
    do {
        let restored=try Journal(directory:copy)
        guard try restored.unresolvedCount()==1,try restored.uncertainCount()==1 else {fatalError("Backup lost independent native ownership")}
    }
    var overwritten=false
    do {_=try StoppedJournalBackup.create(directory:state,destination:backup);overwritten=true} catch {}
    guard !overwritten else {fatalError("Backup overwrote an existing path")}
    let foreign=root.appendingPathComponent("not-platform")
    try FileManager.default.createDirectory(at:foreign,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    try Data(repeating:0,count:100).write(to:foreign.appendingPathComponent("state.sqlite"))
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:foreign.appendingPathComponent("state.sqlite").path)
    do {_=try StoppedJournalBackup.create(directory:foreign,destination:root.appendingPathComponent("bad.sqlite"));fatalError("Unmarked database accepted")} catch JournalError.invalid {}
    let future=root.appendingPathComponent("future")
    try FileManager.default.createDirectory(at:future,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let futureFile=future.appendingPathComponent("state.sqlite")
    try FileManager.default.copyItem(at:backup,to:futureFile)
    var database:OpaquePointer?
    guard sqlite3_open_v2(futureFile.path,&database,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK else {throw JournalError.storage}
    let changed=sqlite3_exec(database,"PRAGMA user_version=8",nil,nil,nil)
    sqlite3_close(database)
    guard changed==SQLITE_OK else {throw JournalError.storage}
    let before=try Data(contentsOf:futureFile)
    do {_=try Journal(directory:future);fatalError("Future ownership schema silently downgraded")} catch JournalError.invalid {}
    guard try Data(contentsOf:futureFile)==before else {fatalError("Rejected future journal was mutated")}
    let payload=Data("EXPLICIT_EXPORT_FIXTURE".utf8),owner=String(repeating:"a",count:64)
    var artifact=""
    do {
        let store=try ArtifactStore(directory:state.appendingPathComponent("artifacts"),availableBytes:{100<<30})
        artifact=try store.publish(job:job,ownerHash:owner,data:payload,now:1000)
        do {_=try StoppedArtifactBackup.create(directory:state,destination:root.appendingPathComponent("live-exports"));fatalError("Active artifact writer was snapshotted")} catch JournalError.locked {}
    }
    let exports=root.appendingPathComponent("exports-copy")
    let indexBefore=try Data(contentsOf:state.appendingPathComponent("artifacts/index.json"))
    let saved=try StoppedArtifactBackup.create(directory:state,destination:exports)
    guard saved.artifacts==1,saved.bytes==payload.count,saved.indexSHA256.count==64,
          try Data(contentsOf:state.appendingPathComponent("artifacts/index.json"))==indexBefore else {fatalError("Export snapshot mutated source or lost data")}
    do {
        let restored=try ArtifactStore(directory:exports,availableBytes:{100<<30})
        var stream=try restored.download(id:artifact,ownerHash:owner,now:1001)
        _=try stream.next(now:1001)
        guard case .chunk(0,let encoded)=try stream.next(now:1001),Data(base64Encoded:encoded)==payload else {fatalError("Restored export differs")}
    }
    let indexPath=state.appendingPathComponent("artifacts/index.json")
    var unknown=try JSONSerialization.jsonObject(with:indexBefore) as! [String:Any]
    unknown["unreviewed_ownership"]=true
    try JSONSerialization.data(withJSONObject:unknown).write(to:indexPath)
    do {_=try ArtifactStore(directory:state.appendingPathComponent("artifacts"),availableBytes:{100<<30});fatalError("Unknown artifact ownership fields ignored")} catch ArtifactError.invalid {}
    try indexBefore.write(to:indexPath)
    let link=root.appendingPathComponent("external-link")
    try FileManager.default.linkItem(at:state.appendingPathComponent("artifacts/"+artifact+".blob"),to:link)
    do {_=try StoppedArtifactBackup.create(directory:state,destination:root.appendingPathComponent("linked-copy"));fatalError("Linked export accepted")} catch JournalError.invalid {}
    try FileManager.default.removeItem(at:link)
    let bundle=root.appendingPathComponent("state-bundle")
    let bundleReceipt=try StoppedStateBackup.create(directory:state,destination:bundle)
    guard bundleReceipt.artifacts==1,bundleReceipt.sha256.count==64 else {fatalError("No full state snapshot receipt")}
    do {_=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:bundleReceipt.sha256,destination:bundle.appendingPathComponent("nested"));fatalError("Restore modified its source archive")} catch JournalError.invalid {}
    let alias=root.appendingPathComponent("state-alias")
    try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:state)
    do {_=try StoppedStateBackup.create(directory:state,destination:alias.appendingPathComponent("artifacts/nested"));fatalError("Snapshot entered source exports through an alias")} catch JournalError.invalid {}
    let checked=try StoppedStateBackup.verify(directory:bundle,expectedSHA256:bundleReceipt.sha256)
    guard checked.bytes==bundleReceipt.bytes,checked.artifacts==1 else {fatalError("Snapshot verification differs")}
    do {_=try StoppedStateBackup.verify(directory:bundle,expectedSHA256:String(repeating:"0",count:64));fatalError("Unreviewed snapshot accepted")} catch JournalError.invalid {}
    let corrupt=root.appendingPathComponent("corrupt-bundle")
    try FileManager.default.copyItem(at:bundle,to:corrupt)
    try Data("changed export".utf8).write(to:corrupt.appendingPathComponent("artifacts/"+artifact+".blob"))
    do {_=try StoppedStateBackup.verify(directory:corrupt,expectedSHA256:bundleReceipt.sha256);fatalError("Changed export verified")} catch JournalError.invalid {}
    let foreignBundle=root.appendingPathComponent("foreign-bundle")
    try FileManager.default.copyItem(at:bundle,to:foreignBundle)
    let manifestPath=foreignBundle.appendingPathComponent("backup.json")
    var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:manifestPath)) as! [String:Any]
    let localHost=manifest["host_hash"]!
    for field in ["host_hash","owner_uid"] {
        manifest["host_hash"]=localHost
        manifest["owner_uid"]=Int(geteuid())
        if field=="host_hash" {manifest[field]=String(repeating:"0",count:64)} else {manifest[field]=Int(geteuid())+1}
        let bytes=try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
        try bytes.write(to:manifestPath)
        let hash=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        do {_=try StoppedStateBackup.verify(directory:foreignBundle,expectedSHA256:hash);fatalError("Foreign host/user snapshot was adopted")} catch JournalError.invalid {}
    }
    let restoredState=root.appendingPathComponent("restored-state")
    _=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:bundleReceipt.sha256,destination:restoredState)
    _=try StoppedStateBackup.verify(directory:restoredState,expectedSHA256:bundleReceipt.sha256)
    do {_=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:bundleReceipt.sha256,destination:state);fatalError("In-place restoration overwrote live state") } catch JournalError.conflict {}
    do {
        let restoredJournal=try Journal(directory:restoredState)
        let restoredExports=try ArtifactStore(directory:restoredState.appendingPathComponent("artifacts"),availableBytes:{100<<30})
        guard try restoredJournal.unresolvedCount()==1,try restoredJournal.uncertainCount()==1 else {fatalError("Bundle erased native uncertainty")}
        var stream=try restoredExports.download(id:artifact,ownerHash:owner,now:1001)
        _=try stream.next(now:1001)
        guard case .chunk(0,let encoded)=try stream.next(now:1001),Data(base64Encoded:encoded)==payload else {fatalError("Bundle lost explicit export")}
    }
    print("PASS: supervisor+manager-fenced stopped-only bounded platform-marked SQLite backup, immutable receipt/no overwrite and independent uncertainty preserved on restore; no Fios database access")
}
