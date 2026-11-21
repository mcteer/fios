import Foundation
import Darwin

func runDockerVMMetadataTests()throws {
    func wire(_ headers:String,_ body:String)->Data {Data((headers+"\r\n\r\n"+body).utf8)}
    let plain=wire("HTTP/1.0 200 OK\r\nContent-Length: 2","{}")
    guard try DockerVMMetadata.body(plain,stream:false)==Data("{}".utf8) else {fatalError("Fixed metadata length framing failed")}
    let chunked=wire("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked","1\r\n{\r\n1\r\n}\r\n0\r\n\r\n")
    guard try DockerVMMetadata.body(chunked,stream:false)==Data("{}".utf8) else {fatalError("Strict metadata chunk decoding failed")}
    let upgrade=wire("HTTP/1.1 101 UPGRADED\r\nConnection: Upgrade\r\nUpgrade: tcp","")
    guard try DockerVMMetadata.body(upgrade,stream:true).isEmpty else {fatalError("Fixed exec upgrade rejected")}
    for (bad,stream) in [
        (wire("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 2","0\r\n\r\n"),false),
        (wire("HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip","{}"),false),
        (wire("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked","1;x=y\r\n{\r\n0\r\n\r\n"),false),
        (wire("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked","2\r\n{}\r\n0\r\nInjected: yes\r\n\r\n"),false),
        (wire("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked","2\r\n{}\r\n0\r\n\r\nextra"),false),
        (wire("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked","ffffffff\r\nx\r\n0\r\n\r\n"),false),
        (wire("HTTP/1.1 200 OK\r\nContent-Length: 3","{}"),false),
        (wire("HTTP/1.1 200 OK\r\nContent-Length: 2\r\ncontent-length: 2","{}"),false),
        (wire("HTTP/1.1 101 UPGRADED\r\nConnection: Upgrade\r\nUpgrade: tcp\r\nTransfer-Encoding: chunked","0\r\n\r\n"),true),
        (wire("HTTP/1.1 200 OK",String(repeating:"x",count:1<<20)+"x"),false),
    ] {
        var refused=false
        do {_=try DockerVMMetadata.body(bad,stream:stream)}catch {refused=true}
        guard refused else {fatalError("Ambiguous/oversized metadata framing accepted")}
    }
    let directory="/tmp/fios-vm-metadata-"+UUID().uuidString.lowercased()
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(atPath:directory)}
    let listener=try UnixControlSocket(path:directory+"/mock.sock")
    defer {withExtendedLifetime(listener) {}}
    let wrong=DockerVMMetadata(socketPath:directory+"/mock.sock",peerUID:geteuid()+1)
    do {_=try wrong.inspect(id:String(repeating:"a",count:64));fatalError("Foreign Unix socket owner accepted")}catch DockerVMMetadataError.socket {}
    let client=DockerVMMetadata(socketPath:directory+"/missing.sock",peerUID:geteuid())
    do {_=try client.inspect(id:"../foreign");fatalError("Arbitrary inspect path accepted")}catch RuntimeError.identity {}
    do {_=try client.read(id:String(repeating:"A",count:64));fatalError("Noncanonical exec ID accepted")}catch RuntimeError.identity {}
    print("PASS: fixed metadata API canonical IDs/UID socket gate, bounded strict length/chunk/upgrade framing; CL+TE/duplicate fields/extensions/trailers/truncation/overflow refusal (no daemon)")
}
