import Foundation
import Darwin

enum SessionClientOperation:String {case launch,lookup}

enum SessionReply {
    static func encode(id:String,service:ManagedService,instance:String,profile:String,result:SessionLaunchResult)throws->Data {
        var fields:[String:Any]=["version":1,"id":id,"service":service.rawValue,"instance":instance,"profile":profile]
        switch result {
        case .notSent:fields["status"]="not_sent"
        case .uncertain:fields["status"]="uncertain"
        case .wrongInstance:fields["status"]="wrong_instance"
        case .busy:fields["status"]="busy"
        case .started(let identity):
            fields["status"]="started";fields["pid"]=identity.pid
            fields["process_start"]=String(identity.start);fields["sha256"]=identity.sha256
        }
        let bytes=try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys])
        guard bytes.count<=2048 else {throw ControlError.internal_error};return bytes
    }
    static func decode(_ bytes:Data,id:String,service:ManagedService,instance:String,profile:String,expectedHash:String)throws->SessionLaunchResult {
        try StrictJSON.validate(bytes,maximum:2048)
        guard let fields=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              WireScalar.integer(fields["version"],maximum:1)==1,fields["id"] as? String==id,
              fields["service"] as? String==service.rawValue,fields["instance"] as? String==instance,
              fields["profile"] as? String==profile,let status=fields["status"] as? String else {throw ControlError.unauthorized}
        let base=Set(["version","id","service","instance","profile","status"])
        if status=="started" {
            guard Set(fields.keys)==base.union(["pid","process_start","sha256"]),
                  let pid=WireScalar.integer(fields["pid"],maximum:Int64(Int32.max)),pid>1,
                  let text=fields["process_start"] as? String,let start=UInt64(text),start>0,String(start)==text,
                  fields["sha256"] as? String==expectedHash else {throw ControlError.invalid_request}
            return .started(ServiceIdentity(pid:Int32(pid),start:start,sha256:expectedHash))
        }
        guard Set(fields.keys)==base else {throw ControlError.invalid_request}
        switch status {
        case "not_sent":return .notSent
        case "uncertain":return .uncertain
        case "wrong_instance":return .wrongInstance
        case "busy":return .busy
        default:throw ControlError.invalid_request
        }
    }
}

// Trusted constructor only. The deployed entry point is not enrolled/wired
// yet. Incoming PID/UID come exclusively from the accepted Unix connection.
final class SessionControlServer {
    private struct Connection {let pending:PendingControl;let peer:NativeControlPeer;let uid:uid_t}
    private let owner:SessionInstanceLock
    private var listener:UnixControlSocket?
    private let gate:SessionLaunchGate
    private let manager:VerifiedExecutable
    private var clients:[Connection]=[]
    init(directory:URL,manager:VerifiedExecutable,approvedHashes:[ManagedService:String])throws {
        owner=try SessionInstanceLock(directory:directory)
        self.manager=manager;gate=try SessionLaunchGate(manager:manager,approvedHashes:approvedHashes)
        listener=try UnixControlSocket(path:directory.appendingPathComponent("session-control.sock").path)
        let descriptor:[String:Any]=["version":1,"pid":getpid(),"uid":geteuid(),"process_start":try HostBoot.processStartIdentifier(pid:getpid()),
            "boot":try HostBoot.identity(),"instance":gate.instance,"profile":gate.profile]
        try AtomicState.write(JSONSerialization.data(withJSONObject:descriptor,options:[.sortedKeys]),to:directory.appendingPathComponent("session-control.json"))
    }
    deinit {
        for connection in clients {connection.pending.close()}
        listener=nil // Unlink only while still holding the session writer lock.
        owner.release()
    }
    func poll(consoleReady:Bool,now:Int64,launch:(ManagedService,String)throws->SessionLaunchResult)throws {
        guard let listener else {throw ControlError.internal_error}
        for _ in 0..<16 {
            guard let fd=try listener.acceptPeer() else {break}
            guard clients.count<16 else {close(fd);continue}
            var uid:uid_t=0,gid:gid_t=0,pid:Int32=0,length=socklen_t(MemoryLayout<Int32>.size)
            guard getpeereid(fd,&uid,&gid)==0,uid==geteuid(),uid>0,
                  getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&length)==0,length==MemoryLayout<Int32>.size,pid>1,
                  let start=try? WorkerResources.startIdentifier(pid:pid) else {close(fd);continue}
            clients.append(Connection(pending:PendingControl(fd:fd,role:.operator,now:ProcessInfo.processInfo.systemUptime,maximum:1024,requireEOF:true),
                peer:NativeControlPeer(pid:pid,start:start,executable:manager),uid:uid))
        }
        for connection in clients {
            do {
                if let data=try connection.pending.read(now:ProcessInfo.processInfo.systemUptime) {
                    let request=try SessionLaunchRequest(data)
                    let result=try gate.handle(data,peer:connection.peer,uid:connection.uid,consoleReady:consoleReady,now:now,launch:launch)
                    try connection.pending.respond(SessionReply.encode(id:request.id,service:request.service,instance:gate.instance,profile:gate.profile,result:result),now:ProcessInfo.processInfo.systemUptime)
                }
                try connection.pending.flush(now:ProcessInfo.processInfo.systemUptime)
            } catch {
                // No raw packet, path, profile, native exception or stdout.
                // Failure never becomes a non-dispatch acknowledgement.
                connection.pending.close()
            }
        }
        clients.removeAll(where:{$0.pending.closed})
    }
}

struct SessionControlClient {
    private let path:String
    private let peer:NativeControlPeer
    private let instance:String
    private let profile:String
    private let pins:[ManagedService:String]
    init(directory:URL,peer:NativeControlPeer,instance:String,profile:String,approvedHashes:[ManagedService:String])throws {
        guard WireScalar.uuid(instance),WireScalar.sha256(profile),Set(approvedHashes.keys)==Set(ManagedService.allCases),approvedHashes.values.allSatisfy(WireScalar.sha256) else {throw ControlError.invalid_request}
        path=directory.appendingPathComponent("session-control.sock").path
        self.peer=peer;self.instance=instance;self.profile=profile;pins=approvedHashes
    }
    func request(operation:SessionClientOperation,service:ManagedService,id:String)throws->SessionLaunchResult {
        guard WireScalar.uuid(id),path.utf8.count<104 else {throw ControlError.invalid_request}
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
        let body=try JSONSerialization.data(withJSONObject:["version":1,"id":id,"operation":operation.rawValue,"service":service.rawValue,"instance":instance,"profile":profile])
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
        guard try WorkerResources.startIdentifier(pid:peer.pid)==peer.start else {throw ControlError.unauthorized}
        return try SessionReply.decode(reply,id:id,service:service,instance:instance,profile:profile,expectedHash:pins[service]!)
    }
}
