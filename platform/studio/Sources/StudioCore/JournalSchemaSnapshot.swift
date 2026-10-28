import Foundation
import Darwin

// Existing state is inspected in a private bounded copy. A read-only SQLite
// connection may still need WAL initialization/recovery and can fail on valid
// restored WAL-mode main files. Never let that preflight repair the original.
final class JournalSchemaSnapshot {
    let directory:URL
    init(source:URL)throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-schema-"+UUID().uuidString.lowercased())
        guard mkdir(directory.path,0o700)==0 else {throw JournalError.storage}
        var completed=false
        defer {if !completed {try? FileManager.default.removeItem(at:directory)}}
        let deadline=ProcessInfo.processInfo.systemUptime+10
        for suffix in ["","-wal","-journal","-shm"] {
            let original=source.appendingPathComponent("state.sqlite"+suffix)
            let input=open(original.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
            if input<0,errno==ENOENT,suffix != "" {continue}
            guard input>=0 else {throw JournalError.invalid}
            defer {close(input)}
            var before=stat(),after=stat(),named=stat()
            guard fstat(input,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_nlink==1,
                  before.st_uid==geteuid(),before.st_mode&0o7777==0o600,before.st_size>=0,before.st_size<=64<<20 else {throw JournalError.invalid}
            // Reconstruct SHM in private state; never copy stale reader locks.
            if suffix=="-shm" {continue}
            let output=open(directory.appendingPathComponent("state.sqlite"+suffix).path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            guard output>=0 else {throw JournalError.storage}
            defer {close(output)}
            var bytes=[UInt8](repeating:0,count:32768),total:Int64=0
            while true {
                guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
                let count=Darwin.read(input,&bytes,bytes.count)
                if count<0,errno==EINTR {continue}
                guard count>=0 else {throw JournalError.storage}
                if count==0 {break}
                total+=Int64(count);guard total<=before.st_size else {throw JournalError.invalid}
                var offset=0
                while offset<count {
                    guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
                    let written=bytes.withUnsafeBytes {Darwin.write(output,$0.baseAddress!.advanced(by:offset),count-offset)}
                    if written<0,errno==EINTR {continue}
                    guard written>0 else {throw JournalError.storage};offset+=written
                }
            }
            guard total==before.st_size,fstat(input,&after)==0,lstat(original.path,&named)==0,
                  before.st_dev==after.st_dev,before.st_ino==after.st_ino,before.st_size==after.st_size,
                  before.st_mode==after.st_mode,before.st_uid==after.st_uid,after.st_nlink==1,
                  before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
                  before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
                  named.st_dev==after.st_dev,named.st_ino==after.st_ino,named.st_mode==after.st_mode,named.st_nlink==1,
                  named.st_uid==after.st_uid,named.st_size==after.st_size,
                  named.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,named.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
                  named.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,named.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec else {throw JournalError.invalid}
        }
        completed=true
    }
    deinit {try? FileManager.default.removeItem(at:directory)}
}
