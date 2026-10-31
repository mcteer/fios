import Foundation
import Darwin

func runAsyncNativeControlTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-native-async-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let peer=NativeControlPeer(pid:getpid(),start:try WorkerResources.startIdentifier(pid:getpid()),executable:try VerifiedExecutable(path:"/var/empty/no-native-executable",sha256:String(repeating:"a",count:64)))
    let queue=AsyncNativeControl(client:NativeControlClient(path:directory.appendingPathComponent("absent.sock").path,peer:peer))
    let command=NativeMaintenanceCommand(id:UUID().uuidString.lowercased(),operation:.observe,instance:nil,sequence:0)
    try queue.submit(command)
    do {try queue.submit(command);fatalError("Unconsumed native work exceeded one slot")}catch{}
    let deadline=ProcessInfo.processInfo.systemUptime+3
    var received:NativeControlResult?
    while ProcessInfo.processInfo.systemUptime<deadline,received==nil {received=queue.poll();if received==nil {Thread.sleep(forTimeInterval:0.001)}}
    guard let received,received.id==command.id else {fatalError("Native off-loop result lost")}
    guard case .failure=received.value else {fatalError("Missing private socket authenticated")}
    guard queue.poll()==nil else {fatalError("Native result replayed")}
    print("PASS: one-slot off-loop native control, correlated finite result, no replay or fallback")
}
