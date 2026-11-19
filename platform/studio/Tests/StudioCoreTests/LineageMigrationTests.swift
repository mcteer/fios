import Foundation
import CSQLite
import CryptoKit

func runLineageMigrationTests()throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)}
    let source=root.appendingPathComponent("source"),working=root.appendingPathComponent("working"),backup=root.appendingPathComponent("backup"),target=root.appendingPathComponent("migrated")
    let job=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:String(repeating:"1",count:32),canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    do {
        let journal=try Journal(directory:source)
        try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
        try journal.markDispatched(job:job,attempt:0)
        _=try ArtifactStore(directory:source.appendingPathComponent("artifacts"),availableBytes:{100<<30})
    }
    _=try StoppedStateBackup.create(directory:source,destination:working)
    // Construct an exact previous-format fixture; genuine old-artifact backup
    // production is separately exercised by check-platform-upgrade.
    var db:OpaquePointer?
    guard sqlite3_open(working.appendingPathComponent("state.sqlite").path,&db)==SQLITE_OK else {throw JournalError.storage}
    let changed=sqlite3_exec(db,"PRAGMA journal_mode=DELETE; DROP TABLE native_lineages; PRAGMA user_version=8",nil,nil,nil)
    let closed=sqlite3_close(db)
    guard changed==SQLITE_OK,closed==SQLITE_OK else {throw JournalError.storage}
    let original=try Data(contentsOf:working.appendingPathComponent("state.sqlite"))
    var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:working.appendingPathComponent("backup.json"))) as! [String:Any]
    manifest["journal_schema"]=8;manifest["journal_bytes"]=original.count
    manifest["journal_sha256"]=SHA256.hash(data:original).map{String(format:"%02x",$0)}.joined()
    let bytes=try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
    try bytes.write(to:working.appendingPathComponent("backup.json"))
    try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    for name in ["state.sqlite","backup.json","artifacts"] {try FileManager.default.copyItem(at:working.appendingPathComponent(name),to:backup.appendingPathComponent(name))}
    let digest=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    do {_=try Journal(directory:working);fatalError("Ordinary startup migrated previous native correlation")}
    catch JournalError.invalid {}
    _=try StoppedStateBackup.migrateEight(directory:backup,expectedSHA256:digest,destination:target)
    do {
        let journal=try Journal(directory:target)
        guard journal.migrationHeld,try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
              let retained=try journal.inferenceScope(job:job,attempt:0),retained.state == .uncertain,
              try retained.scope.encoded()==scope.encoded() else {throw JournalError.invalid}
    }
    let sealed=root.appendingPathComponent("sealed"),restored=root.appendingPathComponent("restored")
    let receipt=try StoppedStateBackup.create(directory:target,destination:sealed)
    _=try StoppedStateBackup.restore(directory:sealed,expectedSHA256:receipt.sha256,destination:restored)
    let restoredJournal=try Journal(directory:restored)
    guard restoredJournal.migrationHeld,try restoredJournal.unresolvedCount()==1,try restoredJournal.uncertainCount()==1,
          try Data(contentsOf:backup.appendingPathComponent("state.sqlite"))==original else {throw JournalError.invalid}
    let orphan=UUID().uuidString.lowercased(),hash=String(repeating:"c",count:64)
    let configuration=try SandboxConfiguration(job:orphan,nonce:hash,image:"sha256:"+hash,memory:512<<20,cpus:1)
    let payload=try JSONEncoder().encode(SandboxRecord(configuration:configuration)).map{String(format:"%02x",$0)}.joined()
    let bad=root.appendingPathComponent("orphan-backup"),refused=root.appendingPathComponent("orphan-migration")
    try FileManager.default.copyItem(at:backup,to:bad)
    let badDB=bad.appendingPathComponent("state.sqlite"),badManifest=bad.appendingPathComponent("backup.json")
    do {
        var db:OpaquePointer?
        guard sqlite3_open_v2(badDB.path,&db,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK else {throw JournalError.storage}
        defer {sqlite3_close(db)}
        let sql="INSERT INTO sandboxes(job,payload) VALUES('\(orphan)',CAST(X'\(payload)' AS TEXT))"
        guard sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    }
    let badBytes=try Data(contentsOf:badDB)
    manifest["journal_bytes"]=badBytes.count
    manifest["journal_sha256"]=SHA256.hash(data:badBytes).map{String(format:"%02x",$0)}.joined()
    let badMetadata=try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
    try badMetadata.write(to:badManifest)
    let badDigest=SHA256.hash(data:badMetadata).map{String(format:"%02x",$0)}.joined()
    _=try StoppedStateBackup.verify(directory:bad,expectedSHA256:badDigest,journalSchema:8)
    do {
        _=try StoppedStateBackup.migrateEight(directory:bad,expectedSHA256:badDigest,destination:refused)
        fatalError("Migration published orphan sandbox custody")
    } catch JournalError.invalid {}
    guard !FileManager.default.fileExists(atPath:refused.path),try Data(contentsOf:badDB)==badBytes,
          try Data(contentsOf:badManifest)==badMetadata else {throw JournalError.conflict}
    print("PASS: explicit copy-only schema8→9 migration retains exact scope and uncertainty; orphan sandbox backup refused without publication or source mutation")
}
