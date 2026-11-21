import Foundation
import Darwin

// Code-only expected daemon image. Installed construction must supply it from
// root-reviewed immutable policy, never a task, endpoint advertisement or PID.
// Current on-disk bytes/path/start are not mapped-code or VM epoch attestation.
struct RuntimePeerPolicy:Sendable {
    let uid:uid_t
    let executable:VerifiedExecutable
    init(uid:uid_t,executable:VerifiedExecutable)throws {
        guard uid>0,uid==getuid(),getuid()==geteuid() else {throw RuntimeError.identity}
        self.uid=uid;self.executable=executable
    }
    private func checkDeadline(_ deadline:TimeInterval)throws {
        let now=ProcessInfo.processInfo.systemUptime
        guard deadline.isFinite,deadline>now,deadline-now<=2 else {throw RuntimeError.deadline}
    }
    func verifyProcessKernel(identity:ServiceIdentity,deadline:TimeInterval)throws {
        try checkDeadline(deadline)
        let pid=identity.pid
        var info=proc_bsdinfo(),path=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard pid>1,identity.sha256==executable.sha256,try WorkerResources.startIdentifier(pid:pid)==identity.start,
              proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,Int32(MemoryLayout<proc_bsdinfo>.size))==MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid==uid,info.pbi_ruid==uid,info.pbi_svuid==uid,
              proc_pidpath(pid,&path,UInt32(path.count))>0,
              path.prefix(while:{$0 != 0}).map({UInt8(bitPattern:$0)})==Array(executable.path.utf8) else {throw RuntimeError.identity}
        try checkDeadline(deadline)
    }
    func verifyIdentity(_ identity:ServiceIdentity,deadline:TimeInterval)throws->ServiceIdentity {
        try checkDeadline(deadline)
        do {
            let actual=try ServiceIdentity.verified(peer:NativeControlPeer(pid:identity.pid,start:identity.start,executable:executable),expectedUID:uid,deadline:deadline)
            guard actual==identity else {throw RuntimeError.identity}
            return actual
        }catch {
            if ProcessInfo.processInfo.systemUptime>=deadline {throw RuntimeError.deadline}
            throw RuntimeError.identity
        }
    }
    func authenticate(fd:Int32,deadline:TimeInterval)throws->ServiceIdentity {
        try checkDeadline(deadline)
        func principal()throws->Int32 {
            var actual:uid_t=0,gid:gid_t=0,pid:Int32=0,length=socklen_t(MemoryLayout<Int32>.size)
            guard getpeereid(fd,&actual,&gid)==0,actual==uid,
                  getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&length)==0,length==MemoryLayout<Int32>.size,pid>1 else {throw RuntimeError.identity}
            return pid
        }
        let pid=try principal()
        do {
            let start=try WorkerResources.startIdentifier(pid:pid)
            let identity=try ServiceIdentity.verified(peer:NativeControlPeer(pid:pid,start:start,executable:executable),expectedUID:uid,deadline:deadline)
            guard try principal()==pid,ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.identity}
            return identity
        } catch {
            if ProcessInfo.processInfo.systemUptime>=deadline {throw RuntimeError.deadline}
            throw RuntimeError.identity
        }
    }
    func connect(path:String,deadline:TimeInterval)throws->RuntimePeerConnection {
        try checkDeadline(deadline)
        guard path.hasPrefix("/"),!path.contains("\0"),path.utf8.count<104 else {throw RuntimeError.identity}
        let fd=socket(AF_UNIX,SOCK_STREAM,0)
        guard fd>=0 else {throw RuntimeError.launch}
        var transferred=false
        defer {if !transferred {Darwin.close(fd)}}
        guard fcntl(fd,F_SETFL,O_NONBLOCK)>=0,fcntl(fd,F_SETFD,FD_CLOEXEC)>=0 else {throw RuntimeError.launch}
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) {$0.initializeMemory(as:UInt8.self,repeating:0);$0.copyBytes(from:Array(path.utf8))}
        let result=withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        if result != 0 {
            guard [EINPROGRESS,EAGAIN].contains(errno) else {throw RuntimeError.launch}
            while true {
                try checkDeadline(deadline)
                var item=pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
                let ready=Darwin.poll(&item,1,1)
                if ready<0 && errno==EINTR {continue}
                guard ready>=0 else {throw RuntimeError.launch}
                if ready>0 {break}
            }
            var code:Int32=0,length=socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&code,&length)==0,code==0 else {throw RuntimeError.launch}
        }
        let identity=try authenticate(fd:fd,deadline:deadline)
        let connection=RuntimePeerConnection(fd:fd,policy:self,identity:identity)
        transferred=true;return connection
    }
}

final class RuntimePeerConnection {
    private let fd:Int32
    private let policy:RuntimePeerPolicy
    private let identity:ServiceIdentity
    fileprivate init(fd:Int32,policy:RuntimePeerPolicy,identity:ServiceIdentity) {self.fd=fd;self.policy=policy;self.identity=identity}
    deinit {Darwin.close(fd)}
    func verify(deadline:TimeInterval)throws->ServiceIdentity {
        let current=try policy.verifyIdentity(identity,deadline:deadline)
        guard current==identity else {throw RuntimeError.identity}
        return current
    }
}

// At most two actual off-loop hashes, queue0. Closing/expiring an attach does
// not free its slot until the worker really finishes. A late result has no I/O
// callback/effect and cannot reopen a closed stream.
private final class RuntimeAuthenticationSlots:@unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    func acquire()throws {lock.lock();defer{lock.unlock()};guard count<2 else {throw RuntimeError.capacity};count+=1}
    func release(){lock.lock();count-=1;lock.unlock()}
}
final class RuntimePeerAuthentication:@unchecked Sendable {
    private static let slots=RuntimeAuthenticationSlots()
    private let lock=NSLock()
    private var result:Result<ServiceIdentity,RuntimeError>?
    init(policy:RuntimePeerPolicy,fd:Int32,deadline:TimeInterval)throws {
        try Self.slots.acquire()
        let copy=fcntl(fd,F_DUPFD_CLOEXEC,0)
        guard copy>=0 else {Self.slots.release();throw RuntimeError.launch}
        DispatchQueue.global(qos:.utility).async { [self] in
            defer {Darwin.close(copy);Self.slots.release()}
            let value:Result<ServiceIdentity,RuntimeError>
            do {value = .success(try policy.authenticate(fd:copy,deadline:deadline))}
            catch let error as RuntimeError {value = .failure(error)}
            catch {value = .failure(.identity)}
            lock.lock();result=value;lock.unlock()
        }
    }
    func take()->Result<ServiceIdentity,RuntimeError>? {
        lock.lock();defer{lock.unlock()};let value=result;result=nil;return value
    }
}
