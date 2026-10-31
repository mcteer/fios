import Foundation
import Darwin
import CoreFoundation

enum DockerVMMetadataError:Error {case status,create,completion,socket,headers,transferEncoding,upgrade,length,object}
protocol DockerVMMetadataReading:Sendable {
    func inspect(id:String)throws->[String:Any]
    func read(id:String)throws->Data
}

// Fixed metadata-only Docker API, private UID-authenticated Unix transport.
// No caller command/path/HTTP method/body, shell, credentials, TCP or retries.
struct DockerVMMetadata:DockerVMMetadataReading {
    let socketPath:String
    let peerUID:uid_t
    let endpointPolicy:RuntimeEndpointPolicy?
    init(socketPath:String,peerUID:uid_t,endpointPolicy:RuntimeEndpointPolicy?=nil) {
        self.socketPath=socketPath;self.peerUID=peerUID;self.endpointPolicy=endpointPolicy
    }
    private static let files=["/proc/meminfo","/proc/self/mountinfo","/proc/self/status","/proc/sys/kernel/random/boot_id"]
    private func valid(_ id:String)->Bool {id.utf8.count==64 && id.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})}
    func inspect(id:String)throws->[String:Any] {
        guard valid(id) else {throw RuntimeError.identity}
        return try object(exchange(method:"GET",path:"/v1.47/containers/"+id+"/json",body:nil,stream:false))
    }
    func read(id:String)throws->Data {
        guard valid(id) else {throw RuntimeError.identity}
        let body=try JSONSerialization.data(withJSONObject:["AttachStdin":false,"AttachStdout":true,"AttachStderr":true,"Tty":false,
            "Privileged":false,"User":"65533:65533","WorkingDir":"/","Cmd":["/bin/cat"]+Self.files])
        let created=try object(exchange(method:"POST",path:"/v1.47/containers/"+id+"/exec",body:body,stream:false))
        guard Set(created.keys)==["Id"],let exec=created["Id"] as? String,valid(exec) else {throw DockerVMMetadataError.create}
        let start=try JSONSerialization.data(withJSONObject:["Detach":false,"Tty":false])
        let raw=try exchange(method:"POST",path:"/v1.47/exec/"+exec+"/start",body:start,stream:true)
        var multiplex=DockerMultiplex()
        let chunks=try multiplex.append(raw);try multiplex.finish()
        let data=chunks.reduce(into:Data()) {$0.append($1)}
        guard data.count<=32768 else {throw RuntimeError.outputLimit}
        let completed=try object(exchange(method:"GET",path:"/v1.47/exec/"+exec+"/json",body:nil,stream:false))
        func boolean(_ value:Any?,_ expected:Bool)->Bool {
            guard let number=value as? NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID() else {return false};return number.boolValue==expected
        }
        guard completed["ID"] as? String==exec,completed["ContainerID"] as? String==id,boolean(completed["Running"],false),
              let exit=completed["ExitCode"] as? NSNumber,CFGetTypeID(exit) != CFBooleanGetTypeID(),!["d","f"].contains(String(cString:exit.objCType)),exit.int64Value==0,
              let config=completed["ProcessConfig"] as? [String:Any],boolean(config["privileged"],false),boolean(config["tty"],false),
              config["user"] as? String=="65533:65533",config["entrypoint"] as? String=="/bin/cat",config["arguments"] as? [String]==Self.files else {throw DockerVMMetadataError.completion}
        return data
    }
    private func object(_ data:Data)throws->[String:Any] {
        try StrictJSON.validate(data,maximum:1<<20)
        guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw DockerVMMetadataError.object};return value
    }
    private func exchange(method:String,path:String,body:Data?,stream:Bool)throws->Data {
        let end=ProcessInfo.processInfo.systemUptime+1
        if let endpointPolicy {
            guard endpointPolicy.path==socketPath,endpointPolicy.uid==peerUID else {throw DockerVMMetadataError.socket}
        }
        let pinned=try endpointPolicy?.capture(deadline:end)
        let socketPath=pinned?.path ?? URL(fileURLWithPath:socketPath).resolvingSymlinksInPath().path
        var info=stat()
        guard socketPath.hasPrefix("/"),socketPath.utf8.count<104,lstat(socketPath,&info)==0,
              info.st_mode&S_IFMT==S_IFSOCK,info.st_uid==peerUID else {throw DockerVMMetadataError.socket}
        let fd=socket(AF_UNIX,SOCK_STREAM,0)
        guard fd>=0 else {throw RuntimeError.launch};defer{close(fd)}
        guard fcntl(fd,F_SETFL,O_NONBLOCK)>=0,fcntl(fd,F_SETFD,FD_CLOEXEC)>=0 else {throw RuntimeError.launch}
        var noPipe:Int32=1
        guard setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,socklen_t(MemoryLayout<Int32>.size))==0 else {throw RuntimeError.launch}
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) {$0.initializeMemory(as:UInt8.self,repeating:0);$0.copyBytes(from:Array(socketPath.utf8))}
        let connected=withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        guard connected==0 || errno==EINPROGRESS || errno==EAGAIN else {throw RuntimeError.launch}
        var peerIdentity:ServiceIdentity?
        var ready=connected==0,verified=false
        let bytes=body ?? Data()
        let version=stream ? "HTTP/1.1":"HTTP/1.0"
        let connection=stream ? "Connection: Upgrade\r\nUpgrade: tcp\r\n":"Connection: close\r\n"
        var request=Data((method+" "+path+" "+version+"\r\nHost: localhost\r\n"+connection+"Content-Type: application/json\r\nContent-Length: "+String(bytes.count)+"\r\n\r\n").utf8)
        request.append(bytes)
        var sent=0,response=Data()
        while ProcessInfo.processInfo.systemUptime<end {
            if !ready {
                var item=pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
                guard Darwin.poll(&item,1,0)>=0 else {throw RuntimeError.launch}
                if item.revents==0 {Thread.sleep(forTimeInterval:0.001);continue}
                var error:Int32=0,size=socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&size)==0,error==0 else {throw RuntimeError.launch};ready=true
            }
            if !verified {
                var uid:uid_t=0,gid:gid_t=0
                guard getpeereid(fd,&uid,&gid)==0,uid==peerUID else {throw DockerVMMetadataError.socket}
                peerIdentity=try endpointPolicy?.peer?.authenticate(fd:fd,deadline:end)
                try pinned?.verify(deadline:end);verified=true
            }
            if sent<request.count {
                let count=request.withUnsafeBytes {write(fd,$0.baseAddress!.advanced(by:sent),request.count-sent)}
                if count>0 {sent+=count}
                else if ![EAGAIN,EWOULDBLOCK,EINTR].contains(errno) {throw RuntimeError.launch}
            }
            var buffer=[UInt8](repeating:0,count:65536)
            let count=Darwin.read(fd,&buffer,buffer.count)
            if count>0 {
                guard response.count+count<=(1<<20)+8192 else {throw RuntimeError.outputLimit};response.append(contentsOf:buffer.prefix(count))
            }else if count==0 {
                guard sent==request.count else {throw RuntimeError.launch}
                let body=try Self.body(response,stream:stream)
                try pinned?.verify(deadline:end)
                if let expected=peerIdentity {
                    guard try endpointPolicy?.peer?.verifyIdentity(expected,deadline:end)==expected else {throw RuntimeError.identity}
                }
                return body
            }
            else if ![EAGAIN,EWOULDBLOCK,EINTR].contains(errno) {throw RuntimeError.launch}
            Thread.sleep(forTimeInterval:0.001)
        }
        throw RuntimeError.deadline
    }
    private static func chunks(_ body:Data)throws->Data {
        var offset=0,result=Data()
        while offset<body.count {
            guard let end=body.range(of:Data("\r\n".utf8),in:offset..<body.count),
                  (1...8).contains(end.lowerBound-offset),let size=String(data:body[offset..<end.lowerBound],encoding:.ascii),
                  size.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)||(65...70).contains($0)}),
                  let count=Int(size,radix:16) else {throw DockerVMMetadataError.length}
            offset=end.upperBound
            if count==0 {
                guard body.count-offset==2,body[offset...]==Data("\r\n".utf8) else {throw DockerVMMetadataError.length};return result
            }
            guard count<=1<<20,body.count-offset>=2,count<=body.count-offset-2,result.count+count<=1<<20,
                  body[(offset+count)..<(offset+count+2)]==Data("\r\n".utf8) else {throw DockerVMMetadataError.length}
            result.append(contentsOf:body[offset..<(offset+count)]);offset+=count+2
        }
        throw DockerVMMetadataError.length
    }
    static func body(_ data:Data,stream:Bool)throws->Data {
        guard let end=data.range(of:Data("\r\n\r\n".utf8)),end.upperBound<=8192,
              let text=String(data:data[..<end.lowerBound],encoding:.ascii) else {throw DockerVMMetadataError.headers}
        let lines=text.components(separatedBy:"\r\n"),status=lines[0].split(separator:" ")
        guard lines.count<=33,status.count>=2,["HTTP/1.0","HTTP/1.1"].contains(String(status[0])),
              (stream ? status[1]=="101" : ["200","201"].contains(String(status[1]))) else {throw DockerVMMetadataError.status}
        var fields:[String:String]=[:]
        for line in lines.dropFirst() {
            guard let colon=line.firstIndex(of:":") else {throw DockerVMMetadataError.headers}
            let key=line[..<colon].lowercased()
            guard !key.isEmpty,key.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||$0==45}),fields[key]==nil else {throw DockerVMMetadataError.headers}
            fields[key]=line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
        }
        let body=Data(data[end.upperBound...])
        if let transfer=fields["transfer-encoding"] {
            guard !stream,transfer.lowercased()=="chunked",fields["content-length"]==nil else {throw DockerVMMetadataError.transferEncoding}
            return try chunks(body)
        }
        if stream {
            guard fields["upgrade"]?.lowercased()=="tcp",fields["connection"]?.lowercased().split(separator:",").map({$0.trimmingCharacters(in:.whitespaces)}).contains("upgrade")==true,
                  fields["content-length"]==nil || fields["content-length"]=="0",body.count<=65536 else {throw DockerVMMetadataError.upgrade}
        }else if let length=fields["content-length"] {
            guard !length.isEmpty,length.utf8.allSatisfy({(48...57).contains($0)}),let count=Int(length),count==body.count else {throw DockerVMMetadataError.length}
        }
        guard body.count<=1<<20 else {throw RuntimeError.outputLimit};return body
    }
}
