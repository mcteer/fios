import Foundation
import Darwin
import CryptoKit

struct ArtifactBackupFile:Codable {let path:String;let bytes:Int64;let sha256:String}
struct ArtifactBackupReceipt {let artifacts:Int;let bytes:Int64;let indexSHA256:String;let files:[ArtifactBackupFile]}

// Offline operator primitive only. No task/control route and no source
// mutation/recovery/expiry: preserve pending/failed records as recorded.
enum StoppedArtifactBackup {
    private struct Record:Decodable {let id:String;let job:String;let ownerHash:String;let created:Int64;let bytes:Int;let sha256:String;let state:String}
    private struct Index:Decodable {let version:Int;let records:[Record]}
    static func create(directory:URL,destination:URL,stopped:StoppedPlatformState?=nil)throws->ArtifactBackupReceipt {
        let proof=try stopped ?? StoppedPlatformState(directory:directory)
        defer {withExtendedLifetime(proof) {}}
        guard proof.directory==directory.standardizedFileURL else {throw JournalError.invalid}
        func privateDirectory(_ url:URL)throws {
            var value=stat()
            guard lstat(url.path,&value)==0,value.st_mode&S_IFMT==S_IFDIR,value.st_uid==geteuid(),value.st_mode&0o077==0 else {throw JournalError.invalid}
        }
        func openPrivate(_ url:URL,maximum:Int64)throws->(Int32,Int64) {
            let fd=open(url.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw JournalError.invalid}
            var value=stat()
            guard fstat(fd,&value)==0,value.st_mode&S_IFMT==S_IFREG,value.st_nlink==1,value.st_uid==geteuid(),value.st_mode&0o077==0,value.st_size>=0,value.st_size<=maximum else {close(fd);throw JournalError.invalid}
            return (fd,value.st_size)
        }
        func readMetadata(_ url:URL,maximum:Int64)throws->Data {
            let (fd,length)=try openPrivate(url,maximum:maximum);defer {close(fd)}
            var data=Data(),buffer=[UInt8](repeating:0,count:32768)
            while true {
                let count=Darwin.read(fd,&buffer,buffer.count)
                if count<0 && errno==EINTR {continue}
                guard count>=0,Int64(data.count+max(0,count))<=maximum else {throw JournalError.invalid}
                if count==0 {break};data.append(contentsOf:buffer.prefix(count))
            }
            guard data.count==length else {throw JournalError.invalid};return data
        }
        func lockFile(_ url:URL)throws->Int32 {
            let (fd,_)=try openPrivate(url,maximum:4096)
            guard flock(fd,LOCK_EX|LOCK_NB)==0 else {close(fd);throw JournalError.locked};return fd
        }
        guard directory.isFileURL,destination.isFileURL else {throw JournalError.invalid}
        try privateDirectory(directory);try privateDirectory(destination.deletingLastPathComponent())
        let source=directory.appendingPathComponent("artifacts")
        let protected=source.resolvingSymlinksInPath().standardizedFileURL.path
        let target=destination.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent).standardizedFileURL.path
        guard target != protected,!target.hasPrefix(protected+"/") else {throw JournalError.invalid}
        let (database,_)=try openPrivate(directory.appendingPathComponent("state.sqlite"),maximum:64<<20)
        var header=[UInt8](repeating:0,count:100)
        let headerRead=pread(database,&header,100,0);close(database)
        guard headerRead==100,Array(header.prefix(16))==Array("SQLite format 3\0".utf8),Array(header[68..<72])==[0x46,0x49,0x53,0x39] else {throw JournalError.invalid}
        try privateDirectory(source)
        let store=try lockFile(source.appendingPathComponent("store.lock"));defer {flock(store,LOCK_UN);close(store)}
        let metadata:Data
        var indexInfo=stat()
        if lstat(source.appendingPathComponent("index.json").path,&indexInfo)==0 {
            metadata=try readMetadata(source.appendingPathComponent("index.json"),maximum:1<<20)
        } else {
            guard errno==ENOENT else {throw JournalError.invalid}
            metadata=Data("{\"version\":1,\"records\":[]}".utf8)
        }
        try StrictJSON.validate(metadata,maximum:1<<20)
        guard let object=try JSONSerialization.jsonObject(with:metadata) as? [String:Any],Set(object.keys)==Set(["version","records"]),
              let raw=object["records"] as? [[String:Any]],raw.allSatisfy({Set($0.keys)==Set(["id","job","ownerHash","created","bytes","sha256","state"])}) else {throw JournalError.invalid}
        let index=try JSONDecoder().decode(Index.self,from:metadata)
        guard index.version==1,index.records.count<=256 else {throw JournalError.invalid}
        func uuid(_ value:String)->Bool {UUID(uuidString:value)?.uuidString.lowercased()==value}
        func digest(_ value:String)->Bool {value.utf8.count==64 && value.utf8.allSatisfy {(48...57).contains($0)||(97...102).contains($0)}}
        var ids=Set<String>(),total:Int64=0,files:[(Record,Int64)]=[],jobs:[String:(String,Int)]=[:]
        for record in index.records {
            guard uuid(record.id),uuid(record.job),digest(record.ownerHash),digest(record.sha256),record.created>=0,record.created<=ActivityPolicy.maximumTimestamp-86400000,(0...16<<20).contains(record.bytes),["pending","ready","failed","deleting"].contains(record.state),ids.insert(record.id).inserted else {throw JournalError.invalid}
            let previous=jobs[record.job] ?? (record.ownerHash,0)
            guard previous.0==record.ownerHash,previous.1+record.bytes<=16<<20 else {throw JournalError.invalid}
            jobs[record.job]=(record.ownerHash,previous.1+record.bytes)
            let path=source.appendingPathComponent(record.id+".blob")
            var value=stat()
            if lstat(path.path,&value) != 0 {
                guard errno==ENOENT,record.state != "ready" else {throw JournalError.invalid};continue
            }
            let (fd,length)=try openPrivate(path,maximum:16<<20);close(fd)
            total+=length;guard total<=4<<30 else {throw JournalError.invalid};files.append((record,length))
        }
        let allowed=ids.map {$0+".blob"}+["index.json","store.lock"]
        guard try FileManager.default.contentsOfDirectory(atPath:source.path).allSatisfy({allowed.contains($0)}) else {throw JournalError.invalid}
        let disk=try FileManager.default.attributesOfFileSystem(forPath:destination.deletingLastPathComponent().path)
        guard let free=(disk[.systemFreeSize] as? NSNumber)?.int64Value,free>=total+(10<<30) else {throw JournalError.storage}
        guard mkdir(destination.path,0o700)==0 else {throw JournalError.conflict}
        var success=false;defer {if !success {try? FileManager.default.removeItem(at:destination)}}
        let end=ProcessInfo.processInfo.systemUptime+30
        var copiedFiles:[ArtifactBackupFile]=[]
        for (record,length) in files {
            let name=record.id+".blob",(input,_)=try openPrivate(source.appendingPathComponent(name),maximum:16<<20)
            defer {close(input)}
            let output=open(destination.appendingPathComponent(name).path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            guard output>=0 else {throw JournalError.storage};defer {close(output)}
            var hash=SHA256(),copied:Int64=0,buffer=[UInt8](repeating:0,count:65536)
            while true {
                guard ProcessInfo.processInfo.systemUptime<end else {throw RuntimeError.deadline}
                let count=Darwin.read(input,&buffer,buffer.count)
                if count<0 && errno==EINTR {continue}
                guard count>=0,copied+Int64(max(0,count))<=length else {throw JournalError.invalid}
                if count==0 {break}
                let data=Data(buffer.prefix(count));hash.update(data:data)
                var position=0
                while position<count {
                    let written=data.withUnsafeBytes {Darwin.write(output,$0.baseAddress!.advanced(by:position),count-position)}
                    if written<0 && errno==EINTR {continue}
                    guard written>0 else {throw JournalError.storage};position+=written
                }
                copied+=Int64(count)
            }
            guard copied==length,fsync(output)==0 else {throw JournalError.storage}
            let digest=hash.finalize().map {String(format:"%02x",$0)}.joined()
            if record.state=="ready" {guard copied==record.bytes,digest==record.sha256 else {throw JournalError.invalid}}
            copiedFiles.append(ArtifactBackupFile(path:name,bytes:copied,sha256:digest))
        }
        try metadata.write(to:destination.appendingPathComponent("index.json"),options:.withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.appendingPathComponent("index.json").path)
        let (indexFD,_)=try openPrivate(destination.appendingPathComponent("index.json"),maximum:1<<20);defer {close(indexFD)}
        let parent=open(destination.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard parent>=0 else {throw JournalError.storage};defer {close(parent)}
        guard fsync(indexFD)==0,fsync(parent)==0 else {throw JournalError.storage}
        success=true
        return ArtifactBackupReceipt(artifacts:files.count,bytes:total,indexSHA256:SHA256.hash(data:metadata).map {String(format:"%02x",$0)}.joined(),files:copiedFiles.sorted {$0.path<$1.path})
    }
}
