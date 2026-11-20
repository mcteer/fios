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
        let fd=open(file,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard fd>=0 else {throw JournalError.invalid};defer {close(fd)}
        var info=stat(),header=[UInt8](repeating:0,count:100)
        guard fstat(fd,&info)==0,stopped.matchesDatabase(info),(info.st_mode&S_IFMT)==S_IFREG,info.st_nlink==1,info.st_uid==geteuid(),info.st_mode&0o077==0,(100...(64<<20)).contains(info.st_size),pread(fd,&header,100,0)==100,
              Array(header.prefix(16))==Array("SQLite format 3\0".utf8),Array(header[68..<72])==[0x46,0x49,0x53,0x39] else {throw JournalError.invalid}
        for suffix in ["","-wal","-shm","-journal"] {
            var existing=stat()
            guard lstat(destination.path+suffix,&existing) != 0,errno==ENOENT else {throw JournalError.conflict}
        }
        let output=open(destination.path,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard output>=0 else {throw JournalError.storage}
        defer {close(output)}
        var created=stat()
        guard fstat(output,&created)==0 else {throw JournalError.storage}
        // Retain failed output/SQLite sidecars for diagnosis. No receipt is
        // returned and no pathname cleanup assumes their current ownership.
        // A restored WAL-mode main file may lack SHM/WAL initialization.
        // Recover only a bounded private snapshot; never open the original
        // with a writable SQLite connection or mutate it to enable backup.
        let snapshot=try JournalSchemaSnapshot(source:directory,stopped:stopped)
        var source:OpaquePointer?,target:OpaquePointer?
        defer {
            if let target {sqlite3_close(target)}
            if let source {sqlite3_close(source)}
            withExtendedLifetime(snapshot) {}
        }
        var targetName=stat()
        guard lstat(destination.path,&targetName)==0,targetName.st_dev==created.st_dev,targetName.st_ino==created.st_ino,
              targetName.st_nlink==1,targetName.st_size==0 else {throw JournalError.storage}
        guard sqlite3_open_v2(snapshot.directory.appendingPathComponent("state.sqlite").path,&source,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK,
              sqlite3_open_v2(destination.path,&target,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {throw JournalError.storage}
        func scalar(_ sql:String)throws->Int {
            var stmt:OpaquePointer?
            guard sqlite3_prepare_v2(source,sql,-1,&stmt,nil)==SQLITE_OK else {throw JournalError.storage}
            defer {sqlite3_finalize(stmt)}
            guard sqlite3_step(stmt)==SQLITE_ROW else {throw JournalError.storage}
            return Int(sqlite3_column_int64(stmt,0))
        }
        guard try scalar("PRAGMA application_id")==0x46495339,try scalar("PRAGMA user_version")==9 else {throw JournalError.invalid}
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
        let saved=open(destination.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard saved>=0 else {throw JournalError.storage};defer {close(saved)}
        var savedInfo=stat()
        guard fstat(saved,&savedInfo)==0,savedInfo.st_dev==created.st_dev,savedInfo.st_ino==created.st_ino,
              savedInfo.st_mode&S_IFMT==S_IFREG,savedInfo.st_nlink==1,
              savedInfo.st_uid==geteuid(),savedInfo.st_mode&0o077==0,(100...(64<<20)).contains(savedInfo.st_size),
              fsync(saved)==0 else {throw JournalError.storage}
        var digest=SHA256(),buffer=[UInt8](repeating:0,count:65536),total:Int64=0
        let hashDeadline=ProcessInfo.processInfo.systemUptime+10
        while total<savedInfo.st_size {
            guard ProcessInfo.processInfo.systemUptime<hashDeadline else {throw RuntimeError.deadline}
            let count=Darwin.read(saved,&buffer,min(buffer.count,Int(savedInfo.st_size-total)))
            if count<0 && errno==EINTR {continue}
            guard count>0 else {throw JournalError.storage}
            total+=Int64(count);digest.update(data:Data(buffer.prefix(count)))
        }
        var named=stat()
        guard lstat(destination.path,&named)==0,named.st_dev==savedInfo.st_dev,named.st_ino==savedInfo.st_ino,
              named.st_size==savedInfo.st_size,named.st_uid==savedInfo.st_uid,named.st_mode==savedInfo.st_mode,named.st_nlink==1,
              named.st_mtimespec.tv_sec==savedInfo.st_mtimespec.tv_sec,named.st_mtimespec.tv_nsec==savedInfo.st_mtimespec.tv_nsec,
              named.st_ctimespec.tv_sec==savedInfo.st_ctimespec.tv_sec,named.st_ctimespec.tv_nsec==savedInfo.st_ctimespec.tv_nsec else {throw JournalError.storage}
        let parent=open(destination.deletingLastPathComponent().path,O_RDONLY|O_NOFOLLOW|O_DIRECTORY|O_CLOEXEC)
        guard parent>=0 else {throw JournalError.storage};defer {close(parent)}
        guard fsync(parent)==0 else {throw JournalError.storage}
        return JournalBackupReceipt(schema:9,bytes:savedInfo.st_size,sha256:digest.finalize().map {String(format:"%02x",$0)}.joined())
    }
}
