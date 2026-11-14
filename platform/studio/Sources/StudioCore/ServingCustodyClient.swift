import Foundation
import Darwin

// Fixed private supervisor peer, code-only construction. Commands carry no
// credential/argv or authority. Missing connections/history remain unknown.
final class ServingCustodyClient:ServingProcessControlling {
    private let path:String
    private let peer:NativeControlPeer
    private let instance:String
    private let profile:String
    private let base:String
    private let image:String
    var recoveryProfileHash:String {profile}
    init(directory:URL,peer:NativeControlPeer,instance:String,profile:String,baseProfileHash:String,imageSHA256:String)throws {
        guard WireScalar.uuid(instance),WireScalar.sha256(profile),WireScalar.sha256(baseProfileHash),WireScalar.sha256(imageSHA256),peer.pid>1,peer.start>0 else {throw ControlError.invalid_request}
        path=directory.appendingPathComponent("serving-custody.sock").path
        guard path.utf8.count<104 else {throw ControlError.invalid_request}
        self.peer=peer;self.instance=instance;self.profile=profile;base=baseProfileHash;image=imageSHA256
    }
    func acceptsBaseProfile(_ base:String,expectedSHA256:String)->Bool {self.base==base && image==expectedSHA256}
    func accepts(_ command:ServiceLaunchCommand)->Bool {
        command.service == .mlx && WireScalar.uuid(command.id) && command.profileHash==profile && command.expectedSHA256==image
    }
    func acceptsStopReceipt(_ receipt:ServiceRecordedLaunch)->Bool {
        receipt.service == .mlx && receipt.profileHash==profile && receipt.identity.valid && receipt.identity.sha256==image && WireScalar.uuid(receipt.id) && WireScalar.uuid(receipt.boot)
    }
    private func request(id:String,operation:ServingCustodyOperation,deadline:TimeInterval?=nil,receipt:ServiceRecordedLaunch?=nil)throws->ServingCustodyValue {
        let bytes=try ServingCustodyCommand.encode(id:id,operation:operation,instance:instance,profile:profile,imageSHA256:image,deadline:deadline,receipt:receipt)
        let command=try ServingCustodyCommand(bytes,expectedSHA256:image)
        return try ServingCustodyReply.decode(exchange(bytes),command:command)
    }
    func begin(_ command:ServiceLaunchCommand,deadline:TimeInterval)throws {
        guard accepts(command) else {throw RuntimeError.invalid}
        guard case .launch(let value)=try request(id:command.id,operation:.launch,deadline:deadline) else {throw ControlError.invalid_request}
        if value == .busy {throw RuntimeError.capacity}
        if value == .wrongInstance {throw SessionTransportFailure.unavailable}
        // Original-ID lookup retrieves the immutable eventual outcome. A lost
        // response does not authorize another launch or a local not-sent claim.
    }
    func acknowledgeResult(id:String)->SessionLaunchResult {
        do {if case .launch(let value)=try request(id:id,operation:.lookupLaunch) {return value}}
        catch {}
        return .uncertain
    }
    func cancelValidation(id:String)->Bool {
        do {if case .launch(.notSent)=try request(id:id,operation:.cancelLaunch) {return true}}
        catch {}
        return false
    }
    func retireKnownExited()->Bool {false} // Only the custodian can retire its own child.
    func beginStop(id:String,matching receipt:ServiceRecordedLaunch,deadline:TimeInterval)throws {
        guard acceptsStopReceipt(receipt) else {throw RuntimeError.invalid}
        guard case .stop=try request(id:id,operation:.stop,deadline:deadline,receipt:receipt) else {throw ControlError.invalid_request}
    }
    func acknowledgeStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult {
        guard acceptsStopReceipt(receipt) else {return .uncertain}
        do {if case .stop(let value)=try request(id:id,operation:.lookupStop,receipt:receipt) {return value}}
        catch {}
        return .uncertain
    }
    func rejectedStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult {
        // Rejection on this side cannot prove non-dispatch on the custodian.
        acknowledgeStopResult(id:id,matching:receipt)
    }
    func cancelStopValidation(id:String,matching receipt:ServiceRecordedLaunch)->Bool {
        guard acceptsStopReceipt(receipt) else {return false}
        do {if case .stop(.notSent)=try request(id:id,operation:.cancelStop,receipt:receipt) {return true}}
        catch {}
        return false
    }
    private func exchange(_ body:Data)throws->Data {
        var directory=stat(),entry=stat()
        guard lstat(URL(fileURLWithPath:path).deletingLastPathComponent().path,&directory)==0,directory.st_mode&S_IFMT==S_IFDIR,
              directory.st_uid==geteuid(),directory.st_mode&0o7777==0o700,
              lstat(path,&entry)==0,entry.st_mode&S_IFMT==S_IFSOCK,entry.st_uid==geteuid(),entry.st_mode&0o7777==0o600 else {throw ControlError.unauthorized}
        let deadline=ProcessInfo.processInfo.systemUptime+2
        let fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else {throw ControlError.internal_error};defer {close(fd)}
        var noPipe:Int32=1
        guard fcntl(fd,F_SETFD,FD_CLOEXEC)==0,fcntl(fd,F_SETFL,O_NONBLOCK)==0,
              setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,socklen_t(MemoryLayout<Int32>.size))==0 else {throw ControlError.internal_error}
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) {$0.initializeMemory(as:UInt8.self,repeating:0);$0.copyBytes(from:Array(path.utf8))}
        let connected=withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1){connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        if connected != 0 {
            guard errno==EINPROGRESS else {throw ControlError.internal_error}
            var item=pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
            guard poll(&item,1,Int32(max(0,(deadline-ProcessInfo.processInfo.systemUptime)*1000)))>0 else {throw RuntimeError.deadline}
        }
        var error:Int32=0,size=socklen_t(MemoryLayout<Int32>.size),uid:uid_t=0,gid:gid_t=0,pid:Int32=0
        guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&size)==0,error==0,getpeereid(fd,&uid,&gid)==0,uid==geteuid(),uid>0 else {throw ControlError.unauthorized}
        size=socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&size)==0,size==MemoryLayout<Int32>.size,pid==peer.pid else {throw ControlError.unauthorized}
        _=try ServiceIdentity.verified(peer:peer,expectedUID:uid,deadline:deadline)
        try ControlFrames.write(fd:fd,data:body,deadline:deadline)
        guard shutdown(fd,SHUT_WR)==0 else {throw ControlError.internal_error}
        let reply=try ControlFrames.read(fd:fd,deadline:deadline,maximum:2048)
        // One complete reply only. Do not acknowledge a valid prefix with
        // trailing bytes/frames, even from an otherwise authenticated image.
        while true {
            let left=deadline-ProcessInfo.processInfo.systemUptime
            guard left>0 else {throw RuntimeError.deadline}
            var item=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            let count=poll(&item,1,Int32(min(100,max(1,left*1000))))
            if count<0,errno==EINTR {continue}
            if count==0 {continue}
            guard count>0,item.revents&Int16(POLLERR|POLLNVAL)==0 else {throw ControlError.invalid_request}
            var byte:UInt8=0
            let read=Darwin.read(fd,&byte,1)
            if read<0,[EINTR,EAGAIN,EWOULDBLOCK].contains(errno) {continue}
            guard read==0 else {throw ControlError.invalid_request};break
        }
        _=try ServiceIdentity.verified(peer:peer,expectedUID:uid,deadline:deadline)
        return reply
    }
}
