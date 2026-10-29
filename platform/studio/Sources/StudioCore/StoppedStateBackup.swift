import Foundation
import Darwin
import CryptoKit

public struct StateBackupReceipt {
    public let scope:String
    public let bytes:Int64
    public let artifacts:Int
    public let sha256:String
}

public enum StoppedStateBackup {
    // Preserve opaque future ownership metadata without interpreting it as
    // permission/completion. The controller independently validates on startup.
    static func serviceRecoveryPayload(directory:URL)throws->Data? {
        try privatePayload(directory:directory,name:"service-recovery.json")
    }
    static func migrationHoldPayload(directory:URL)throws->Data? {
        try privatePayload(directory:directory,name:"migration-hold.json")
    }
    private static func privatePayload(directory:URL,name:String)throws->Data? {
        let path=directory.appendingPathComponent(name).path
        let fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        if fd<0,errno==ENOENT {return nil}
        guard fd>=0 else {throw JournalError.invalid};defer {close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_uid==geteuid(),
              before.st_mode&0o7777==0o600,before.st_nlink==1,(1...4096).contains(before.st_size) else {throw JournalError.invalid}
        var bytes=[UInt8](repeating:0,count:4097),offset=0
        while offset<bytes.count {
            let count=bytes.withUnsafeMutableBytes {Darwin.read(fd,$0.baseAddress!.advanced(by:offset),$0.count-offset)}
            if count<0,errno==EINTR {continue}
            guard count>=0 else {throw JournalError.invalid};if count==0 {break};offset+=count
        }
        guard offset==before.st_size,fstat(fd,&after)==0,lstat(path,&named)==0,
              before.st_dev==after.st_dev,before.st_ino==after.st_ino,before.st_size==after.st_size,
              before.st_mode==after.st_mode,before.st_uid==after.st_uid,after.st_nlink==1,
              before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
              named.st_dev==after.st_dev,named.st_ino==after.st_ino,named.st_nlink==1 else {throw JournalError.invalid}
        return Data(bytes.prefix(offset))
    }
    // One lexical writer fence spans both snapshots. Native uncertainty may
    // continue independently; no completion/reap inference or execution replay.
    public static func create(directory:URL,destination:URL)throws->StateBackupReceipt {
        let stopped=try StoppedPlatformState(directory:directory)
        defer {withExtendedLifetime(stopped) {}}
        let protected=directory.appendingPathComponent("artifacts").resolvingSymlinksInPath().standardizedFileURL.path
        let target=destination.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent).standardizedFileURL.path
        guard destination.isFileURL,target != protected,!target.hasPrefix(protected+"/") else {throw JournalError.invalid}
        var parent=stat()
        guard lstat(destination.deletingLastPathComponent().path,&parent)==0,parent.st_mode&S_IFMT==S_IFDIR,parent.st_uid==geteuid(),parent.st_mode&0o077==0 else {throw JournalError.invalid}
        guard mkdir(destination.path,0o700)==0 else {throw JournalError.conflict}
        var success=false
        defer {if !success {try? FileManager.default.removeItem(at:destination)}}
        let journal=try StoppedJournalBackup.create(directory:directory,destination:destination.appendingPathComponent("state.sqlite"),stopped:stopped)
        let artifacts=try StoppedArtifactBackup.create(directory:directory,destination:destination.appendingPathComponent("artifacts"),stopped:stopped)
        let files=try JSONSerialization.jsonObject(with:JSONEncoder().encode(artifacts.files))
        let recovery=try serviceRecoveryPayload(directory:directory)
        let hold=try migrationHoldPayload(directory:directory)
        let scope=hold != nil ? "platform_journal_exports_and_migration_hold":recovery==nil ? "platform_journal_and_exports":"platform_journal_exports_and_service_recovery"
        var manifest:[String:Any]=["version":hold != nil ? 3:recovery==nil ? 1:2,"scope":scope,"host_hash":try StoppedPlatformState.hostHash(),"owner_uid":Int(geteuid()),"journal_schema":journal.schema,"journal_application_id":"FIS9",
            "journal_bytes":journal.bytes,"journal_sha256":journal.sha256,"artifact_index_sha256":artifacts.indexSHA256,"artifact_files":files]
        if let recovery {
            let path=destination.appendingPathComponent("service-recovery.json")
            try recovery.write(to:path,options:.withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
            let fd=open(path.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw JournalError.storage};defer {close(fd)}
            guard fsync(fd)==0 else {throw JournalError.storage}
            manifest["service_recovery_bytes"]=recovery.count
            manifest["service_recovery_sha256"]=SHA256.hash(data:recovery).map {String(format:"%02x",$0)}.joined()
        }
        if let hold {
            let path=destination.appendingPathComponent("migration-hold.json")
            try hold.write(to:path,options:.withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
            let fd=open(path.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw JournalError.storage};defer {close(fd)}
            guard fsync(fd)==0 else {throw JournalError.storage}
            manifest["migration_hold_bytes"]=hold.count
            manifest["migration_hold_sha256"]=SHA256.hash(data:hold).map {String(format:"%02x",$0)}.joined()
            if recovery==nil {manifest["service_recovery_bytes"]=NSNull();manifest["service_recovery_sha256"]=NSNull()}
        }
        let data=try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
        guard data.count<=65536 else {throw JournalError.invalid}
        let path=destination.appendingPathComponent("backup.json")
        try data.write(to:path,options:.withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
        let fd=open(path.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw JournalError.storage};defer {close(fd)}
        let folder=open(destination.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard folder>=0 else {throw JournalError.storage};defer {close(folder)}
        let outer=open(destination.deletingLastPathComponent().path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard outer>=0 else {throw JournalError.storage};defer {close(outer)}
        guard fsync(fd)==0,fsync(folder)==0,fsync(outer)==0 else {throw JournalError.storage}
        success=true
        return StateBackupReceipt(scope:scope,bytes:journal.bytes+artifacts.bytes+Int64(recovery?.count ?? 0)+Int64(hold?.count ?? 0),artifacts:artifacts.artifacts,sha256:SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined())
    }
}
