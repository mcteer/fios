import Foundation
import Darwin
import CryptoKit

// Data preservation only. These opaque documents may be incomplete/invalid;
// neither capture nor private restoration enrolls a runtime or installs policy.
struct ConfigurationBackup {
    static let names=["runtime-enrollment.json","session-enrollment.json","python-enrollment.json","resource-enrollment.json","native-serving-launch.json","sandbox-enrollment.json"]
    struct File:Codable,Equatable {
        let name:String
        let bytes:Int?
        let sha256:String?
        let originalUID:UInt32?
        var originalGID:UInt32? = nil
        let originalMode:UInt16?
    }
    struct Manifest:Codable {let version:Int;let scope:String;let files:[File]}
    let files:[File]
    let payloads:[String:Data]
    let identities:[String:stat]
    let directoryIdentity:stat
    static func digest(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
    static func noACL(_ fd:Int32)->Bool {
        if let acl=acl_get_fd_np(fd,ACL_TYPE_EXTENDED) {acl_free(UnsafeMutableRawPointer(acl));return false}
        return errno==ENOENT
    }
    static func stable(_ a:stat,_ b:stat)->Bool {
        a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_uid==b.st_uid && a.st_gid==b.st_gid && a.st_mode==b.st_mode && a.st_nlink==b.st_nlink && a.st_size==b.st_size &&
        a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
    }
    static func capture(directory:URL,uptime:()->TimeInterval={ProcessInfo.processInfo.systemUptime})throws->ConfigurationBackup {
        let began=uptime()
        var previous=began
        func checkClock()throws {
            let now=uptime()
            guard began.isFinite,began>=0,now.isFinite,now>=previous,now-began<2 else {throw RuntimeError.deadline}
            previous=now
        }
        guard directory.isFileURL else {throw JournalError.invalid}
        let parent=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard parent>=0 else {throw JournalError.invalid};defer {close(parent)}
        var initial=stat(),final=stat(),namedParent=stat()
        guard fstat(parent,&initial)==0,[0,geteuid()].contains(initial.st_uid),initial.st_mode&0o7022==0,noACL(parent) else {throw JournalError.invalid}
        var files=[File](),payloads=[String:Data]()
        var identities:[String:stat]=[:]
        for name in names {
            try checkClock()
            let fd=openat(parent,name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
            if fd<0,errno==ENOENT {files.append(File(name:name,bytes:nil,sha256:nil,originalUID:nil,originalMode:nil));continue}
            guard fd>=0 else {throw JournalError.invalid};defer {close(fd)}
            var before=stat(),after=stat(),named=stat()
            guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,[0,geteuid()].contains(before.st_uid),before.st_mode&0o7022==0,before.st_nlink==1,(0...65536).contains(before.st_size),noACL(fd) else {throw JournalError.invalid}
            var data=Data(),buffer=[UInt8](repeating:0,count:4096)
            while true {
                try checkClock()
                let count=Darwin.read(fd,&buffer,min(buffer.count,65537-data.count))
                if count<0,errno==EINTR {continue}
                guard count>=0,data.count+count<=65536 else {throw JournalError.invalid}
                if count==0 {break};data.append(contentsOf:buffer.prefix(count))
            }
            guard data.count==before.st_size,fstat(fd,&after)==0,fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW)==0,stable(before,after),stable(after,named),noACL(fd) else {throw JournalError.invalid}
            files.append(File(name:name,bytes:data.count,sha256:digest(data),originalUID:before.st_uid,originalGID:before.st_gid,originalMode:before.st_mode&0o7777));payloads[name]=data;identities[name]=after
        }
        guard fstat(parent,&final)==0,stable(initial,final),lstat(directory.path,&namedParent)==0,stable(final,namedParent),noACL(parent) else {throw JournalError.invalid}
        try checkClock()
        return ConfigurationBackup(files:files,payloads:payloads,identities:identities,directoryIdentity:final)
    }
    func recheck(directory:URL)throws {
        let current=try Self.capture(directory:directory)
        guard current.files==files,current.payloads==payloads,Self.stable(directoryIdentity,current.directoryIdentity),identities.allSatisfy({name,info in current.identities[name].map {Self.stable(info,$0)} ?? false}) else {throw JournalError.conflict}
    }
    func write(directory:URL)throws->(sha256:String,bytes:Int64) {
        guard mkdir(directory.path,0o700)==0 else {throw JournalError.conflict}
        for (name,data) in payloads {try AtomicState.write(data,to:directory.appendingPathComponent(name))}
        let data=try JSONEncoder().encode(Manifest(version:2,scope:"opaque_configuration_data_only",files:files))
        try AtomicState.write(data,to:directory.appendingPathComponent("manifest.json"))
        let fd=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw JournalError.storage};defer {close(fd)}
        guard fsync(fd)==0 else {throw JournalError.storage}
        return (Self.digest(data),Int64(data.count+payloads.values.reduce(0){$0+$1.count}))
    }
    static func verify(directory:URL,expected:String)throws->Int64 {
        let fd=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw JournalError.invalid};defer {close(fd)}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_uid==geteuid(),info.st_mode&0o7777==0o700,noACL(fd) else {throw JournalError.invalid}
        // Fixed bounded files; reuse the same stable/no-follow reader. The
        // manifest is read separately because it is not an enrollment document.
        let manifestFD=openat(fd,"manifest.json",O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        guard manifestFD>=0 else {throw JournalError.invalid};defer {close(manifestFD)}
        guard fstat(manifestFD,&info)==0,info.st_mode&S_IFMT==S_IFREG,info.st_uid==geteuid(),info.st_nlink==1,info.st_mode&0o7777==0o600,(1...65536).contains(info.st_size),noACL(manifestFD) else {throw JournalError.invalid}
        var buffer=[UInt8](repeating:0,count:65537),offset=0
        while offset<buffer.count {
            let n=buffer.withUnsafeMutableBytes {Darwin.read(manifestFD,$0.baseAddress!.advanced(by:offset),$0.count-offset)}
            if n<0,errno==EINTR {continue};guard n>=0 else {throw JournalError.invalid};if n==0 {break};offset+=n
        }
        let data=Data(buffer.prefix(offset))
        var after=stat(),named=stat()
        guard fstat(manifestFD,&after)==0,fstatat(fd,"manifest.json",&named,AT_SYMLINK_NOFOLLOW)==0,stable(info,after),stable(after,named),noACL(manifestFD),offset==info.st_size,digest(data)==expected else {throw JournalError.invalid}
        try StrictJSON.validate(data,maximum:65536)
        guard let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(raw.keys)==Set(["version","scope","files"]),
              let rows=raw["files"] as? [[String:Any]],rows.count==names.count else {throw JournalError.invalid}
        let manifest=try JSONDecoder().decode(Manifest.self,from:data)
        guard [1,2].contains(manifest.version),manifest.scope=="opaque_configuration_data_only",manifest.files.map(\.name)==names else {throw JournalError.invalid}
        let presentKeys:Set<String>=Set(["name","bytes","sha256","originalUID","originalMode"]+(manifest.version==2 ? ["originalGID"]:[]))
        guard rows.allSatisfy({Set($0.keys)==Set(["name"]) || Set($0.keys)==presentKeys}) else {throw JournalError.invalid}
        let snapshot=try capture(directory:directory)
        var present=Set(["manifest.json"]),total=Int64(data.count)
        for (declared,actual) in zip(manifest.files,snapshot.files) {
            guard declared.bytes==actual.bytes,declared.sha256==actual.sha256 else {throw JournalError.invalid}
            if let bytes=declared.bytes {
                guard (0...65536).contains(bytes),let uid=declared.originalUID,[0,geteuid()].contains(uid),let mode=declared.originalMode,mode&0o7022==0,actual.originalUID==geteuid(),actual.originalMode==0o600 else {throw JournalError.invalid}
                if manifest.version==2 {guard declared.originalGID != nil else {throw JournalError.invalid}}
                else {guard declared.originalGID==nil else {throw JournalError.invalid}}
                present.insert(declared.name);total+=Int64(bytes)
            } else {guard declared.originalUID==nil,declared.originalGID==nil,declared.originalMode==nil,declared.sha256==nil else {throw JournalError.invalid}}
        }
        guard Set(try FileManager.default.contentsOfDirectory(atPath:directory.path))==present else {throw JournalError.invalid}
        return total
    }
}
