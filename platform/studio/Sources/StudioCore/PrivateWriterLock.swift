import Foundation
import Darwin

// Fixed private metadata writers only; no caller-selected lock filename.
enum PrivateWriterKind:String {
    case supervisor="supervisor.lock"
    case session="session.lock"
}
final class PrivateWriterLock {
    private var descriptor:Int32 = -1
    init(directory:URL,kind:PrivateWriterKind)throws {
        guard getuid() != 0,getuid()==geteuid() else {throw ControlError.unauthorized}
        let parentFD=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard parentFD>=0 else {throw ControlError.unauthorized}
        defer {Darwin.close(parentFD)}
        var parent=stat(),parentName=stat()
        guard fstat(parentFD,&parent)==0,parent.st_mode & S_IFMT == S_IFDIR,
              parent.st_uid==geteuid(),parent.st_mode & 0o7777==0o700 else {throw ControlError.unauthorized}
        let fd=openat(parentFD,kind.rawValue,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK,0o600)
        guard fd>=0 else {throw ControlError.unauthorized}
        var opened=stat(),named=stat()
        guard fstat(fd,&opened)==0,opened.st_mode & S_IFMT == S_IFREG,
              opened.st_uid==geteuid(),opened.st_nlink==1,opened.st_mode & 0o7777==0o600,
              flock(fd,LOCK_EX|LOCK_NB)==0,
              fstatat(parentFD,kind.rawValue,&named,AT_SYMLINK_NOFOLLOW)==0,
              named.st_mode & S_IFMT == S_IFREG,named.st_dev==opened.st_dev,named.st_ino==opened.st_ino,
              named.st_uid==opened.st_uid,named.st_nlink==1,named.st_mode==opened.st_mode,
              lstat(directory.path,&parentName)==0,parentName.st_dev==parent.st_dev,parentName.st_ino==parent.st_ino,
              parentName.st_uid==parent.st_uid,parentName.st_mode==parent.st_mode else {
            Darwin.close(fd);throw ControlError.busy
        }
        descriptor=fd
    }
    func release() {
        if descriptor>=0 {Darwin.close(descriptor);descriptor = -1}
    }
    deinit {release()}
}
