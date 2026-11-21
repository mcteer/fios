import Foundation
import Darwin

// Normal stdin -> local task socket -> JSON reply round trip.
func runTaskClientTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let socket=try UnixControlSocket(path:directory.appendingPathComponent("task.sock").path)
    let listener=socket.fd
    let completed=DispatchSemaphore(value:0)
    DispatchQueue.global().async {
        defer {completed.signal()}
        let deadline=ProcessInfo.processInfo.systemUptime+3
        var ready=pollfd(fd:listener,events:Int16(POLLIN),revents:0)
        guard Darwin.poll(&ready,1,3000)>0 else {return}
        let peer=Darwin.accept(listener,nil,nil)
        guard peer>=0 else {return}
        defer {Darwin.close(peer)}
        do {
            let request=try ControlRequest.decode(ControlFrames.read(fd:peer,deadline:deadline))
            let reply:[String:Any]=["ok":true,"id":request.id,"operation":request.operation.rawValue,"payload":request.payload]
            try ControlFrames.write(fd:peer,data:JSONSerialization.data(withJSONObject:reply),deadline:deadline)
        }catch {return}
    }
    let id=UUID().uuidString.lowercased(),job=UUID().uuidString.lowercased()
    let payload=["owner":TaskOwner.newToken(),"job":job]
    let data=try JSONSerialization.data(withJSONObject:["version":1,"id":id,"operation":"job.status","payload":payload])
    var descriptors:[Int32]=[0,0]
    guard Darwin.pipe(&descriptors)==0 else {throw ControlError.internal_error}
    defer {Darwin.close(descriptors[0])}
    let written=data.withUnsafeBytes {Darwin.write(descriptors[1],$0.baseAddress,data.count)}
    Darwin.close(descriptors[1])
    guard written==data.count else {throw ControlError.internal_error}
    let response=try TaskControlClient.request(directory:directory,inputFD:descriptors[0])
    guard completed.wait(timeout:.now()+3) == .success else {throw ControlError.internal_error}
    guard response["id"] as? String == id else {
        throw NSError(domain:"TaskClient",code:1,userInfo:[NSLocalizedDescriptionKey:"Task CLI replaced the caller request ID"])
    }
    guard response["operation"] as? String == "job.status",response["payload"] as? [String:String] == payload else {throw ControlError.invalid_request}
    withExtendedLifetime(socket) {}
    print("PASS: task CLI preserves the caller request ID and payload through a normal local socket round trip")
}
