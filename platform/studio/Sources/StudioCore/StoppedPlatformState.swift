import Foundation
import Darwin
import CryptoKit

// Unforgeable-in-protocol lexical ownership of the platform's writer lock.
// Hold one across journal + export snapshots so no manager can interleave.
final class StoppedPlatformState {
    static func hostHash()throws->String {
        var identifier:uuid_t=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        var timeout=timespec(tv_sec:1,tv_nsec:0)
        guard gethostuuid(&identifier,&timeout)==0 else {throw JournalError.invalid}
        let data=withUnsafeBytes(of:identifier) {Data($0)}
        guard data.contains(where:{$0 != 0}) else {throw JournalError.invalid}
        return SHA256.hash(data:Data("fios009-backup-host-v1\0".utf8)+data).map {String(format:"%02x",$0)}.joined()
    }
    let directory:URL
    private let fd:Int32
    private let supervisorFD:Int32
    init(directory:URL)throws {
        guard directory.isFileURL else {throw JournalError.invalid}
        self.directory=directory.standardizedFileURL
        var value=stat()
        guard lstat(directory.path,&value)==0,value.st_mode&S_IFMT==S_IFDIR,value.st_uid==geteuid(),value.st_mode&0o077==0 else {throw JournalError.invalid}
        let database=open(directory.appendingPathComponent("state.sqlite").path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard database>=0 else {throw JournalError.invalid};defer {close(database)}
        var header=[UInt8](repeating:0,count:100)
        guard fstat(database,&value)==0,value.st_mode&S_IFMT==S_IFREG,value.st_nlink==1,value.st_uid==geteuid(),value.st_mode&0o077==0,value.st_size>=100,value.st_size<=64<<20,pread(database,&header,100,0)==100,
              Array(header.prefix(16))==Array("SQLite format 3\0".utf8),Array(header[68..<72])==[0x46,0x49,0x53,0x39] else {throw JournalError.invalid}
        // Fence the watchdog too: a stopped manager alone is insufficient
        // while its supervisor can respawn it. Fixed lock order, nonblocking.
        let supervisor=open(directory.appendingPathComponent("supervisor.lock").path,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard supervisor>=0 else {throw JournalError.invalid}
        var retained=false
        defer {if !retained {flock(supervisor,LOCK_UN);close(supervisor)}}
        guard fstat(supervisor,&value)==0,value.st_mode&S_IFMT==S_IFREG,value.st_nlink==1,value.st_uid==geteuid(),value.st_mode&0o077==0 else {throw JournalError.invalid}
        guard flock(supervisor,LOCK_EX|LOCK_NB)==0 else {throw JournalError.locked}
        let lock=open(directory.appendingPathComponent("manager.lock").path,O_RDWR|O_NOFOLLOW|O_CLOEXEC)
        guard lock>=0 else {throw JournalError.invalid}
        guard fstat(lock,&value)==0,value.st_mode&S_IFMT==S_IFREG,value.st_nlink==1,value.st_uid==geteuid(),value.st_mode&0o077==0 else {close(lock);throw JournalError.invalid}
        guard flock(lock,LOCK_EX|LOCK_NB)==0 else {close(lock);throw JournalError.locked}
        fd=lock;supervisorFD=supervisor;retained=true
    }
    deinit {flock(fd,LOCK_UN);close(fd);flock(supervisorFD,LOCK_UN);close(supervisorFD)}
}
