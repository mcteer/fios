import Foundation
import Darwin

enum ServiceHealthState:Equatable {case healthy,loading,waitingCredentials,unavailable}

// Bounded read-only metadata, NOT absence/identity/native-idle evidence. No
// prompts, API keys, redirects, cookies, proxies, DNS or model requests.
enum ServiceHealthWire {
    static let maximum=8192+16384
    static func decode(_ input:Data)->ServiceHealthState {
        let data=Data(input)
        guard data.count<=maximum,let boundary=data.range(of:Data([13,10,13,10])),boundary.lowerBound<=8192 else {return .unavailable}
        let head=data.prefix(boundary.lowerBound)
        guard head.allSatisfy({$0==9 || $0==10 || $0==13 || (32...126).contains($0)}),
              let text=String(data:head,encoding:.ascii) else {return .unavailable}
        let lines=text.components(separatedBy:"\r\n")
        guard let first=lines.first else {return .unavailable}
        let status=first.split(separator:" ",omittingEmptySubsequences:false)
        guard status.count>=3,["HTTP/1.0","HTTP/1.1"].contains(status[0]),status[1].count==3,
              let code=Int(status[1]),(100...599).contains(code) else {return .unavailable}
        var headers:[String:String]=[:]
        for line in lines.dropFirst() {
            guard let colon=line.firstIndex(of:":") else {return .unavailable}
            let key=String(line[..<colon]).lowercased()
            guard !key.isEmpty,key.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||$0==45}),headers[key]==nil else {return .unavailable}
            headers[key]=line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
        }
        guard headers["transfer-encoding"]==nil,let declared=headers["content-length"],
              let length=Int(declared),length>=0,length<=16384,String(length)==declared,
              data.count-boundary.upperBound==length else {return .unavailable}
        if code==401 || code==403 {return .waitingCredentials}
        guard code==200 || code==503,
              headers["content-type"]?.split(separator:";").first?.trimmingCharacters(in:.whitespaces).lowercased()=="application/json" else {return .unavailable}
        let body=Data(data.suffix(length))
        guard (try? StrictJSON.validate(body,maximum:16384)) != nil,
              let fields=(try? JSONSerialization.jsonObject(with:body)) as? [String:Any],Set(fields.keys)==Set(["status"]),
              let value=fields["status"] as? String else {return .unavailable}
        if code==200 && value=="ok" {return .healthy}
        if code==503 && value=="loading" {return .loading}
        return .unavailable
    }
}

struct ServiceHealthProbe {
    private let port:Int
    // Internal trusted enrollment/test configuration only. No IPC-selected
    // endpoint or URL. Production route is the fixed local MLX health port;
    // finite ephemeral ports exist solely for kernel-restricted source mocks.
    init(port:Int=11234) throws {
        guard port==11234 || (49152...65535).contains(port) else {throw RuntimeError.invalid}
        self.port=port
    }
    func probe()->ServiceHealthState {
        do {return ServiceHealthWire.decode(try read())}catch{return .unavailable}
    }
    private func read() throws -> Data {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        let fd=socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else {throw RuntimeError.launch};defer {Darwin.close(fd)}
        var noSigPipe:Int32=1
        guard fcntl(fd,F_SETFD,FD_CLOEXEC)==0,fcntl(fd,F_SETFL,O_NONBLOCK)==0,
              setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSigPipe,socklen_t(MemoryLayout<Int32>.size))==0 else {throw RuntimeError.launch}
        func ready(_ events:Int16) throws {
            while true {
                let left=deadline-ProcessInfo.processInfo.systemUptime
                guard left>0 else {throw RuntimeError.deadline}
                var item=pollfd(fd:fd,events:events,revents:0)
                let count=poll(&item,1,Int32(max(1,min(100,left*1000))))
                if count<0 && errno==EINTR {continue}
                if count==0 {continue}
                guard count>0,item.revents&Int16(POLLERR|POLLNVAL)==0,
                      item.revents&Int16(events|Int16(POLLHUP)) != 0 else {throw RuntimeError.launch};return
            }
        }
        var address=sockaddr_in();address.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family=sa_family_t(AF_INET);address.sin_port=UInt16(port).bigEndian
        address.sin_addr=in_addr(s_addr:inet_addr("127.0.0.1"))
        let connected=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
        if connected != 0 {guard errno==EINPROGRESS else {throw RuntimeError.launch};try ready(Int16(POLLOUT))}
        var code:Int32=0,size=socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&code,&size)==0,code==0 else {throw RuntimeError.launch}
        let request=Data("GET /health HTTP/1.0\r\nHost: 127.0.0.1:\(port)\r\nAccept: application/json\r\nConnection: close\r\n\r\n".utf8)
        var offset=0
        while offset<request.count {
            try ready(Int16(POLLOUT))
            let count=request.withUnsafeBytes{Darwin.write(fd,$0.baseAddress!.advanced(by:offset),request.count-offset)}
            if count<0 && (errno==EINTR || errno==EAGAIN) {continue}
            guard count>0 else {throw RuntimeError.launch};offset+=count
        }
        var output=Data()
        while true {
            try ready(Int16(POLLIN));var bytes=[UInt8](repeating:0,count:4096)
            let count=Darwin.read(fd,&bytes,bytes.count)
            if count<0 && (errno==EINTR || errno==EAGAIN) {continue}
            guard count>=0 else {throw RuntimeError.launch};if count==0 {return output}
            guard output.count+count<=ServiceHealthWire.maximum else {throw RuntimeError.outputLimit}
            output.append(contentsOf:bytes.prefix(count))
        }
    }
}
