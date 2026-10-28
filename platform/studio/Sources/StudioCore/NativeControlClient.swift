import Foundation
import Darwin
import CryptoKit

enum NativeControlError:Error,Sendable {case invalid,unauthorized,deadline,unavailable}
enum NativeControlOperation:UInt8,Sendable {case observe,pause,resume,ownerBarrier}
enum NativeOwnerStreamOutcome:UInt8,Sendable {case notRequested,ownerStreamsSynchronized,blocked,wrongOwner,streamsChanged,failed,timedOut}
enum NativeControlStatus:UInt8,Sendable {case ok,invalid,maintenance,wrongInstance}
// Not Codable and deliberately not NativeSnapshot. Connection counters and an
// ingress fence do not establish registry/device terminal or all-client idle.
struct NativeIngressStatus:Sendable {
    let operation:NativeControlOperation
    let status:NativeControlStatus
    let instance:String
    let pauseSequence:UInt64
    let owners:Int
    let ingress:Int
    let preparing:Int
    let active:Int
    let responding:Int
    let modelIdentities:Int
    let closed:Bool
    let uncertain:Bool
    var ownerStreamOutcome:NativeOwnerStreamOutcome = .notRequested
    var synchronizedStreams:UInt32 = 0
    var activity:HostActivity {.unknown}
}
enum NativeControlWire {
    static func instanceBytes(_ value:String) throws -> [UInt8] {
        let bytes=Array(value.utf8)
        guard bytes.count==32,bytes.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),bytes.contains(where:{$0 != 48}) else {throw NativeControlError.invalid}
        func nibble(_ b:UInt8)->UInt8 {b<=57 ? b-48:b-87}
        return stride(from:0,to:32,by:2).map {nibble(bytes[$0])*16+nibble(bytes[$0+1])}
    }
    static func request(operation:NativeControlOperation,instance:String?,sequence:UInt64) throws -> Data {
        guard (operation == .resume || operation == .ownerBarrier ? sequence>0:sequence==0) else {throw NativeControlError.invalid}
        var bytes=Data(repeating:0,count:32)
        bytes.replaceSubrange(0..<4,with:Data("FIC9".utf8));bytes[4]=2;bytes[5]=operation.rawValue
        for index in 0..<8 {bytes[8+index]=UInt8(truncatingIfNeeded:sequence >> (56-index*8))}
        if let instance {bytes.replaceSubrange(16..<32,with:try instanceBytes(instance))}
        else if operation != .observe {throw NativeControlError.invalid}
        return bytes
    }
    static func reply(_ input:Data) throws -> NativeIngressStatus {
        guard input.count==64 else {throw NativeControlError.invalid}
        // Data slices/removeFirst retain nonzero indices. Rebase the bounded
        // frame before numeric indexing; malformed backing offsets must not trap.
        let bytes=Array(input)
        guard bytes.prefix(4).elementsEqual("FIR9".utf8),bytes[4]==2,bytes[7]==0,
              let operation=NativeControlOperation(rawValue:bytes[5]),let status=NativeControlStatus(rawValue:bytes[6]),
              bytes[56]<=1,bytes[57]<=1,let ownerOutcome=NativeOwnerStreamOutcome(rawValue:bytes[58]),bytes[59]==0 else {throw NativeControlError.invalid}
        let instance=bytes[8..<24].map {String(format:"%02x",$0)}.joined()
        _ = try instanceBytes(instance)
        func number(_ start:Int,_ count:Int)->UInt64 {bytes[start..<start+count].reduce(0){($0<<8)|UInt64($1)}}
        let sequence=number(24,8),values=stride(from:32,to:56,by:4).map {Int(number($0,4))}
        guard values[0]<=256,values[1...4].allSatisfy({$0<=256}),values[5]<=64,
              values[0]==values[1...4].reduce(0,+),
              (bytes[56]==1 ? sequence>0:sequence==0) else {throw NativeControlError.invalid}
        let streams=number(60,4)
        guard streams<=256,(ownerOutcome == .ownerStreamsSynchronized || streams==0),
              operation == .ownerBarrier || ownerOutcome == .notRequested,
              operation != .ownerBarrier || status != .ok || ownerOutcome != .notRequested,
              status == .ok || ownerOutcome == .notRequested,
              ownerOutcome != .ownerStreamsSynchronized || (bytes[56]==1 && sequence>0 && values[0]==0 && bytes[57]==0) else {throw NativeControlError.invalid}
        var result=NativeIngressStatus(operation:operation,status:status,instance:instance,pauseSequence:sequence,owners:values[0],ingress:values[1],preparing:values[2],active:values[3],responding:values[4],modelIdentities:values[5],closed:bytes[56]==1,uncertain:bytes[57]==1)
        result.ownerStreamOutcome=ownerOutcome;result.synchronizedStreams=UInt32(streams)
        return result
    }
}

// Only reviewed native enrollment constructs this peer. No model/control wire
// accepts a PID, start identity, executable path or management socket path.
struct NativeControlPeer:Sendable {
    let pid:Int32
    let start:UInt64
    let executable:VerifiedExecutable
    func verify(deadline:TimeInterval) throws {
        guard pid>1,!executable.path.contains("\0"),try WorkerResources.startIdentifier(pid:pid)==start else {throw NativeControlError.unauthorized}
        var path=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(pid,&path,UInt32(path.count))>0,
              path.prefix(while:{$0 != 0}).map({UInt8(bitPattern:$0)})==Array(executable.path.utf8) else {throw NativeControlError.unauthorized}
        let fd=open(executable.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard fd>=0 else {throw NativeControlError.unauthorized};defer {close(fd)}
        var before=stat(),after=stat()
        guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_mode&0o6022==0,
              before.st_uid==0 || before.st_uid==geteuid(),before.st_nlink==1,before.st_size>0,before.st_size<=512<<20 else {throw NativeControlError.unauthorized}
        var hash=SHA256(),buffer=[UInt8](repeating:0,count:32768),total:Int64=0
        while true {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw NativeControlError.deadline}
            let count=Darwin.read(fd,&buffer,buffer.count)
            if count<0 && errno==EINTR {continue}
            guard count>=0 else {throw NativeControlError.unauthorized};if count==0 {break}
            total+=Int64(count);guard total<=before.st_size else {throw NativeControlError.unauthorized}
            hash.update(data:Data(buffer.prefix(count)))
        }
        var current=stat()
        guard proc_pidpath(pid,&path,UInt32(path.count))>0,path.prefix(while:{$0 != 0}).map({UInt8(bitPattern:$0)})==Array(executable.path.utf8),
              lstat(executable.path,&current)==0,current.st_dev==before.st_dev,current.st_ino==before.st_ino,
              total==before.st_size,fstat(fd,&after)==0,before.st_dev==after.st_dev,before.st_ino==after.st_ino,
              before.st_size==after.st_size,before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
              hash.finalize().map({String(format:"%02x",$0)}).joined()==executable.sha256,
              try WorkerResources.startIdentifier(pid:pid)==start else {throw NativeControlError.unauthorized}
    }
}

struct NativeControlClient:Sendable {
    let path:String
    let peer:NativeControlPeer
    func request(operation:NativeControlOperation,instance:String?=nil,sequence:UInt64=0) throws -> NativeIngressStatus {
        let data=try NativeControlWire.request(operation:operation,instance:instance,sequence:sequence)
        guard path.hasPrefix("/"),path.utf8.count<104,!path.contains("\0") else {throw NativeControlError.invalid}
        var parent=stat(),socketInfo=stat()
        let directory=URL(fileURLWithPath:path).deletingLastPathComponent().path
        guard lstat(directory,&parent)==0,parent.st_mode&S_IFMT==S_IFDIR,parent.st_uid==geteuid(),parent.st_mode&0o777==0o700,
              lstat(path,&socketInfo)==0,socketInfo.st_mode&S_IFMT==S_IFSOCK,socketInfo.st_uid==geteuid(),socketInfo.st_mode&0o777==0o600 else {throw NativeControlError.unauthorized}
        let deadline=ProcessInfo.processInfo.systemUptime+2
        let fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else {throw NativeControlError.unavailable};defer {close(fd)}
        var noSigPipe:Int32=1
        guard fcntl(fd,F_SETFD,FD_CLOEXEC)==0,fcntl(fd,F_SETFL,O_NONBLOCK)==0,
              setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSigPipe,socklen_t(MemoryLayout<Int32>.size))==0 else {throw NativeControlError.unavailable}
        func ready(_ events:Int16) throws {
            while true {
                let left=deadline-ProcessInfo.processInfo.systemUptime;guard left>0 else {throw NativeControlError.deadline}
                var pollItem=pollfd(fd:fd,events:events,revents:0)
                let result=poll(&pollItem,1,Int32(min(100,left*1000)))
                if result<0 && errno==EINTR {continue}
                if result==0 {continue}
                guard result>0,pollItem.revents&Int16(POLLNVAL|POLLERR)==0,
                      pollItem.revents&Int16(events|Int16(POLLHUP)) != 0 else {throw NativeControlError.unavailable};return
            }
        }
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) {destination in destination.initializeMemory(as:UInt8.self,repeating:0);destination.copyBytes(from:Array(path.utf8))}
        let connected=withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1){connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        if connected != 0 {guard errno==EINPROGRESS else {throw NativeControlError.unavailable};try ready(Int16(POLLOUT))}
        var code:Int32=0,length=socklen_t(MemoryLayout<Int32>.size),uid:uid_t=0,gid:gid_t=0,pid:Int32=0
        guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&code,&length)==0,code==0,getpeereid(fd,&uid,&gid)==0,uid==geteuid() else {throw NativeControlError.unauthorized}
        length=socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&length)==0,length==MemoryLayout<Int32>.size,pid==peer.pid else {throw NativeControlError.unauthorized}
        try peer.verify(deadline:deadline) // Authenticate before sending an action.
        var offset=0
        while offset<data.count {
            try ready(Int16(POLLOUT))
            let count=data.withUnsafeBytes {Darwin.write(fd,$0.baseAddress!.advanced(by:offset),data.count-offset)}
            if count<0 && (errno==EINTR || errno==EAGAIN) {continue}
            guard count>0 else {throw NativeControlError.unavailable};offset+=count
        }
        guard shutdown(fd,SHUT_WR)==0 else {throw NativeControlError.unavailable}
        var output=Data()
        while true {
            try ready(Int16(POLLIN));var buffer=[UInt8](repeating:0,count:65-output.count)
            let count=Darwin.read(fd,&buffer,buffer.count)
            if count<0 && (errno==EINTR || errno==EAGAIN) {continue}
            guard count>=0 else {throw NativeControlError.unavailable};if count==0 {break}
            output.append(contentsOf:buffer.prefix(count));guard output.count<=64 else {throw NativeControlError.invalid}
        }
        guard try WorkerResources.startIdentifier(pid:peer.pid)==peer.start else {throw NativeControlError.unauthorized}
        let value=try NativeControlWire.reply(output)
        guard value.operation==operation,instance==nil || value.instance==instance else {throw NativeControlError.unauthorized}
        return value
    }
}
