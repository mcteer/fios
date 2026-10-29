import Foundation
import Darwin

func runDockerAttachTests() throws {
    let home="/private/tmp/fios-attach-"+UUID().uuidString.lowercased()
    let directory=home+"/.orbstack/run"
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(atPath:home)}
    let listener=try UnixControlSocket(path:directory+"/docker.sock")
    let config=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
    let id=String(repeating:"c",count:64),created=ProcessInfo.processInfo.systemUptime
    let client=try DockerAttach(socketPath:directory+"/docker.sock",configuration:config,savedID:id,peerUID:geteuid(),now:created,endpointPolicy:try RuntimeEndpointPolicy(home:home,uid:geteuid()))
    guard let peer=try listener.acceptPeer() else {fatalError("Local attach mock not connected")}
    defer {Darwin.close(peer)}
    _=try client.poll(now:ProcessInfo.processInfo.systemUptime)
    var bytes=[UInt8](repeating:0,count:4096)
    let n=Darwin.read(peer,&bytes,bytes.count)
    guard n>0,String(decoding:bytes.prefix(n),as:UTF8.self).hasPrefix("POST /v1.47/containers/"+id+"/attach?stdin=1&stdout=1&stderr=1&stream=1 HTTP/1.1\r\n") else {fatalError("Attach request became arbitrary daemon route")}
    func send(_ data:Data) {
        let written=data.withUnsafeBytes {Darwin.write(peer,$0.baseAddress!,data.count)}
        guard written==data.count else {fatalError("Mock short write")}
    }
    send(Data("HTTP/1.1 101 UPGRADED\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n".utf8))
    _=try client.poll(now:ProcessInfo.processInfo.systemUptime)
    guard client.ready else {fatalError("Attach handshake not ready")}
    let body=Data("{\"version\":1,\"type\":\"complete\"}".utf8)
    let application=Data([0,0,0,UInt8(body.count)])+body
    let wire=Data([1,0,0,0,0,0,0,UInt8(application.count)])+application
    send(Data(wire.prefix(3)))
    guard try client.poll(now:ProcessInfo.processInfo.systemUptime).isEmpty else {fatalError("Partial Docker header became application frame")}
    send(Data(wire.dropFirst(3)))
    guard try client.poll(now:ProcessInfo.processInfo.systemUptime)==[body] else {fatalError("Docker/application framing lost correlation")}
    try client.enqueue(application)
    _=try client.poll(now:ProcessInfo.processInfo.systemUptime)
    let received=Darwin.read(peer,&bytes,bytes.count)
    guard received==application.count,Data(bytes.prefix(received))==application else {fatalError("Attach input framing changed")}
    client.close()
    guard chmod(directory,0o755)==0 else {fatalError("Fixture endpoint mode change failed")}
    do {
        _=try DockerAttach(socketPath:directory+"/docker.sock",configuration:config,savedID:id,peerUID:geteuid(),now:ProcessInfo.processInfo.systemUptime,endpointPolicy:RuntimeEndpointPolicy(home:home,uid:geteuid()))
        fatalError("Attach ignored its enrolled endpoint policy")
    } catch RuntimeError.identity {}
    guard chmod(directory,0o700)==0 else {fatalError("Fixture endpoint mode restore failed")}

    var parser=DockerMultiplex()
    do {_=try parser.append(Data([2,0,0,0,0,0,0,1,65]));fatalError("Infrastructure stderr entered control frames")} catch DockerStreamError.invalid {}
    do {_=try parser.append(wire);fatalError("Failed multiplex parser revived")} catch DockerStreamError.closed {}
    var truncated=DockerMultiplex()
    _=try truncated.append(Data(wire.prefix(9)))
    do {try truncated.finish();fatalError("Truncated multiplex frame accepted")} catch DockerStreamError.invalid {}
    print("PASS: private Unix fixed attach/UID/upgrade, partial multiplex/application framing, bounded writes and irreversible malformed/stderr/truncation rejection (mock daemon only)")
}
