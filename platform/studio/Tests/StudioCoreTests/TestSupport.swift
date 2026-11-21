import Foundation
import Darwin

// Test-only manually controlled clock: rollback is intentional input, not an
// alternate production clock or authority to refresh a real observation.
struct MockClock {
    private(set) var now:Int64
    init(_ value:Int64) {now=value}
    mutating func advance(_ delta:Int64) {
        let (next,overflow)=now.addingReportingOverflow(delta)
        precondition(!overflow,"Mock clock overflow")
        now=next
    }
}

func runMockSupportTests() throws {
    var clock=MockClock(1000),lease=try JobLease(created:1000)
    clock.advance(29999)
    guard lease.valid(now:clock.now) else {fatalError("Mock clock early expiry")}
    clock.advance(1)
    guard !lease.valid(now:clock.now) else {fatalError("Mock clock exact expiry ignored")}
    clock.advance(-1)
    guard !lease.valid(now:clock.now) else {fatalError("Mock clock rollback revived consumed lease")}

    // Fixed loopback discard endpoints, no DNS, no application payload or
    // configured native endpoint. The runner MUST deny IP outside its one
    // ephemeral mock endpoint; refused/unreachable is NOT guard success.
    func denied(_ family:Int32,_ address:UnsafePointer<sockaddr>,_ size:socklen_t) {
        let fd=Darwin.socket(family,SOCK_STREAM,0)
        if fd<0 {
            guard errno==EPERM || errno==EACCES else {fatalError("Mock IP guard unavailable")}
            return
        }
        defer {Darwin.close(fd)}
        guard fcntl(fd,F_SETFL,O_NONBLOCK)==0 else {fatalError("Mock socket nonblocking setup failed")}
        let result=Darwin.connect(fd,address,size),code=errno
        guard result == -1,(code==EPERM || code==EACCES) else {fatalError("Mock runner lacks kernel IP network denial")}
    }
    var ipv4=sockaddr_in()
    ipv4.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);ipv4.sin_family=sa_family_t(AF_INET);ipv4.sin_port=UInt16(9).bigEndian
    guard inet_pton(AF_INET,"127.0.0.1",&ipv4.sin_addr)==1 else {fatalError("Invalid fixed loopback fixture")}
    withUnsafePointer(to:&ipv4) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {denied(AF_INET,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
    var ipv6=sockaddr_in6()
    ipv6.sin6_len=UInt8(MemoryLayout<sockaddr_in6>.size);ipv6.sin6_family=sa_family_t(AF_INET6);ipv6.sin6_port=UInt16(9).bigEndian
    guard inet_pton(AF_INET6,"::1",&ipv6.sin6_addr)==1 else {fatalError("Invalid fixed IPv6 fixture")}
    withUnsafePointer(to:&ipv6) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {denied(AF_INET6,$0,socklen_t(MemoryLayout<sockaddr_in6>.size))}}
    print("PASS: shared manual clock and kernel-denied IPv4/IPv6 outside the finite mock endpoint (not merely absent listeners)")
}
