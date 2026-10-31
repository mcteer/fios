import Foundation
import Darwin

// Code-only fixed-suffix policy. Installed construction supplies the root-
// reviewed account home; tests use a generated private /private/tmp home.
// No connect, daemon request, socket deletion, or native absence authority.
struct RuntimeEndpointPolicy:Sendable {
    let home:String
    let uid:uid_t
    let peer:RuntimePeerPolicy?
    var path:String {home+"/.orbstack/run/docker.sock"}
    init(home:String,uid:uid_t,peer:RuntimePeerPolicy?=nil)throws {
        guard uid>0,uid==geteuid(),getuid()==geteuid(),home.hasPrefix("/"),
              !home.hasSuffix("/"),!home.contains("//"),!home.contains("\0"),
              !home.split(separator:"/").contains(where:{$0=="." || $0==".."}),
              (home+"/.orbstack/run/docker.sock").utf8.count<104 else {throw RuntimeError.identity}
        guard peer == nil || peer?.uid==uid else {throw RuntimeError.identity}
        self.home=home;self.uid=uid;self.peer=peer
    }
    func capture(deadline:TimeInterval)throws->PinnedRuntimeEndpoint {
        try EndpointMetadata.deadline(deadline)
        var directories:[PinnedRuntimeEndpoint.Directory]=[]
        var transferred=false
        defer {if !transferred {for directory in directories {Darwin.close(directory.fd)}}}
        let root=open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard root>=0 else {throw RuntimeError.identity}
        var rootInfo=stat()
        guard fstat(root,&rootInfo)==0 else {Darwin.close(root);throw RuntimeError.identity}
        directories.append(.init(fd:root,parent:nil,name:"",identity:rootInfo))
        guard rootInfo.st_uid==0,rootInfo.st_mode&S_IFMT==S_IFDIR,rootInfo.st_mode&0o7022==0,
              EndpointMetadata.denyOnlyACL(fd:root) else {throw RuntimeError.identity}
        let account=home.split(separator:"/").map(String.init),parts=account+[".orbstack","run"]
        var prefix=""
        for (index,name) in parts.enumerated() {
            try EndpointMetadata.deadline(deadline)
            prefix+="/"+name
            let parent=directories.last!.fd
            let fd=openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw RuntimeError.identity}
            var info=stat()
            guard fstat(fd,&info)==0 else {Darwin.close(fd);throw RuntimeError.identity}
            directories.append(.init(fd:fd,parent:parent,name:name,identity:info))
            let expectedOwner=index>=account.count-1 ? uid:0
            // Fixed OS temporary root for isolated fixtures only. Production
            // enrollment restricts homes to a direct child of /Users.
            let stickyTemporary=prefix=="/private/tmp" && info.st_uid==0 && info.st_mode&0o7777==0o1777
            guard info.st_mode&S_IFMT==S_IFDIR,info.st_uid==expectedOwner,
                  (info.st_mode&0o7022==0 || stickyTemporary),
                  index<account.count || info.st_mode&0o7777==0o700,
                  EndpointMetadata.denyOnlyACL(fd:fd) else {throw RuntimeError.identity}
        }
        var socketInfo=stat()
        guard fstatat(directories.last!.fd,"docker.sock",&socketInfo,AT_SYMLINK_NOFOLLOW)==0,
              socketInfo.st_mode&S_IFMT==S_IFSOCK,socketInfo.st_uid==uid,
              socketInfo.st_nlink==1,socketInfo.st_mode&0o7022==0 else {throw RuntimeError.identity}
        let pinned=PinnedRuntimeEndpoint(path:path,directories:directories,socket:socketInfo)
        transferred=true
        try pinned.verify(deadline:deadline)
        return pinned
    }
}

final class PinnedRuntimeEndpoint {
    struct Directory {let fd:Int32;let parent:Int32?;let name:String;let identity:stat}
    let path:String
    private let directories:[Directory]
    private let socket:stat
    fileprivate init(path:String,directories:[Directory],socket:stat) {self.path=path;self.directories=directories;self.socket=socket}
    deinit {for directory in directories {Darwin.close(directory.fd)}}
    func verify(deadline:TimeInterval)throws {
        try EndpointMetadata.deadline(deadline)
        for directory in directories {
            var held=stat(),named=stat()
            guard fstat(directory.fd,&held)==0,EndpointMetadata.same(directory.identity,held),
                  EndpointMetadata.denyOnlyACL(fd:directory.fd) else {throw RuntimeError.identity}
            if let parent=directory.parent {
                guard fstatat(parent,directory.name,&named,AT_SYMLINK_NOFOLLOW)==0,
                      EndpointMetadata.same(held,named) else {throw RuntimeError.identity}
            }
            try EndpointMetadata.deadline(deadline)
        }
        var named=stat()
        guard fstatat(directories.last!.fd,"docker.sock",&named,AT_SYMLINK_NOFOLLOW)==0,
              EndpointMetadata.same(socket,named),named.st_nlink==1,
              EndpointMetadata.denyOnlySocketACL(path:path) else {throw RuntimeError.identity}
        try EndpointMetadata.deadline(deadline)
    }
}

private enum EndpointMetadata {
    static func deadline(_ value:TimeInterval)throws {
        guard value.isFinite,ProcessInfo.processInfo.systemUptime<value else {throw RuntimeError.deadline}
    }
    static func same(_ a:stat,_ b:stat)->Bool {
        a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_mode==b.st_mode && a.st_uid==b.st_uid && a.st_gid==b.st_gid
    }
    static func denyOnlyACL(fd:Int32)->Bool {
        errno=0
        return denyOnly(acl_get_fd_np(fd,ACL_TYPE_EXTENDED))
    }
    static func denyOnlySocketACL(path:String)->Bool {
        errno=0
        return denyOnly(acl_get_link_np(path,ACL_TYPE_EXTENDED))
    }
    private static func denyOnly(_ acl:acl_t?)->Bool {
        guard let acl else {return errno==ENOENT}
        defer {acl_free(UnsafeMutableRawPointer(acl))}
        guard acl_valid(acl)==0 else {return false}
        // Darwin returns0 per entry and EINVAL at the end of a valid ACL.
        // Keep the iteration bounded even for a corrupt/unexpected object.
        for index in 0..<256 {
            var entry:acl_entry_t?
            errno=0
            if acl_get_entry(acl,Int32(index),&entry) != 0 {return errno==EINVAL}
            guard let entry else {return false}
            var tag=ACL_EXTENDED_DENY
            guard acl_get_tag_type(entry,&tag)==0,tag==ACL_EXTENDED_DENY else {return false}
        }
        return false
    }
}
