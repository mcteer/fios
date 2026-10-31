import Foundation
import Darwin

public enum ControlFrames {
    private static func ready(_ fd:Int32, events:Int16, deadline:TimeInterval) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw RuntimeError.deadline }
            var item = pollfd(fd:fd,events:events,revents:0)
            let result = poll(&item,1,Int32(min(remaining * 1000,2000)))
            if result < 0 && errno == EINTR { continue }
            guard result > 0, item.revents & Int16(POLLERR | POLLNVAL) == 0,
                  item.revents & events != 0 else { throw RuntimeError.deadline }
            return
        }
    }
    private static func exact(fd:Int32,count:Int,deadline:TimeInterval) throws -> Data {
        var result=Data()
        while result.count < count {
            try ready(fd,events:Int16(POLLIN),deadline:deadline)
            var buffer=[UInt8](repeating:0,count:min(4096,count-result.count))
            let n = Darwin.read(fd,&buffer,buffer.count)
            if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard n > 0 else { throw ControlError.invalid_request }
            result.append(contentsOf:buffer.prefix(n))
        }
        return result
    }
    public static func read(fd:Int32,deadline:TimeInterval,maximum:Int=65536) throws -> Data {
        let header=try exact(fd:fd,count:4,deadline:deadline)
        let count=header.reduce(0) { ($0 << 8) | Int($1) }
        guard (1...65536).contains(maximum),count > 0, count <= maximum else { throw ControlError.invalid_request }
        return try exact(fd:fd,count:count,deadline:deadline)
    }
    public static func write(fd:Int32,data:Data,deadline:TimeInterval) throws {
        guard !data.isEmpty, data.count <= 65_536 else { throw ControlError.invalid_request }
        let n=UInt32(data.count)
        var framed=Data([UInt8(n >> 24),UInt8((n >> 16) & 255),UInt8((n >> 8) & 255),UInt8(n & 255)])
        framed.append(data)
        var offset=0
        while offset < framed.count {
            try ready(fd,events:Int16(POLLOUT),deadline:deadline)
            let written=framed.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!.advanced(by:offset),framed.count-offset) }
            if written < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard written > 0 else { throw ControlError.internal_error }
            offset += written
        }
    }
}

public final class UnixControlSocket {
    public let fd:Int32
    private let path:String
    public init(path:String) throws {
        guard path.utf8.count < 104, path.hasPrefix("/"), !path.contains("\0") else { throw ControlError.invalid_request }
        let parent=URL(fileURLWithPath:path).deletingLastPathComponent().path
        var info=stat()
        guard lstat(parent,&info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw ControlError.unauthorized }
        // Do not unlink an existing socket until the caller owns the journal
        // single-instance lock; caller is responsible for acquiring it first.
        if lstat(path,&info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == geteuid() else { throw ControlError.unauthorized }
            guard unlink(path) == 0 else { throw ControlError.internal_error }
        }
        self.path=path
        fd=socket(AF_UNIX,SOCK_STREAM,0)
        guard fd >= 0 else { throw ControlError.internal_error }
        var address=sockaddr_un(); address.sun_family=sa_family_t(AF_UNIX)
        address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) { destination in
            destination.initializeMemory(as:UInt8.self,repeating:0)
            _ = path.utf8.withContiguousStorageIfAvailable { bytes in
                destination.copyBytes(from:UnsafeRawBufferPointer(bytes))
            }
        }
        let bound=withUnsafePointer(to:&address) {
            $0.withMemoryRebound(to:sockaddr.self,capacity:1) { bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path,0o600) == 0, listen(fd,16) == 0 else {
            close(fd); unlink(path); throw ControlError.internal_error
        }
        _ = fcntl(fd,F_SETFL,O_NONBLOCK)
    }
    deinit { close(fd); unlink(path) }
    public func acceptPeer() throws -> Int32? {
        let client=accept(fd,nil,nil)
        if client < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return nil }
        guard client >= 0 else { throw ControlError.internal_error }
        var uid:uid_t=0, gid:gid_t=0
        guard getpeereid(client,&uid,&gid) == 0, uid == geteuid() else {
            close(client); throw ControlError.unauthorized
        }
        var noSigPipe:Int32=1
        _ = setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&noSigPipe,socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(client,F_SETFD,FD_CLOEXEC)
        _ = fcntl(client,F_SETFL,O_NONBLOCK)
        return client
    }
}
