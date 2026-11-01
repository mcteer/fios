import Foundation
import Darwin

// Private module of the existing supervisor, never a separate host helper.
// Source-only constructor; public supervisor startup supplies no native ports.
final class ServingCustodyServer:@unchecked Sendable {
    private struct Connection {let id:String;let pending:PendingControl;let peer:NativeControlPeer;let uid:uid_t}
    private struct Completion {let id:String;let reply:Data?}
    private let owner:PrivateWriterLock
    private var listener:UnixControlSocket?
    private let gate:ServingCustodyGate
    private let manager:VerifiedExecutable
    private let imageSHA256:String
    private var clients:[Connection]=[]
    private let worker=NSLock()
    private var busy=false
    private var completion:Completion?
    var instance:String {gate.instance}
    var profile:String {gate.profile}
    init(directory:URL,runtime:any ServingProcessControlling,manager:VerifiedExecutable,imageSHA256:String)throws {
        owner=try PrivateWriterLock(directory:directory,kind:.servingCustody)
        gate=try ServingCustodyGate(runtime:runtime,manager:manager,imageSHA256:imageSHA256)
        self.manager=manager;self.imageSHA256=imageSHA256
        listener=try UnixControlSocket(path:directory.appendingPathComponent("serving-custody.sock").path)
        let descriptor:[String:Any]=["version":1,"purpose":"native_serving_custody","pid":getpid(),"uid":geteuid(),
            "process_start":try HostBoot.processStartIdentifier(pid:getpid()),"boot":try HostBoot.identity(),"instance":gate.instance,"profile":gate.profile]
        try AtomicState.write(JSONSerialization.data(withJSONObject:descriptor,options:[.sortedKeys]),to:directory.appendingPathComponent("serving-custody.json"))
    }
    deinit {
        for connection in clients {connection.pending.close()}
        listener=nil;owner.release()
        // No child signal/reap or native uncertainty reset on socket teardown.
    }
    func bindManager(_ peer:NativeControlPeer?)throws {try gate.bindManager(peer)}
    func acceptsManager(at url:URL)->Bool {url.path==manager.path}
    // Existing supervisor child object only; no packet can choose this PID.
    // Kernel/image authentication still occurs independently off-loop per RPC.
    func bindSupervisedManager(_ process:Process?)throws {
        guard let process else {try gate.bindManager(nil);return}
        guard process.isRunning,let start=try? WorkerResources.startIdentifier(pid:process.processIdentifier) else {try gate.bindManager(nil);return}
        var path=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(process.processIdentifier,&path,UInt32(path.count))>0,
              String(bytes:path.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8)==manager.path else {throw ControlError.unauthorized}
        try gate.bindManager(NativeControlPeer(pid:process.processIdentifier,start:start,executable:manager))
    }

    private var available:Bool {worker.lock();defer {worker.unlock()};return !busy && completion==nil}
    private func takeCompletion()->Completion? {worker.lock();defer {worker.unlock()};let result=completion;completion=nil;return result}
    private func submit(_ command:ServingCustodyCommand,connection:Connection)throws {
        worker.lock()
        guard !busy,completion==nil else {worker.unlock();throw RuntimeError.capacity}
        busy=true;worker.unlock()
        let id=connection.id,peer=connection.peer,uid=connection.uid
        Thread.detachNewThread { [self] in
            var reply:Data?
            autoreleasepool {
                do {reply=try ServingCustodyReply.encode(command:command,value:gate.handle(command,peer:peer,uid:uid))}
                catch {reply=nil} // Never turn transport/identity failure into non-dispatch.
            }
            worker.lock();completion=Completion(id:id,reply:reply);busy=false;worker.unlock()
        }
    }
    // Nonblocking framing/flush only. One retained off-loop identity/action
    // exchange; at most16 finite clients and no unbounded work queue.
    func poll()throws {
        guard let listener else {throw ControlError.internal_error}
        if let completed=takeCompletion(),let connection=clients.first(where:{$0.id==completed.id}) {
            if let reply=completed.reply {
                do {try connection.pending.respond(reply,now:ProcessInfo.processInfo.systemUptime)} catch {connection.pending.close()}
            } else {connection.pending.close()}
        }
        for _ in 0..<16 {
            let accepted:Int32?
            do {accepted=try listener.acceptPeer()} catch ControlError.unauthorized {continue}
            guard let fd=accepted else {break}
            guard clients.count<16 else {close(fd);continue}
            var uid:uid_t=0,gid:gid_t=0,pid:Int32=0,length=socklen_t(MemoryLayout<Int32>.size)
            guard getpeereid(fd,&uid,&gid)==0,uid==geteuid(),uid>0,
                  getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&length)==0,length==MemoryLayout<Int32>.size,pid>1,
                  let start=try? WorkerResources.startIdentifier(pid:pid) else {close(fd);continue}
            clients.append(Connection(id:UUID().uuidString.lowercased(),pending:PendingControl(fd:fd,role:.operator,now:ProcessInfo.processInfo.systemUptime,maximum:2048,requireEOF:true),
                peer:NativeControlPeer(pid:pid,start:start,executable:manager),uid:uid))
        }
        for connection in clients {
            do {
                if available,let bytes=try connection.pending.read(now:ProcessInfo.processInfo.systemUptime) {
                    let command=try ServingCustodyCommand(bytes,expectedSHA256:imageSHA256)
                    try submit(command,connection:connection)
                }
                try connection.pending.flush(now:ProcessInfo.processInfo.systemUptime)
            } catch {connection.pending.close()}
        }
        clients.removeAll(where:{$0.pending.closed})
    }
}
