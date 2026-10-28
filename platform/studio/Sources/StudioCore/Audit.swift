import Foundation
import Darwin

enum AuditError: Error { case invalid, storage }
enum AuditEvent: String, Codable { case started, stopped, desiredChanged, rejected, revoked, reconciled }

// Serialized-manager writer. No API accepts free text, payloads or CLI output.
final class AuditLog {
    private let directory:URL
    private let maximumBytes:Int
    private var previous:Int64 = -1
    private struct Entry:Encodable { let version=1;let event:AuditEvent;let time:Int64;let job:String?;let count:Int? }
    init(directory:URL,maximumBytes:Int=10<<20) throws {
        guard directory.isFileURL,(256...10<<20).contains(maximumBytes) else { throw AuditError.invalid }
        self.directory=directory;self.maximumBytes=maximumBytes
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var info=stat()
        guard lstat(directory.path,&info)==0,info.st_mode & S_IFMT == S_IFDIR,info.st_uid==geteuid(),info.st_mode & 0o077==0 else { throw AuditError.invalid }
    }
    func record(_ event:AuditEvent,now:Int64,job:String?=nil,count:Int?=nil) throws {
        guard now>=previous,now>=0,now<=ActivityPolicy.maximumTimestamp,
              job==nil || UUID(uuidString:job!)?.uuidString.lowercased()==job,
              count==nil || (0...1_000_000).contains(count!) else { throw AuditError.invalid }
        let day=now/86_400_000
        let files=try FileManager.default.contentsOfDirectory(atPath:directory.path)
        var owned:[(Int64,String,Int)]=[]
        for name in files {
            guard name.hasPrefix("audit-"),name.hasSuffix(".jsonl"),
                  let value=Int64(name.dropFirst(6).dropLast(6)),value>=0,
                  name=="audit-\(value).jsonl" else { throw AuditError.invalid }
            let path=directory.appendingPathComponent(name).path
            var info=stat()
            guard lstat(path,&info)==0,info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid==geteuid(),info.st_mode & 0o077==0,info.st_size>=0,
                  value<=day else { throw AuditError.invalid }
            if value<=day-7 { guard unlink(path)==0 else { throw AuditError.storage } }
            else { owned.append((value,path,Int(info.st_size))) }
        }
        var data=try JSONEncoder().encode(Entry(event:event,time:now,job:job,count:count));data.append(10)
        guard data.count<=maximumBytes else { throw AuditError.invalid }
        var bytes=owned.reduce(0){$0+$1.2}
        for file in owned.sorted(by:{$0.0<$1.0}) where bytes+data.count>maximumBytes {
            guard unlink(file.1)==0 else { throw AuditError.storage };bytes-=file.2
        }
        let path=directory.appendingPathComponent("audit-\(day).jsonl").path
        let fd=open(path,O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else { throw AuditError.storage };defer { close(fd) }
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode & S_IFMT == S_IFREG,
              info.st_uid==geteuid(),info.st_mode & 0o077==0 else { throw AuditError.invalid }
        try data.withUnsafeBytes { bytes in
            var offset=0
            while offset<bytes.count {
                let result=write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                if result<0 && errno==EINTR { continue }
                guard result>0 else { throw AuditError.storage };offset+=result
            }
        }
        previous=now
    }
}
