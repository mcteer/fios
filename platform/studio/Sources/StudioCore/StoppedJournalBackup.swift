import Foundation
import Darwin
import CSQLite
import CryptoKit

public struct JournalBackupReceipt {
    public let schema:Int
    public let bytes:Int64
    public let sha256:String
}

// Explicit offline/operator utility, never an IPC task/model operation. This
// snapshots only the platform metadata journal, not exports or credentials.
public enum StoppedJournalBackup {
    public static func create(directory:URL,destination:URL)throws->JournalBackupReceipt {
        let stopped=try StoppedPlatformState(directory:directory)
        return try create(directory:directory,destination:destination,stopped:stopped)
    }
    static func create(directory:URL,destination:URL,stopped:StoppedPlatformState)throws->JournalBackupReceipt {
        defer {withExtendedLifetime(stopped) {}}
        guard stopped.directory==directory.standardizedFileURL else {throw JournalError.invalid}
        guard directory.isFileURL,destination.isFileURL else {throw JournalError.invalid}
        func privateDirectory(_ url:URL)throws {
            var info=stat()
            guard lstat(url.path,&info)==0,(info.st_mode&S_IFMT)==S_IFDIR,info.st_uid==geteuid(),info.st_mode&0o077==0 else {throw JournalError.invalid}
        }
        try privateDirectory(directory);try privateDirectory(destination.deletingLastPathComponent())
        let file=directory.appendingPathComponent("state.sqlite").path
        let fd=open(file,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw JournalError.invalid};defer {close(fd)}
        var info=stat(),header=[UInt8](repeating:0,count:100)
        guard fstat(fd,&info)==0,(info.st_mode&S_IFMT)==S_IFREG,info.st_nlink==1,info.st_uid==geteuid(),info.st_mode&0o077==0,(100...(64<<20)).contains(info.st_size),pread(fd,&header,100,0)==100,
              Array(header.prefix(16))==Array("SQLite format 3\0".utf8),Array(header[68..<72])==[0x46,0x49,0x53,0x39] else {throw JournalError.invalid}
        for suffix in ["","-wal","-shm","-journal"] {
            var existing=stat()
            guard lstat(destination.path+suffix,&existing) != 0,errno==ENOENT else {throw JournalError.conflict}
        }
        let output=open(destination.path,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard output>=0 else {throw JournalError.storage};close(output)
        var success=false
        defer {if !success {for suffix in ["","-journal","-wal","-shm"] {_=unlink(destination.path+suffix)}}}
        var source:OpaquePointer?,target:OpaquePointer?
        defer {if let target {sqlite3_close(target)};if let source {sqlite3_close(source)}}
        guard sqlite3_open_v2(file,&source,SQLITE_OPEN_READONLY|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK,
              sqlite3_open_v2(destination.path,&target,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {throw JournalError.storage}
        func scalar(_ sql:String)throws->Int {
            var stmt:OpaquePointer?
            guard sqlite3_prepare_v2(source,sql,-1,&stmt,nil)==SQLITE_OK else {throw JournalError.storage}
            defer {sqlite3_finalize(stmt)}
            guard sqlite3_step(stmt)==SQLITE_ROW else {throw JournalError.storage}
            return Int(sqlite3_column_int64(stmt,0))
        }
        guard try scalar("PRAGMA application_id")==0x46495339,try scalar("PRAGMA user_version")==8 else {throw JournalError.invalid}
        let pages=try scalar("PRAGMA page_count"),pageSize=try scalar("PRAGMA page_size")
        guard pages>0,(512...65536).contains(pageSize),pages<=(64<<20)/pageSize else {throw JournalError.invalid}
        guard let operation=sqlite3_backup_init(target,"main",source,"main") else {throw JournalError.storage}
        var finalized=false
        defer {if !finalized {sqlite3_backup_finish(operation)}}
        let end=ProcessInfo.processInfo.systemUptime+10
        while true {
            guard ProcessInfo.processInfo.systemUptime<end else {throw JournalError.storage}
            let result=sqlite3_backup_step(operation,128)
            if result==SQLITE_DONE {break}
            guard result==SQLITE_OK else {throw JournalError.storage}
        }
        let result=sqlite3_backup_finish(operation);finalized=true
        guard result==SQLITE_OK,sqlite3_close(target)==SQLITE_OK else {throw JournalError.storage};target=nil
        let saved=open(destination.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard saved>=0 else {throw JournalError.storage};defer {close(saved)}
        var savedInfo=stat()
        guard fstat(saved,&savedInfo)==0,(100...(64<<20)).contains(savedInfo.st_size),fsync(saved)==0 else {throw JournalError.storage}
        let data=try Data(contentsOf:destination)
        guard data.count==savedInfo.st_size else {throw JournalError.storage}
        let parent=open(destination.deletingLastPathComponent().path,O_RDONLY|O_NOFOLLOW|O_DIRECTORY|O_CLOEXEC)
        guard parent>=0 else {throw JournalError.storage};defer {close(parent)}
        guard fsync(parent)==0 else {throw JournalError.storage}
        success=true
        return JournalBackupReceipt(schema:8,bytes:savedInfo.st_size,sha256:SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined())
    }
}
