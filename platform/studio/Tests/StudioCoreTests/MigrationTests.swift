import Foundation
import CSQLite
import CryptoKit

private enum MigrationStageError:Error {case stage(String)}
enum MigrationTests {
    private static func step<T>(_ name:String,_ body:()throws->T)throws->T {
        do {return try body()}catch{throw MigrationStageError.stage(name)}
    }
    static func run() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var success=false
        defer {
            if success {try? FileManager.default.removeItem(at:root)}
            else {FileHandle.standardError.write(Data(("Migration fixture retained: "+root.path+"\n").utf8))}
        }
        let source=root.appendingPathComponent("source"),backup=root.appendingPathComponent("backup"),target=root.appendingPathComponent("migrated")
        let job=UUID().uuidString.lowercased()
        do {let journal=try Journal(directory:source);try journal.claim(job:job,attempt:0,model:"fixture/model")}
        try Data("{\"future_service_metadata\":true}".utf8).write(to:source.appendingPathComponent("service-recovery.json"))
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:source.appendingPathComponent("service-recovery.json").path)
        do {
            let store=try ArtifactStore(directory:source.appendingPathComponent("artifacts"),availableBytes:{100<<30})
            _=try store.publish(job:job,ownerHash:String(repeating:"a",count:64),data:Data("MIGRATION_EXPLICIT_EXPORT".utf8),now:1000)
        }
        _=try step("initial-backup"){try StoppedStateBackup.create(directory:source,destination:backup)}
        // Synthetic exact legacy layout only. Real old-artifact production of
        // this backup is a separate process rehearsal, not this unit receipt.
        let database=backup.appendingPathComponent("state.sqlite")
        var db:OpaquePointer?
        guard sqlite3_open(database.path,&db)==SQLITE_OK else {throw JournalError.storage}
        let code=sqlite3_exec(db,"PRAGMA journal_mode=DELETE; DROP TABLE inference_scopes; PRAGMA user_version=7",nil,nil,nil)
        let closed=sqlite3_close(db)
        guard code==SQLITE_OK,closed==SQLITE_OK else {throw JournalError.storage}
        let bytes=try Data(contentsOf:database)
        let manifestPath=backup.appendingPathComponent("backup.json")
        var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:manifestPath)) as! [String:Any]
        manifest["journal_schema"]=7;manifest["journal_bytes"]=bytes.count
        manifest["journal_sha256"]=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        let encoded=try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
        try encoded.write(to:manifestPath)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:manifestPath.path)
        let digest=SHA256.hash(data:encoded).map {String(format:"%02x",$0)}.joined()
        // Editing the synthetic working DB may leave SQLite-owned SHM cache.
        // Seal a fresh backup namespace from the verified closed main file;
        // do not weaken production verification or delete a runtime resource.
        let legacy=root.appendingPathComponent("legacy-backup")
        try FileManager.default.createDirectory(at:legacy,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        for name in ["state.sqlite","backup.json","artifacts","service-recovery.json"] {
            try FileManager.default.copyItem(at:backup.appendingPathComponent(name),to:legacy.appendingPathComponent(name))
        }
        do {_=try StoppedStateBackup.restore(directory:legacy,expectedSHA256:digest,destination:target);fatalError("Ordinary restore silently migrated legacy ownership")}
        catch JournalError.invalid {}
        _=try step("verify-legacy"){try StoppedStateBackup.verify(directory:legacy,expectedSHA256:digest,journalSchema:7)}
        let inspected=root.appendingPathComponent(".fios-restore-inspection")
        try FileManager.default.createDirectory(at:inspected,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        try FileManager.default.copyItem(at:database,to:inspected.appendingPathComponent("state.sqlite"))
        try step("convert-inspection"){try Journal.migrateSevenCopy(directory:inspected)}
        _=try step("migrate-copy"){try StoppedStateBackup.migrateSeven(directory:legacy,expectedSHA256:digest,destination:target)}
        guard try Data(contentsOf:legacy.appendingPathComponent("state.sqlite"))==bytes,try Data(contentsOf:legacy.appendingPathComponent("backup.json"))==encoded else {fatalError("Migration changed rollback source")}
        do {
            let migrated=try step("open-migrated"){try Journal(directory:target)}
            guard migrated.migrationHeld,try migrated.unresolvedCount()==1,try migrated.uncertainCount()==1,
                  try migrated.requestCount(job:job)==1 else {fatalError("Migration lost ownership/budget/maintenance hold")}
        }
        let secondBackup=root.appendingPathComponent("held-backup"),restored=root.appendingPathComponent("held-restore")
        let second=try step("backup-held"){try StoppedStateBackup.create(directory:target,destination:secondBackup)}
        _=try step("verify-held"){try StoppedStateBackup.verify(directory:secondBackup,expectedSHA256:second.sha256)}
        _=try step("restore-held"){try StoppedStateBackup.restore(directory:secondBackup,expectedSHA256:second.sha256,destination:restored)}
        do {
            let journal=try step("open-restored-held"){try Journal(directory:restored)}
            guard journal.migrationHeld,try journal.uncertainCount()==1,
                  try Data(contentsOf:restored.appendingPathComponent("service-recovery.json"))==Data(contentsOf:source.appendingPathComponent("service-recovery.json")) else {fatalError("Backup/restore lost migration hold or opaque recovery state")}
        }
        do {_=try StoppedStateBackup.migrateSeven(directory:legacy,expectedSHA256:digest,destination:target);fatalError("Migration overwrote destination")}
        catch JournalError.conflict {}
        for (index,sql) in ["CREATE TABLE future_ownership(id TEXT PRIMARY KEY)","DELETE FROM request_history"].enumerated() {
            let working=root.appendingPathComponent("bad-working-\(index)"),sealed=root.appendingPathComponent("bad-input-\(index)"),destination=root.appendingPathComponent("bad-output-\(index)")
            try FileManager.default.copyItem(at:legacy,to:working)
            var altered:OpaquePointer?
            guard sqlite3_open(working.appendingPathComponent("state.sqlite").path,&altered)==SQLITE_OK else {throw JournalError.storage}
            let mutation=sqlite3_exec(altered,sql,nil,nil,nil),closed=sqlite3_close(altered)
            guard mutation==SQLITE_OK,closed==SQLITE_OK else {throw JournalError.storage}
            let data=try Data(contentsOf:working.appendingPathComponent("state.sqlite"))
            var receipt=try JSONSerialization.jsonObject(with:Data(contentsOf:working.appendingPathComponent("backup.json"))) as! [String:Any]
            receipt["journal_bytes"]=data.count;receipt["journal_sha256"]=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
            let encoded=try JSONSerialization.data(withJSONObject:receipt,options:[.sortedKeys])
            try encoded.write(to:working.appendingPathComponent("backup.json"))
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:working.appendingPathComponent("backup.json").path)
            try FileManager.default.createDirectory(at:sealed,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            for name in ["state.sqlite","backup.json","artifacts","service-recovery.json"] {
                try FileManager.default.copyItem(at:working.appendingPathComponent(name),to:sealed.appendingPathComponent(name))
            }
            let hash=SHA256.hash(data:encoded).map {String(format:"%02x",$0)}.joined()
            _=try step("verify-incompatible-envelope"){try StoppedStateBackup.verify(directory:sealed,expectedSHA256:hash,journalSchema:7)}
            do {_=try StoppedStateBackup.migrateSeven(directory:sealed,expectedSHA256:hash,destination:destination);fatalError("Incompatible ownership was migrated")}
            catch JournalError.invalid {}
            guard !FileManager.default.fileExists(atPath:destination.path),try Data(contentsOf:sealed.appendingPathComponent("state.sqlite"))==data else {fatalError("Failed migration published or changed protected state")}
        }
        success=true
    }
}
