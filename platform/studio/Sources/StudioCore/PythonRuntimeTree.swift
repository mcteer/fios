import Foundation
import Darwin
import CryptoKit
import CoreFoundation

// Byte observations only. Neither entry point enrolls a runtime, executes it,
// constructs a worker factory or supplies native admission/terminal proof.
struct PythonRuntimeTreeObservation {
    let files:Int
    let bytes:Int64
    let rootProtected:Bool
    let lockSHA256:String
    let producerSHA256:String
    let templateSHA256:String
    let interpreterSHA256:String?
}

enum PythonRuntimeTreeReview {
    private struct FileRecord {let bytes:Int64;let hash:String;let mode:mode_t}
    static func privateCandidate(directory:URL,manifestSHA256:String)throws->PythonRuntimeTreeObservation {
        try review(directory:directory,manifestSHA256:manifestSHA256,owner:geteuid(),rootProtected:false)
    }
    static func rootProtectedCandidate(directory:URL,manifestSHA256:String)throws->PythonRuntimeTreeObservation {
        // Preserve the existing protected-ancestor/physical-tree gate. Its
        // stricter8192-node limit also bounds this root-protected review.
        try RootPolicyFile.verifyApplicationTree(path:directory.path,deadline:ProcessInfo.processInfo.systemUptime+10)
        return try review(directory:directory,manifestSHA256:manifestSHA256,owner:0,rootProtected:true)
    }
    private static func same(_ a:stat,_ b:stat)->Bool {
        a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_uid==b.st_uid && a.st_gid==b.st_gid &&
        a.st_mode==b.st_mode && a.st_nlink==b.st_nlink && a.st_size==b.st_size &&
        a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
    }
    private static func noACL(_ fd:Int32)->Bool {
        errno=0
        if let acl=acl_get_fd_np(fd,ACL_TYPE_EXTENDED) {acl_free(UnsafeMutableRawPointer(acl));return false}
        return errno==ENOENT
    }
    private static func readFile(parent:Int32,name:String,owner:uid_t,maximum:Int64,keep:Bool,deadline:TimeInterval)throws->(Data,String,Int64,mode_t) {
        let fd=openat(parent,name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw ControlError.unauthorized};defer {close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_uid==owner,before.st_nlink==1,
              before.st_size>=0,before.st_size<=maximum,noACL(fd) else {throw ControlError.unauthorized}
        var hash=SHA256(),data=Data(),total:Int64=0,buffer=[UInt8](repeating:0,count:32768)
        while true {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw ControlError.unauthorized}
            let count=Darwin.read(fd,&buffer,buffer.count)
            if count<0,errno==EINTR {continue}
            guard count>=0,total+Int64(count)<=maximum else {throw ControlError.unauthorized}
            if count==0 {break}
            let block=Data(buffer.prefix(count));hash.update(data:block);if keep {data.append(block)}
            total+=Int64(count)
        }
        guard total==before.st_size,fstat(fd,&after)==0,fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW)==0,
              same(before,after),same(after,named),noACL(fd) else {throw ControlError.unauthorized}
        return (data,hash.finalize().map {String(format:"%02x",$0)}.joined(),total,before.st_mode&0o7777)
    }
    private static func review(directory:URL,manifestSHA256:String,owner:uid_t,rootProtected:Bool)throws->PythonRuntimeTreeObservation {
        guard geteuid()>0,getuid()==geteuid(),WireScalar.sha256(manifestSHA256),directory.path.hasPrefix("/"),
              !directory.path.contains("\0"),!directory.path.contains("//"),
              directory.path.split(separator:"/").allSatisfy({$0 != "." && $0 != ".."}) else {throw ControlError.unauthorized}
        let deadline=ProcessInfo.processInfo.systemUptime+120
        let root=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard root>=0 else {throw ControlError.unauthorized};defer {close(root)}
        let (manifest,digest,manifestBytes,manifestMode)=try readFile(parent:root,name:"candidate.json",owner:owner,maximum:4<<20,keep:true,deadline:deadline)
        guard digest==manifestSHA256,manifestMode==0o644 else {throw ControlError.unauthorized}
        try StrictJSON.validate(manifest,maximum:4<<20)
        guard let value=try JSONSerialization.jsonObject(with:manifest) as? [String:Any],
              Set(value.keys)==Set(["version","purpose","python_version","platform","uv_lock_sha256","producer_sha256","release_template_sha256",
                "agent_sources","distributions","files","bytes","console_wrappers_excluded","probe","scope","immutable_tree_enrolled","approved","activation"]),
              WireScalar.integer(value["version"],maximum:1)==1,value["purpose"] as? String=="python_worker_runtime_candidate",
              value["python_version"] as? String=="3.11.17",value["platform"] as? String=="macos/arm64",
              value["scope"] as? String=="declared_installed_runtime_bytes_not_publisher_build_or_whole_os_provenance",
              ["uv_lock_sha256","producer_sha256","release_template_sha256"].allSatisfy({(value[$0] as? String).map(WireScalar.sha256)==true}),
              ["immutable_tree_enrolled","approved","activation"].allSatisfy({key in
                guard let flag=value[key] as? NSNumber,CFGetTypeID(flag)==CFBooleanGetTypeID() else {return false};return !flag.boolValue
              }),let files=value["files"] as? [String:[String:Any]],(1...10000).contains(files.count),
              let declaredBytes=WireScalar.integer(value["bytes"],maximum:512<<20),declaredBytes>0 else {throw ControlError.unauthorized}
        var records:[Data:FileRecord]=[:],folders:Set<Data>=[Data()],total:Int64=0
        for (path,record) in files {
            let parts=path.split(separator:"/",omittingEmptySubsequences:false)
            guard path != "candidate.json",path.utf8.count<=4096,parts.count<=32,!path.contains("\0"),!path.contains("\\"),
                  parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}),
                  Set(record.keys)==Set(["bytes","sha256","mode"]),
                  let bytes=WireScalar.integer(record["bytes"],maximum:128<<20),
                  let hash=record["sha256"] as? String,WireScalar.sha256(hash),
                  let mode=WireScalar.integer(record["mode"],maximum:0o7777),mode==(path.hasPrefix("bin/") ? 0o755:0o644),
                  records.updateValue(FileRecord(bytes:bytes,hash:hash,mode:mode_t(mode)),forKey:Data(path.utf8))==nil else {throw ControlError.unauthorized}
            total+=bytes;guard total<=512<<20 else {throw ControlError.unauthorized}
            for length in 1..<parts.count {folders.insert(Data(parts.prefix(length).joined(separator:"/").utf8))}
        }
        guard total==declaredBytes else {throw ControlError.unauthorized}
        let count=records.count
        records[Data("candidate.json".utf8)]=FileRecord(bytes:manifestBytes,hash:digest,mode:0o644)
        var observed:Set<Data>=[]
        func walk(_ fd:Int32,_ relative:String,_ depth:Int)throws {
            var before=stat(),after=stat()
            guard depth<=32,ProcessInfo.processInfo.systemUptime<deadline,fstat(fd,&before)==0,
                  before.st_mode&S_IFMT==S_IFDIR,before.st_uid==owner,noACL(fd),
                  rootProtected ? before.st_mode&0o7022==0:before.st_mode&0o7777==0o700 else {throw ControlError.unauthorized}
            let duplicate=fcntl(fd,F_DUPFD_CLOEXEC,0);guard duplicate>=0 else {throw ControlError.unauthorized}
            guard let entries=fdopendir(duplicate) else {close(duplicate);throw ControlError.unauthorized}
            defer {closedir(entries)}
            while true {
                errno=0
                guard let entry=readdir(entries) else {guard errno==0 else {throw ControlError.unauthorized};break}
                let bytes=withUnsafeBytes(of:entry.pointee.d_name) {Array($0.prefix(while:{$0 != 0}))}
                guard let name=String(bytes:bytes,encoding:.utf8),!name.isEmpty else {throw ControlError.unauthorized}
                if name=="." || name==".." {continue}
                guard ProcessInfo.processInfo.systemUptime<deadline else {throw ControlError.unauthorized}
                let path=relative.isEmpty ? name:relative+"/"+name,key=Data(path.utf8)
                var named=stat()
                guard fstatat(fd,name,&named,AT_SYMLINK_NOFOLLOW)==0 else {throw ControlError.unauthorized}
                if named.st_mode&S_IFMT==S_IFDIR {
                    guard folders.contains(key) else {throw ControlError.unauthorized}
                    let child=openat(fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                    guard child>=0 else {throw ControlError.unauthorized};defer {close(child)}
                    var held=stat(),current=stat()
                    guard fstat(child,&held)==0,same(named,held) else {throw ControlError.unauthorized}
                    try walk(child,path,depth+1)
                    guard fstat(child,&held)==0,fstatat(fd,name,&current,AT_SYMLINK_NOFOLLOW)==0,same(held,current) else {throw ControlError.unauthorized}
                }else {
                    guard let expected=records[key],observed.insert(key).inserted else {throw ControlError.unauthorized}
                    let (_,hash,size,mode)=try readFile(parent:fd,name:name,owner:owner,maximum:expected.bytes,keep:false,deadline:deadline)
                    guard hash==expected.hash,size==expected.bytes,mode==expected.mode else {throw ControlError.unauthorized}
                }
            }
            guard fstat(fd,&after)==0,same(before,after) else {throw ControlError.unauthorized}
        }
        try walk(root,"",0)
        var held=stat(),named=stat()
        guard observed==Set(records.keys),fstat(root,&held)==0,lstat(directory.path,&named)==0,same(held,named) else {throw ControlError.unauthorized}
        return PythonRuntimeTreeObservation(files:count,bytes:total,rootProtected:rootProtected,
            lockSHA256:value["uv_lock_sha256"] as! String,producerSHA256:value["producer_sha256"] as! String,
            templateSHA256:value["release_template_sha256"] as! String,interpreterSHA256:records[Data("bin/python".utf8)]?.hash)
    }
}
