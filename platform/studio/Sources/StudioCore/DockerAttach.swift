import Foundation
import Darwin

// Fixed owned-container attach only, over the enrolled local Unix daemon
// socket. No TCP, listener, subprocess, arbitrary HTTP path or sandbox socket.
final class DockerAttach {
    private var endpointPin:PinnedRuntimeEndpoint?
    private var fd:Int32 = -1
    private var connecting=false,upgraded=false,closed=false
    private let created:TimeInterval
    private let handshakeDeadline:TimeInterval
    private let request:Data
    private var requestOffset=0
    private var headers=Data(),outgoing=Data(),application=Data()
    private var multiplex=DockerMultiplex()
    private var totalSent=0
    private(set) var eof=false
    var ready:Bool { upgraded && !closed }
    var writableBytes:Int { max(0,(256<<10)-outgoing.count) }
    init(socketPath:String,configuration:SandboxConfiguration,savedID:String,peerUID:uid_t,now:TimeInterval,endpointPolicy:RuntimeEndpointPolicy?=nil) throws {
        guard now.isFinite,now>=0,savedID.count==64,savedID.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else { throw RuntimeError.invalid }
        created=now
        handshakeDeadline=min(now+2,ProcessInfo.processInfo.systemUptime+2)
        request=Data(("POST /v1.47/containers/"+savedID+"/attach?stdin=1&stdout=1&stderr=1&stream=1 HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: tcp\r\nContent-Length: 0\r\n\r\n").utf8)
        // Full container identity is verified by the executor/controller before
        // construction; configuration is a trusted recorded identity, not IPC.
        guard UUID(uuidString:configuration.job) != nil else { throw RuntimeError.identity }
        if let endpointPolicy {
            guard endpointPolicy.path==socketPath,endpointPolicy.uid==peerUID else {throw RuntimeError.identity}
        }
        guard ProcessInfo.processInfo.systemUptime<handshakeDeadline else {throw RuntimeError.deadline}
        endpointPin=try endpointPolicy?.capture(deadline:handshakeDeadline)
        let path=endpointPin?.path ?? URL(fileURLWithPath:socketPath).resolvingSymlinksInPath().path
        var info=stat()
        guard path.hasPrefix("/"),path.utf8.count<104,lstat(path,&info)==0,
              info.st_mode & S_IFMT==S_IFSOCK,info.st_uid==peerUID else { throw RuntimeError.identity }
        fd=socket(AF_UNIX,SOCK_STREAM,0)
        guard fd>=0 else { throw RuntimeError.launch }
        do {
            guard fcntl(fd,F_SETFL,O_NONBLOCK)>=0,fcntl(fd,F_SETFD,FD_CLOEXEC)>=0 else { throw RuntimeError.launch }
            var noPipe:Int32=1
            guard setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,socklen_t(MemoryLayout<Int32>.size))==0 else { throw RuntimeError.launch }
            var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
            withUnsafeMutableBytes(of:&address.sun_path) { target in
                target.initializeMemory(as:UInt8.self,repeating:0)
                target.copyBytes(from:Array(path.utf8))
            }
            let result=withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
            guard result==0 || errno==EINPROGRESS || errno==EAGAIN else { throw RuntimeError.launch }
            connecting=result != 0
            if !connecting { try verifyPeer(peerUID) }
            self.peerUID=peerUID
        } catch { Darwin.close(fd);fd = -1;throw error }
    }
    private var peerUID:uid_t=0
    private func verifyPeer(_ expected:uid_t) throws {
        var uid:uid_t=0,gid:gid_t=0
        guard getpeereid(fd,&uid,&gid)==0,uid==expected else { throw RuntimeError.identity }
        try endpointPin?.verify(deadline:handshakeDeadline)
        // The connected kernel socket now binds this peer. A later pathname
        // replacement cannot redirect the established data connection.
        endpointPin=nil
    }
    deinit { close() }
    func close() {
        if fd>=0 { Darwin.close(fd);fd = -1 };endpointPin=nil;closed=true
        headers.removeAll();outgoing.removeAll();application.removeAll()
    }
    func enqueue(_ frame:Data) throws {
        guard ready,!frame.isEmpty,frame.count<=65540,outgoing.count+frame.count<=256<<10,
              totalSent+frame.count<=16<<20 else { throw RuntimeError.outputLimit }
        outgoing.append(frame);totalSent+=frame.count
    }
    func poll(now:TimeInterval) throws -> [Data] {
        guard !closed,now.isFinite,now>=created,now-created<1800,
              upgraded || now-created<2,
              upgraded || ProcessInfo.processInfo.systemUptime<handshakeDeadline else { close();throw RuntimeError.deadline }
        do {
            if connecting {
                var item=pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
                guard Darwin.poll(&item,1,0)>=0 else { throw RuntimeError.launch }
                if item.revents==0 { return [] }
                var error:Int32=0,size=socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&size)==0,error==0 else { throw RuntimeError.launch }
                try verifyPeer(peerUID);connecting=false
            }
            if requestOffset<request.count {
                let count=request.withUnsafeBytes {Darwin.write(fd,$0.baseAddress!.advanced(by:requestOffset),request.count-requestOffset)}
                if count>0 { requestOffset+=count }
                else if errno != EAGAIN && errno != EINTR { throw RuntimeError.launch }
            } else if ready && !outgoing.isEmpty {
                let count=outgoing.withUnsafeBytes {Darwin.write(fd,$0.baseAddress!,min(outgoing.count,32768))}
                if count>0 { outgoing=Data(outgoing.dropFirst(count)) }
                else if errno != EAGAIN && errno != EINTR { throw RuntimeError.launch }
            }
            var bytes=[UInt8](repeating:0,count:65536)
            let count=Darwin.read(fd,&bytes,bytes.count)
            if count<0 && [EAGAIN,EWOULDBLOCK,EINTR].contains(errno) { return [] }
            guard count>=0 else { throw RuntimeError.launch }
            if count==0 {
                guard upgraded else { throw RuntimeError.launch }
                try multiplex.finish();guard application.isEmpty else { throw DockerStreamError.invalid }
                eof=true;close();return []
            }
            var data=Data(bytes.prefix(count))
            if !upgraded {
                headers.append(data)
                guard let end=headers.range(of:Data("\r\n\r\n".utf8)) else {
                    guard headers.count<=8192 else { throw RuntimeError.outputLimit };return []
                }
                guard end.upperBound<=8192,let text=String(data:headers[..<end.lowerBound],encoding:.ascii),
                      text.hasPrefix("HTTP/1.1 101 ") else { throw RuntimeError.identity }
                let lines=text.components(separatedBy:"\r\n")
                guard lines.count<=33 else { throw RuntimeError.identity }
                var fields:[String:String]=[:]
                for line in lines.dropFirst() {
                    guard let colon=line.firstIndex(of:":") else { throw RuntimeError.identity }
                    let key=line[..<colon].lowercased()
                    guard !key.isEmpty,key.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||$0==45}),fields[key]==nil else { throw RuntimeError.identity }
                    fields[key]=line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces).lowercased()
                }
                guard fields["upgrade"]=="tcp",fields["connection"]?.split(separator:",").map({$0.trimmingCharacters(in:.whitespaces)}).contains("upgrade")==true,
                      fields["transfer-encoding"]==nil else { throw RuntimeError.identity }
                data=Data(headers[end.upperBound...]);headers.removeAll();upgraded=true
            }
            var result:[Data]=[]
            for payload in try multiplex.append(data) {
                guard application.count+payload.count<=131080 else { throw RuntimeError.outputLimit }
                application.append(payload)
                while application.count>=4 {
                    let length=application.prefix(4).reduce(0) {($0<<8)|Int($1)}
                    guard (1...65536).contains(length) else { throw DockerStreamError.invalid }
                    guard application.count>=length+4 else { break }
                    let frame=Data(application[4..<length+4])
                    try StrictJSON.validate(frame,maximum:65536)
                    result.append(frame);application=Data(application.dropFirst(length+4))
                }
            }
            return result
        } catch { close();throw error }
    }
}
