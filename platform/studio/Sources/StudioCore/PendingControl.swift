import Foundation
import Darwin

// One finite authenticated request/response, progressed without waiting on a
// client. This must never block the manager's heartbeat/resource/reap cycle.
final class PendingControl {
    let role:ControlRole
    private var fd:Int32
    private let deadline:TimeInterval
    private var input=Data(),output=Data()
    private var expected:Int?
    private var processed=false
    private var offset=0
    private(set) var closed=false
    init(fd:Int32,role:ControlRole,now:TimeInterval) {
        self.fd=fd;self.role=role;deadline=now+2
    }
    deinit { close() }
    func close() { if !closed { closed=true;Darwin.close(fd);fd = -1 };input.removeAll();output.removeAll() }
    private func check(_ now:TimeInterval) throws {
        guard !closed,now.isFinite,now<deadline,now>=deadline-2 else { close();throw RuntimeError.deadline }
    }
    func read(now:TimeInterval) throws -> Data? {
        try check(now)
        guard !processed else { return nil }
        var bytes=[UInt8](repeating:0,count:4096)
        let remaining=(expected.map {$0+4} ?? 4)-input.count
        let count=Darwin.read(fd,&bytes,min(bytes.count,remaining+1))
        if count<0 && [EAGAIN,EWOULDBLOCK,EINTR].contains(errno) { return nil }
        guard count>0 else { close();throw ControlError.invalid_request }
        input.append(contentsOf:bytes.prefix(count))
        if expected==nil && input.count>=4 {
            let size=input.prefix(4).reduce(0) { ($0<<8)|Int($1) }
            guard (1...65536).contains(size) else { close();throw ControlError.invalid_request }
            expected=size
        }
        if let expected {
            guard input.count<=expected+4 else { close();throw ControlError.invalid_request }
            if input.count==expected+4 {
                processed=true
                let result=Data(input.dropFirst(4));input.removeAll()
                return result
            }
        }
        return nil
    }
    func respond(_ data:Data,now:TimeInterval) throws {
        try check(now)
        guard processed,output.isEmpty,!data.isEmpty,data.count<=65536 else { close();throw ControlError.invalid_request }
        let count=UInt32(data.count)
        output=Data([UInt8(count>>24),UInt8((count>>16)&255),UInt8((count>>8)&255),UInt8(count&255)])
        output.append(data)
    }
    func flush(now:TimeInterval) throws {
        try check(now)
        guard !output.isEmpty else { return }
        let count=output.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!.advanced(by:offset),min(4096,output.count-offset)) }
        if count<0 && [EAGAIN,EWOULDBLOCK,EINTR].contains(errno) { return }
        guard count>0 else { close();throw ControlError.internal_error }
        offset+=count
        if offset==output.count { close() }
    }
}
