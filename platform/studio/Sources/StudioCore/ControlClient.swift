import Foundation
import Darwin

public enum ControlClient {
    public static func request(path:String,operation:ControlOperation,payload:[String:Any] = [:]) throws -> [String:Any] {
        guard path.hasPrefix("/"), path.utf8.count < 104, !path.contains("\0") else { throw ControlError.invalid_request }
        let fd=socket(AF_UNIX,SOCK_STREAM,0)
        guard fd >= 0 else { throw ControlError.internal_error }; defer { close(fd) }
        var noSigPipe:Int32=1
        _ = setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSigPipe,socklen_t(MemoryLayout<Int32>.size))
        var address=sockaddr_un(); address.sun_family=sa_family_t(AF_UNIX); address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) { destination in
            destination.initializeMemory(as:UInt8.self,repeating:0)
            _ = path.utf8.withContiguousStorageIfAvailable { destination.copyBytes(from:UnsafeRawBufferPointer($0)) }
        }
        let connected=withUnsafePointer(to:&address) {
            $0.withMemoryRebound(to:sockaddr.self,capacity:1) { connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw ControlError.internal_error }
        var uid:uid_t=0, gid:gid_t=0
        guard getpeereid(fd,&uid,&gid) == 0, uid == geteuid() else { throw ControlError.unauthorized }
        _ = fcntl(fd,F_SETFL,O_NONBLOCK)
        let id=UUID().uuidString.lowercased()
        let data=try JSONSerialization.data(withJSONObject:["version":1,"id":id,"operation":operation.rawValue,"payload":payload])
        let deadline=ProcessInfo.processInfo.systemUptime + 2
        try ControlFrames.write(fd:fd,data:data,deadline:deadline)
        let received=try ControlFrames.read(fd:fd,deadline:deadline)
        try StrictJSON.validate(received,maximum:65_536)
        guard let response=try JSONSerialization.jsonObject(with:received) as? [String:Any] else { throw ControlError.invalid_request }
        if response["ok"] as? Bool == true { guard response["id"] as? String == id else { throw ControlError.invalid_request } }
        return response
    }
}
