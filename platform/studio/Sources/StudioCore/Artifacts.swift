import Foundation
import Darwin
import CryptoKit

enum ArtifactError: Error { case invalid, unauthorized, unavailable, capacity, storage }

// Single-manager, generated-path export store. No archive extraction, caller
// filenames, workload logging or automatic deletion outside this directory.
final class ArtifactStore {
    private enum State:String,Codable { case pending, ready, failed, deleting }
    private struct Record:Codable {
        let id:String; let job:String; let ownerHash:String; let created:Int64
        let bytes:Int; let sha256:String; var state:State
    }
    private struct Index:Codable { let version:Int; let records:[Record] }
    private let directory:URL
    private let availableBytes:()->UInt64?
    private var records:[Record]=[]
    private var lock:Int32 = -1
    private var previous:Int64 = -1
    var retainedBytes:Int64 { records.reduce(0,{$0+Int64($1.bytes)}) }
    var retainedJobs:Int { Set(records.map(\.job)).count }
    private static func uuid(_ value:String)->Bool { UUID(uuidString:value)?.uuidString.lowercased()==value }
    private static func digest(_ value:String)->Bool {
        value.utf8.count==64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func hash(_ data:Data)->String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }

    init(directory:URL,availableBytes:(()->UInt64?)?=nil) throws {
        guard directory.isFileURL else { throw ArtifactError.invalid }
        self.directory=directory
        self.availableBytes=availableBytes ?? {
            let attributes=try? FileManager.default.attributesOfFileSystem(forPath:directory.path)
            return (attributes?[.systemFreeSize] as? NSNumber)?.uint64Value
        }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var info=stat()
        guard lstat(directory.path,&info)==0,info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid==geteuid(),info.st_mode & 0o077==0 else { throw ArtifactError.invalid }
        lock=open(directory.appendingPathComponent("store.lock").path,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard lock>=0 else { throw ArtifactError.storage }
        do {
            guard fstat(lock,&info)==0,info.st_mode & S_IFMT == S_IFREG,info.st_uid==geteuid(),
                  info.st_mode & 0o077==0,info.st_nlink==1,flock(lock,LOCK_EX|LOCK_NB)==0 else { throw ArtifactError.invalid }
            let names=try FileManager.default.contentsOfDirectory(atPath:directory.path)
            if names.contains("index.json") {
                let data=try read("index.json",maximum:1<<20)
                try StrictJSON.validate(data,maximum:1<<20)
                guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(object.keys)==Set(["version","records"]),
                      let raw=object["records"] as? [[String:Any]],raw.allSatisfy({Set($0.keys)==Set(["id","job","ownerHash","created","bytes","sha256","state"])}) else {throw ArtifactError.invalid}
                let index=try JSONDecoder().decode(Index.self,from:data)
                guard index.version==1,index.records.count<=256 else { throw ArtifactError.invalid }
                records=index.records
            }
            var ids=Set<String>(),jobs:[String:(String,Int)]=[:]
            for record in records {
                guard Self.uuid(record.id),Self.uuid(record.job),Self.digest(record.ownerHash),Self.digest(record.sha256),
                      record.created>=0,record.created<=ActivityPolicy.maximumTimestamp-86_400_000,
                      (0...16<<20).contains(record.bytes),ids.insert(record.id).inserted else { throw ArtifactError.invalid }
                let existing=jobs[record.job] ?? (record.ownerHash,0)
                guard existing.0==record.ownerHash,existing.1+record.bytes<=16<<20 else { throw ArtifactError.invalid }
                jobs[record.job]=(record.ownerHash,existing.1+record.bytes)
                previous=max(previous,record.created)
            }
            let allowed=Set(records.map { $0.id+".blob" }).union(["store.lock","index.json"])
            guard names.allSatisfy({allowed.contains($0)}) else { throw ArtifactError.invalid }
            for index in records.indices where records[index].state == .pending {
                let record=records[index]
                if let data=try? read(record.id+".blob",maximum:record.bytes),data.count==record.bytes,Self.hash(data)==record.sha256 {
                    records[index].state = .ready
                } else { records[index].state = .failed }
            }
            try save()
            try finishDeletions()
        } catch {
            close(lock);lock = -1;throw error
        }
    }
    deinit { if lock>=0 { flock(lock,LOCK_UN);close(lock) } }

    private func check(now:Int64) throws {
        guard now>=previous,now>=0,now<=ActivityPolicy.maximumTimestamp-86_400_000 else { throw ArtifactError.invalid }
        previous=now
    }
    private func save() throws {
        let data=try JSONEncoder().encode(Index(version:1,records:records))
        guard data.count<=1<<20 else { throw ArtifactError.capacity }
        try AtomicState.write(data,to:directory.appendingPathComponent("index.json"))
    }
    private func read(_ name:String,maximum:Int) throws -> Data {
        let fd=open(directory.appendingPathComponent(name).path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else { throw ArtifactError.unavailable };defer { close(fd) }
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode & S_IFMT == S_IFREG,info.st_uid==geteuid(),
              info.st_mode & 0o077==0,info.st_nlink==1,info.st_size>=0,info.st_size<=maximum else { throw ArtifactError.invalid }
        var data=Data(),buffer=[UInt8](repeating:0,count:32_768)
        while true {
            let count=Darwin.read(fd,&buffer,min(buffer.count,maximum-data.count+1))
            if count<0 && errno==EINTR { continue }
            guard count>=0 else { throw ArtifactError.storage }
            if count==0 { return data }
            guard count<=maximum-data.count else { throw ArtifactError.invalid }
            data.append(contentsOf:buffer.prefix(count))
        }
    }
    func publish(job:String,ownerHash:String,data:Data,now:Int64) throws -> String {
        try check(now:now)
        guard Self.uuid(job),Self.digest(ownerHash) else { throw ArtifactError.invalid }
        guard records.count<256,data.count<=16<<20,
              records.filter({$0.job==job}).reduce(0,{$0+$1.bytes})+data.count<=16<<20,
              records.reduce(Int64(0),{$0+Int64($1.bytes)})+Int64(data.count)<=4<<30 else { throw ArtifactError.capacity }
        guard records.filter({$0.job==job}).allSatisfy({$0.ownerHash==ownerHash}) else { throw ArtifactError.unauthorized }
        let commitments=records.filter({$0.state == .pending || $0.state == .failed}).reduce(UInt64(0),{$0+UInt64($1.bytes)})
        guard let available=availableBytes(),available>=(UInt64(10)<<30)+commitments+UInt64(data.count) else { throw ArtifactError.capacity }
        let id=UUID().uuidString.lowercased()
        records.append(Record(id:id,job:job,ownerHash:ownerHash,created:now,bytes:data.count,sha256:Self.hash(data),state:.pending))
        // Persist reservation/identity before writing bytes. A failed or lost
        // publication retains its quota and never silently retries delivery.
        try save()
        let fd=open(directory.appendingPathComponent(id+".blob").path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else { throw ArtifactError.storage };defer { close(fd) }
        var offset=0
        while offset<data.count {
            let count=data.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!.advanced(by:offset),data.count-offset) }
            if count<0 && errno==EINTR { continue }
            guard count>0 else { throw ArtifactError.storage };offset+=count
        }
        guard fsync(fd)==0 else { throw ArtifactError.storage }
        records[records.count-1].state = .ready
        try save()
        return id
    }
    func retrieve(id:String,ownerHash:String,now:Int64) throws -> Data {
        try check(now:now)
        guard Self.uuid(id),Self.digest(ownerHash) else { throw ArtifactError.invalid }
        guard let record=records.first(where:{$0.id==id}),record.state == .ready,
              now<record.created+86_400_000 else { throw ArtifactError.unavailable }
        guard record.ownerHash==ownerHash else { throw ArtifactError.unauthorized }
        let data=try read(record.id+".blob",maximum:record.bytes)
        guard data.count==record.bytes,Self.hash(data)==record.sha256 else { throw ArtifactError.invalid }
        return data
    }
    func download(id:String,ownerHash:String,now:Int64) throws -> ArtifactDownload {
        let data=try retrieve(id:id,ownerHash:ownerHash,now:now)
        guard let record=records.first(where:{$0.id==id}) else { throw ArtifactError.unavailable }
        return try ArtifactDownload(id:id,data:data,created:now,expires:record.created+86_400_000)
    }
    private func finishDeletions() throws {
        for record in records where record.state == .deleting {
            let path=directory.appendingPathComponent(record.id+".blob").path
            var info=stat()
            if lstat(path,&info)==0 {
                guard info.st_mode & S_IFMT == S_IFREG,info.st_uid==geteuid(),info.st_nlink==1,
                      info.st_mode & 0o077==0,unlink(path)==0 else { throw ArtifactError.invalid }
            } else if errno != ENOENT { throw ArtifactError.storage }
        }
        records.removeAll(where:{$0.state == .deleting})
        try save()
    }
    func expire(now:Int64) throws {
        try check(now:now)
        let expired=records.indices.filter { now>=records[$0].created+86_400_000 }
        guard !expired.isEmpty || records.contains(where:{$0.state == .deleting}) else { return }
        for index in expired { records[index].state = .deleting }
        try save();try finishDeletions()
    }
}
