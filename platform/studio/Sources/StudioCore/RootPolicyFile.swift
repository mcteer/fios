import Foundation
import Darwin
import CryptoKit

// Trusted callers select fixed installation paths. This is not an IPC path
// reader or an enrollment issuer: bytes still need their strict policy schema,
// approved user/source binding and scope validation before granting authority.
enum RootPolicyFile {
    static func read(path:String,maximum:Int,expectedSHA256:String?=nil)throws->Data {
        guard geteuid()>0,getuid()==geteuid(),(1...65536).contains(maximum),
              path.hasPrefix("/"),!path.hasSuffix("/"),!path.contains("//"),!path.contains("\0"),
              path.utf8.count<Int(MAXPATHLEN),expectedSHA256.map(WireScalar.sha256) ?? true else {throw ControlError.unauthorized}
        let deadline=ProcessInfo.processInfo.systemUptime+2
        let (parent,name)=try rootParent(path:path,deadline:deadline)
        defer {close(parent)}
        let fd=openat(parent,name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw ControlError.unauthorized};defer {close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_uid==0,
              [0o444,0o644].contains(Int(before.st_mode&0o7777)),before.st_nlink==1,
              (1...Int64(maximum)).contains(before.st_size),noACL(fd) else {throw ControlError.unauthorized}
        var result=Data(),buffer=[UInt8](repeating:0,count:4096)
        while true {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw ControlError.unauthorized}
            let count=Darwin.read(fd,&buffer,min(buffer.count,maximum-result.count+1))
            if count<0,errno==EINTR {continue}
            guard count>=0,result.count+count<=maximum else {throw ControlError.unauthorized}
            if count==0 {break}
            result.append(contentsOf:buffer.prefix(count))
        }
        guard result.count==before.st_size,fstat(fd,&after)==0,
              fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW)==0,
              stable(before,after),stable(after,named),noACL(fd) else {throw ControlError.unauthorized}
        if let expectedSHA256 {
            let actual=SHA256.hash(data:result).map {String(format:"%02x",$0)}.joined()
            guard actual==expectedSHA256 else {throw ControlError.unauthorized}
        }
        return result
    }
    static func verifyExecutable(_ executable:VerifiedExecutable)throws {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        let (parent,name)=try rootParent(path:executable.path,deadline:deadline)
        defer {close(parent)}
        let fd=openat(parent,name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw ControlError.unauthorized};defer {close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_uid==0,
              [0o555,0o755].contains(Int(before.st_mode&0o7777)),before.st_nlink==1,noACL(fd) else {throw ControlError.unauthorized}
        do {try executable.verify(deadline:deadline)} catch {throw ControlError.unauthorized}
        guard ProcessInfo.processInfo.systemUptime<deadline,fstat(fd,&after)==0,
              fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW)==0,
              stable(before,after),stable(after,named),noACL(fd) else {throw ControlError.unauthorized}
        // Current immutable path/file proof only. The installer must serialize
        // updates and stop old processes; this is not mapped-code attestation.
    }
    private static func rootParent(path:String,deadline:TimeInterval)throws->(Int32,String) {
        guard geteuid()>0,getuid()==geteuid(),path.hasPrefix("/"),!path.hasSuffix("/"),
              !path.contains("//"),!path.contains("\0"),path.utf8.count<Int(MAXPATHLEN) else {throw ControlError.unauthorized}
        let parts=path.dropFirst().split(separator:"/",omittingEmptySubsequences:false).map(String.init)
        guard !parts.isEmpty,parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}) else {throw ControlError.unauthorized}
        var parent=open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard parent>=0 else {throw ControlError.unauthorized}
        do {
            try directory(parent)
            for component in parts.dropLast() {
                guard ProcessInfo.processInfo.systemUptime<deadline else {throw ControlError.unauthorized}
                let next=openat(parent,component,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                guard next>=0 else {throw ControlError.unauthorized}
                do {try directory(next)} catch {close(next);throw error}
                close(parent);parent=next
            }
            return (parent,parts.last!) // Caller owns the descriptor.
        } catch {close(parent);throw error}
    }
    private static func directory(_ fd:Int32)throws {
        var value=stat()
        guard fstat(fd,&value)==0,value.st_mode&S_IFMT==S_IFDIR,value.st_uid==0,
              value.st_mode&0o7022==0,noACL(fd) else {throw ControlError.unauthorized}
    }
    private static func noACL(_ fd:Int32)->Bool {
        // Mode bits alone miss ACL write grants to another local user. Even
        // deny-only/empty explicit ACL objects require operator normalization.
        if let acl=acl_get_fd_np(fd,ACL_TYPE_EXTENDED) {
            acl_free(UnsafeMutableRawPointer(acl));return false
        }
        return errno==ENOENT
    }
    private static func stable(_ a:stat,_ b:stat)->Bool {
        a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_uid==b.st_uid && a.st_gid==b.st_gid &&
        a.st_mode==b.st_mode && a.st_nlink==b.st_nlink && a.st_size==b.st_size &&
        a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
    }
}
