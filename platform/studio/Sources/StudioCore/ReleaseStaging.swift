import Foundation
import Darwin
import CryptoKit

public enum PlatformReleaseStagingError:Error {case invalid,retained(String),publicationUncertain}
public struct PlatformReleaseStageReceipt {
    public let manifestSHA256:String
    public let artifacts:Int
    public let bytes:Int64
}

// Data-only staging of the fixed development artifact surface. Expected
// receipt hashes come from independent review; nothing here enrolls a release,
// executes its bytes, installs configuration, opens a journal or starts work.
public enum PlatformReleaseStaging {
    private static let modes:[String:Int] = ["bin/studio-manager":0o755,"bin/studio-supervisor":0o755,"bin/studio-session":0o755,"bin/studioctl":0o755,
        "sandbox/runner.py":0o644,"sandbox/Dockerfile":0o644,"python/uv.lock":0o644,
        "launchd/lab.fios.studio.supervisor.plist":0o644,"launchd/lab.fios.studio.session.plist":0o644]
    private struct Artifact {let path:String;let hash:String;let bytes:Int64;let mode:Int}
    private static func fail()throws->Never {throw PlatformReleaseStagingError.invalid}
    private static func hash(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
    private static func canonical(_ path:String)throws->String {
        guard let resolved=realpath(path,nil) else {try fail()};defer {free(resolved)}
        return String(cString:resolved)
    }
    private static func namedDirectory(_ fd:Int32,path:String)throws {
        var held=stat(),named=stat()
        guard fstat(fd,&held)==0,lstat(path,&named)==0,held.st_dev==named.st_dev,held.st_ino==named.st_ino,
              named.st_mode&S_IFMT==S_IFDIR,held.st_uid==named.st_uid,held.st_mode==named.st_mode else {try fail()}
    }
    private static func same(_ a:stat,_ b:stat)->Bool {
        a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_uid==b.st_uid && a.st_gid==b.st_gid && a.st_mode==b.st_mode && a.st_nlink==b.st_nlink && a.st_size==b.st_size &&
        a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
    }
    private static func noACL(_ fd:Int32)->Bool {
        errno=0
        if let acl=acl_get_fd_np(fd,ACL_TYPE_EXTENDED) {acl_free(UnsafeMutableRawPointer(acl));return false}
        return errno==ENOENT
    }
    private static func directory(_ fd:Int32,privateOnly:Bool=false)throws {
        var s=stat()
        guard fstat(fd,&s)==0,s.st_mode&S_IFMT==S_IFDIR,[uid_t(0),geteuid()].contains(s.st_uid),
              s.st_mode & (privateOnly ? 0o7777:0o6022) == (privateOnly ? 0o700:0),noACL(fd) else {try fail()}
        if privateOnly && s.st_uid != geteuid() {try fail()}
    }
    private static func names(_ fd:Int32)throws->Set<String> {
        let copied=dup(fd);guard copied>=0,let stream=fdopendir(copied) else {if copied>=0 {close(copied)};try fail()}
        defer {closedir(stream)};rewinddir(stream)
        var result=Set<String>()
        while true {
            errno=0;guard let entry=readdir(stream) else {if errno != 0 {try fail()};break}
            let bytes=withUnsafeBytes(of:entry.pointee.d_name) {Data($0.prefix(Int(entry.pointee.d_namlen)))}
            guard let name=String(data:bytes,encoding:.utf8) else {try fail()}
            if name=="." || name==".." {continue}
            guard result.count<16,result.insert(name).inserted else {try fail()}
        }
        return result
    }
    private static func childDirectory(_ fd:Int32,parent:Int32,name:String)throws {
        var held=stat(),named=stat()
        guard fstat(fd,&held)==0,fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW)==0,
              named.st_mode&S_IFMT==S_IFDIR,same(held,named) else {try fail()}
    }
    private static func regular(_ parent:Int32,_ name:String,mode:Int?,maximum:Int64)throws->(Int32,stat) {
        let fd=openat(parent,name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {try fail()}
        var s=stat(),named=stat()
        guard fstat(fd,&s)==0,s.st_mode&S_IFMT==S_IFREG,s.st_nlink==1,[uid_t(0),geteuid()].contains(s.st_uid),
              s.st_mode&0o6022==0,mode==nil || s.st_mode&0o7777==mode_t(mode!),s.st_size>0,s.st_size<=maximum,
              fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW)==0,same(s,named),noACL(fd) else {close(fd);try fail()}
        return (fd,s)
    }
    private static func verify(_ fd:Int32,_ initial:stat,parent:Int32,name:String)throws {
        var current=stat(),named=stat()
        guard fstat(fd,&current)==0,fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW)==0,same(initial,current),same(current,named) else {try fail()}
    }
    private static func data(_ parent:Int32,_ name:String,maximum:Int64)throws->Data {
        let (fd,s)=try regular(parent,name,mode:nil,maximum:maximum);defer {close(fd)}
        var value=Data(),buffer=[UInt8](repeating:0,count:32768)
        while value.count<=maximum {
            let n=read(fd,&buffer,buffer.count)
            if n<0 && errno==EINTR {continue};guard n>=0 else {try fail()};if n==0 {break}
            value.append(contentsOf:buffer.prefix(n))
        }
        guard value.count==s.st_size else {try fail()};try verify(fd,s,parent:parent,name:name)
        return value
    }
    private static func artifacts(_ bytes:Data)throws->[Artifact] {
        try StrictJSON.validate(bytes,maximum:65536)
        guard let v=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],WireScalar.integer(v["schema"],maximum:1)==1,
              WireScalar.integer(v["journal_schema"],maximum:8)==8,v["approval"] as? String=="development_observation_only",
              let complete=v["package_complete"] as? NSNumber,CFGetTypeID(complete)==CFBooleanGetTypeID(),!complete.boolValue,
              let activation=v["activation"] as? [String:Any],Set(activation.keys)==Set(["managed_inference","sandbox_tasks","native_lifecycle","launchd_installation"]),
              activation.values.allSatisfy({if let flag=$0 as? NSNumber {return CFGetTypeID(flag)==CFBooleanGetTypeID() && !flag.boolValue};return false}),
              let rows=v["artifacts"] as? [[String:Any]],rows.count==modes.count else {try fail()}
        var result:[Artifact]=[],seen=Set<String>(),total:Int64=0
        for row in rows {
            guard Set(row.keys)==Set(["path","sha256","bytes","mode"]),let path=row["path"] as? String,let mode=modes[path],seen.insert(path).inserted,
                  WireScalar.integer(row["mode"],maximum:4095)==Int64(mode),let size=WireScalar.integer(row["bytes"],maximum:64<<20),size>0,
                  let sha=row["sha256"] as? String,WireScalar.sha256(sha) else {try fail()}
            total+=size;guard total<=256<<20 else {try fail()};result.append(Artifact(path:path,hash:sha,bytes:size,mode:mode))
        }
        return result.sorted {$0.path<$1.path}
    }
    public static func create(source:URL,expectedSHA256:String,destination:URL)throws->PlatformReleaseStageReceipt {
        guard geteuid() != 0,source.isFileURL,destination.isFileURL,WireScalar.sha256(expectedSHA256),
              !source.path.split(separator:"/").contains(".."),!destination.path.split(separator:"/").contains("..") else {try fail()}
        let deadline=ProcessInfo.processInfo.systemUptime+30
        let sourceFD=open(source.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard sourceFD>=0 else {try fail()};defer {close(sourceFD)};try directory(sourceFD)
        let parent=destination.deletingLastPathComponent(),name=destination.lastPathComponent
        guard !name.isEmpty,name != ".",name != "..",name.utf8.count<=255 else {try fail()}
        let parentFD=open(parent.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard parentFD>=0 else {try fail()};defer {close(parentFD)};try directory(parentFD,privateOnly:true)
        // Canonical paths are only an early nesting check. All subsequent
        // writes/publication are relative to the retained verified descriptors.
        let canonicalSource=try canonical(source.path)
        let canonicalParent=try canonical(parent.path)
        guard canonicalParent != canonicalSource,!canonicalParent.hasPrefix(canonicalSource+"/") else {try fail()}
        try namedDirectory(sourceFD,path:canonicalSource);try namedDirectory(parentFD,path:canonicalParent)
        var existing=stat()
        guard fstatat(parentFD,name,&existing,AT_SYMLINK_NOFOLLOW) != 0,errno==ENOENT else {try fail()}
        let receipt=try data(sourceFD,"release.json",maximum:65536)
        guard hash(receipt)==expectedSHA256 else {try fail()};let entries=try artifacts(receipt)
        let folders=Set(["bin","sandbox","python","launchd"])
        guard try names(sourceFD)==folders.union(["release.json"]) else {try fail()}
        var sources:[String:Int32]=[:]
        defer {for fd in sources.values {close(fd)}}
        for folder in folders {
            let fd=openat(sourceFD,folder,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {try fail()};sources[folder]=fd;try directory(fd)
            let expected=Set(entries.filter {$0.path.hasPrefix(folder+"/")}.map {String($0.path.split(separator:"/")[1])})
            guard try names(fd)==expected else {try fail()}
        }
        var capacity=statfs()
        let required=entries.reduce(Int64(receipt.count)) {$0+$1.bytes}+(10<<30)
        guard fstatfs(parentFD,&capacity)==0,capacity.f_bsize>0,
              capacity.f_bavail<=UInt64.max/UInt64(capacity.f_bsize),
              capacity.f_bavail*UInt64(capacity.f_bsize)>=UInt64(required) else {try fail()}
        var published=false
        let temporary=".fios-stage-"+UUID().uuidString.lowercased()
        guard mkdirat(parentFD,temporary,0o700)==0 else {try fail()}
        do {
            let target=openat(parentFD,temporary,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            guard target>=0 else {try fail()};defer {close(target)};try directory(target,privateOnly:true)
            var initial=stat();guard fstat(target,&initial)==0 else {try fail()}
            var targets:[String:Int32]=[:];defer {for fd in targets.values {close(fd)}}
            for folder in folders {
                guard mkdirat(target,folder,0o700)==0 else {try fail()}
                let fd=openat(target,folder,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {try fail()};targets[folder]=fd;try directory(fd,privateOnly:true)
            }
            var total:Int64=0
            for item in entries {
                guard ProcessInfo.processInfo.systemUptime<deadline else {try fail()}
                let parts=item.path.split(separator:"/"),folder=String(parts[0]),leaf=String(parts[1]),from=sources[folder]!,to=targets[folder]!
                let (input,before)=try regular(from,leaf,mode:item.mode,maximum:item.bytes);defer {close(input)}
                guard before.st_size==item.bytes else {try fail()}
                let output=openat(to,leaf,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK,mode_t(item.mode));guard output>=0 else {try fail()};defer {close(output)}
                guard fchmod(output,mode_t(item.mode))==0,noACL(output) else {try fail()}
                var digest=SHA256(),count:Int64=0,buffer=[UInt8](repeating:0,count:32768)
                while true {
                    guard ProcessInfo.processInfo.systemUptime<deadline else {try fail()}
                    let n=read(input,&buffer,buffer.count);if n<0 && errno==EINTR {continue};guard n>=0 else {try fail()};if n==0 {break}
                    count+=Int64(n);guard count<=item.bytes else {try fail()};let chunk=Data(buffer.prefix(n));digest.update(data:chunk)
                    try chunk.withUnsafeBytes {raw in var offset=0;while offset<n {let written=write(output,raw.baseAddress!.advanced(by:offset),n-offset);if written<0 && errno==EINTR {continue};guard written>0 else {try fail()};offset+=written}}
                }
                guard count==item.bytes,digest.finalize().map({String(format:"%02x",$0)}).joined()==item.hash,fsync(output)==0 else {try fail()}
                try verify(input,before,parent:from,name:leaf)
                let (copied,copiedStat)=try regular(to,leaf,mode:item.mode,maximum:item.bytes);defer {close(copied)}
                var copiedHash=SHA256(),copiedCount:Int64=0
                while true {guard ProcessInfo.processInfo.systemUptime<deadline else {try fail()};let n=read(copied,&buffer,buffer.count);if n<0 && errno==EINTR {continue};guard n>=0 else {try fail()};if n==0 {break};copiedCount+=Int64(n);guard copiedCount<=item.bytes else {try fail()};copiedHash.update(data:Data(buffer.prefix(n)))}
                guard copiedCount==item.bytes,copiedHash.finalize().map({String(format:"%02x",$0)}).joined()==item.hash else {try fail()};try verify(copied,copiedStat,parent:to,name:leaf)
                total+=count
            }
            let manifest=openat(target,"release.json",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600);guard manifest>=0 else {try fail()};defer {close(manifest)}
            try receipt.withUnsafeBytes {raw in var offset=0;while offset<raw.count {let n=write(manifest,raw.baseAddress!.advanced(by:offset),raw.count-offset);if n<0 && errno==EINTR {continue};guard n>0 else {try fail()};offset+=n}}
            guard fsync(manifest)==0,try data(target,"release.json",maximum:65536)==receipt,try data(sourceFD,"release.json",maximum:65536)==receipt else {try fail()}
            for fd in targets.values {guard fsync(fd)==0 else {try fail()}}
            try directory(target,privateOnly:true)
            guard try names(target)==folders.union(["release.json"]) else {try fail()}
            for folder in folders {
                let expected=Set(entries.filter {$0.path.hasPrefix(folder+"/")}.map {String($0.path.split(separator:"/")[1])})
                guard try names(targets[folder]!)==expected else {try fail()}
                try directory(targets[folder]!,privateOnly:true)
                try childDirectory(targets[folder]!,parent:target,name:folder)
                try childDirectory(sources[folder]!,parent:sourceFD,name:folder)
            }
            try directory(parentFD,privateOnly:true)
            try namedDirectory(parentFD,path:canonicalParent);try namedDirectory(sourceFD,path:canonicalSource)
            var named=stat()
            guard fsync(target)==0,fstatat(parentFD,temporary,&named,AT_SYMLINK_NOFOLLOW)==0,named.st_dev==initial.st_dev,named.st_ino==initial.st_ino,
                  renameatx_np(parentFD,temporary,parentFD,name,UInt32(RENAME_EXCL))==0 else {try fail()}
            published=true
            guard fsync(parentFD)==0 else {try fail()}
            return PlatformReleaseStageReceipt(manifestSHA256:expectedSHA256,artifacts:entries.count,bytes:total+Int64(receipt.count))
        }catch {if published {throw PlatformReleaseStagingError.publicationUncertain};throw PlatformReleaseStagingError.retained(temporary)}
    }
}
