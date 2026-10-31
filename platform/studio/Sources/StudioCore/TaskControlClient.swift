import Foundation
import Darwin

public enum TaskControlClient {
    // Finite raw JSON on stdin; credentials are never argv, environment or an
    // error string. The task socket/role cannot be selected by request data.
    public static func request(directory:URL,inputFD:Int32=STDIN_FILENO) throws -> [String:Any] {
        let flags=fcntl(inputFD,F_GETFL)
        guard flags>=0,fcntl(inputFD,F_SETFL,flags|O_NONBLOCK)>=0 else {throw ControlError.invalid_request}
        defer {_=fcntl(inputFD,F_SETFL,flags)}
        let deadline=ProcessInfo.processInfo.systemUptime+2
        var data=Data(),ended=false
        while !ended {
            let remaining=deadline-ProcessInfo.processInfo.systemUptime
            guard remaining>0 else {throw RuntimeError.deadline}
            var item=pollfd(fd:inputFD,events:Int16(POLLIN),revents:0)
            let result=Darwin.poll(&item,1,Int32(min(remaining*1000,100)))
            if result<0 && errno==EINTR {continue}
            guard result>=0 else {throw ControlError.invalid_request}
            if result==0 {continue}
            var bytes=[UInt8](repeating:0,count:4096)
            let count=Darwin.read(inputFD,&bytes,bytes.count)
            if count<0 && [EINTR,EAGAIN,EWOULDBLOCK].contains(errno) {continue}
            guard count>=0,data.count+max(0,count)<=65536 else {throw ControlError.invalid_request}
            if count==0 {ended=true}else {data.append(contentsOf:bytes.prefix(count))}
        }
        let request=try ControlRequest.decode(data)
        guard ControlRole.task.allows(request.operation) else {throw ControlError.unauthorized}
        return try ControlClient.request(path:directory.appendingPathComponent("task.sock").path,operation:request.operation,payload:request.payload)
    }
}
