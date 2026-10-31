import Foundation
import Darwin

func runFramingTests() throws {
    var fds = [Int32](repeating:0,count:2)
    guard socketpair(AF_UNIX,SOCK_STREAM,0,&fds) == 0 else { throw ControlError.internal_error }
    defer { close(fds[0]); close(fds[1]) }
    try ControlFrames.write(fd:fds[0],data:Data("hello".utf8),deadline:ProcessInfo.processInfo.systemUptime + 1)
    let decoded = try ControlFrames.read(fd:fds[1],deadline:ProcessInfo.processInfo.systemUptime + 1)
    precondition(decoded == Data("hello".utf8))
    let oversized = [UInt8](repeating:255,count:4)
    _ = oversized.withUnsafeBytes { Darwin.write(fds[0],$0.baseAddress,4) }
    do {
        _ = try ControlFrames.read(fd:fds[1],deadline:ProcessInfo.processInfo.systemUptime + 1)
        preconditionFailure("Oversized frame accepted")
    } catch {}
    print("PASS: Unix stream framing and oversize rejection")
}
