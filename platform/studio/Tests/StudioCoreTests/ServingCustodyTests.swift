import Foundation
import Darwin
import CryptoKit

private final class CustodyRuntimeFixture:ServingProcessControlling,@unchecked Sendable {
    let recoveryProfileHash:String
    let image:String
    let identity:ServiceIdentity
    var starts=0,stops=0,validating=false
    private var launches:[String:SessionLaunchResult]=[:]
    private var stopped:[String:(ServiceRecordedLaunch,ServingStopResult)]=[:]
    init(profile:String,image:String,identity:ServiceIdentity) {recoveryProfileHash=profile;self.image=image;self.identity=identity}
    func acceptsBaseProfile(_ base:String,expectedSHA256:String)->Bool {base==recoveryProfileHash && expectedSHA256==image}
    func accepts(_ command:ServiceLaunchCommand)->Bool {command.service == .mlx && command.profileHash==recoveryProfileHash && command.expectedSHA256==image}
    func begin(_ command:ServiceLaunchCommand,deadline:TimeInterval)throws {
        starts+=1;launches[command.id]=validating ? .uncertain:.started(identity)
    }
    func acknowledgeResult(id:String)->SessionLaunchResult {launches[id] ?? .uncertain}
    func cancelValidation(id:String)->Bool {
        guard validating,launches[id] == .uncertain else {return false};launches[id] = .notSent;return true
    }
    func retireKnownExited()->Bool {false}
    func acceptsStopReceipt(_ receipt:ServiceRecordedLaunch)->Bool {receipt.profileHash==recoveryProfileHash && receipt.identity.sha256==image}
    func beginStop(id:String,matching receipt:ServiceRecordedLaunch,deadline:TimeInterval)throws {stops+=1;stopped[id]=(receipt,.localExited)}
    func rejectedStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult {acknowledgeStopResult(id:id,matching:receipt)}
    func acknowledgeStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult {
        guard let value=stopped[id],value.0==receipt else {return .uncertain};return value.1
    }
    func cancelStopValidation(id:String,matching receipt:ServiceRecordedLaunch)->Bool {false}
}

func runServingCustodyTests()throws {
    let hash=String(repeating:"a",count:64),profile=String(repeating:"b",count:64),instance=UUID().uuidString.lowercased()
    let receipt=ServiceRecordedLaunch(service:.mlx,id:UUID().uuidString.lowercased(),identity:ServiceIdentity(pid:200,start:UInt64.max,sha256:hash),boot:UUID().uuidString.lowercased(),profileHash:profile)
    func packet(_ operation:ServingCustodyOperation,id:String=UUID().uuidString.lowercased(),instance:String=instance,receipt:ServiceRecordedLaunch?=nil)throws->ServingCustodyCommand {
        try ServingCustodyCommand(ServingCustodyCommand.encode(id:id,operation:operation,instance:instance,profile:profile,imageSHA256:hash,
            deadline:operation.isAction ? ProcessInfo.processInfo.systemUptime+5:nil,receipt:receipt),expectedSHA256:hash)
    }
    for operation in ServingCustodyOperation.allCases {
        let command=try packet(operation,receipt:operation.isStop ? receipt:nil)
        guard command.operation==operation,command.receipt==(operation.isStop ? receipt:nil) else {fatalError("Custody command lost original scope")}
        let values:[ServingCustodyValue]=operation.isStop ? [.stop(.uncertain),.stop(.notSent),.stop(.localExited)]:
            [.launch(.uncertain),.launch(.notSent),.launch(.busy),.launch(.wrongInstance),.launch(.started(receipt.identity))]
        for value in values {
            guard try ServingCustodyReply.decode(ServingCustodyReply.encode(command:command,value:value),command:command)==value else {fatalError("Custody reply changed correlated result")}
        }
    }
    let original=try ServingCustodyCommand.encode(id:UUID().uuidString.lowercased(),operation:.stop,instance:instance,profile:profile,imageSHA256:hash,deadline:10,receipt:receipt)
    for (key,value):(String,Any) in [("role","operator"),("argv",["serve"]),("pid",true),("process_start","01"),("deadline_uptime_ms",1.5),("operation","restart"),("version",2)] {
        var fields=try JSONSerialization.jsonObject(with:original) as! [String:Any];fields[key]=value
        do {_=try ServingCustodyCommand(JSONSerialization.data(withJSONObject:fields),expectedSHA256:hash);fatalError("Custody command accepted incompatible fields")}
        catch ControlError.invalid_request {}
    }
    let stopCommand=try ServingCustodyCommand(original,expectedSHA256:hash)
    do {_=try ServingCustodyReply.encode(command:stopCommand,value:.launch(.started(receipt.identity)));fatalError("Stop reply became launch receipt")}
    catch ControlError.invalid_request {}
    var response=try JSONSerialization.jsonObject(with:ServingCustodyReply.encode(command:stopCommand,value:.stop(.localExited))) as! [String:Any]
    response["id"]=UUID().uuidString.lowercased()
    do {_=try ServingCustodyReply.decode(JSONSerialization.data(withJSONObject:response),command:stopCommand);fatalError("Uncorrelated custody response accepted")}
    catch ControlError.invalid_request {}

    // Genuine local manager identity, synthetic custody results only. This
    // unit test neither spawns nor controls a native/service process.
    var image=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
    guard proc_pidpath(getpid(),&image,UInt32(image.count))>0,
          let path=String(bytes:image.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw RuntimeError.identity}
    let executableHash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let executable=try VerifiedExecutable(path:path,sha256:executableHash)
    let peer=NativeControlPeer(pid:getpid(),start:try WorkerResources.startIdentifier(pid:getpid()),executable:executable)
    let fake=CustodyRuntimeFixture(profile:profile,image:hash,identity:receipt.identity)
    let gate=try ServingCustodyGate(runtime:fake,manager:executable,imageSHA256:hash)
    let launch=try packet(.launch,instance:gate.instance)
    do {_=try gate.handle(launch,peer:peer,uid:geteuid());fatalError("Unbound manager dispatched custody")}
    catch ControlError.unauthorized {}
    try gate.bindManager(peer)
    guard try gate.handle(launch,peer:peer,uid:geteuid()) == .launch(.uncertain),fake.starts==1,
          try gate.handle(launch,peer:peer,uid:geteuid()) == .launch(.started(receipt.identity)),fake.starts==1 else {fatalError("Custody launch replayed")}
    try gate.bindManager(nil);try gate.bindManager(peer)
    let lookup=try packet(.lookupLaunch,id:launch.id,instance:gate.instance)
    guard try gate.handle(lookup,peer:peer,uid:geteuid()) == .launch(.started(receipt.identity)),fake.starts==1 else {fatalError("Manager rebind lost custody or relaunched")}
    fake.validating=true
    let pending=try packet(.launch,instance:gate.instance)
    _=try gate.handle(pending,peer:peer,uid:geteuid())
    try gate.bindManager(nil);try gate.bindManager(peer)
    guard try gate.handle(packet(.lookupLaunch,id:pending.id,instance:gate.instance),peer:peer,uid:geteuid()) == .launch(.notSent),fake.starts==2 else {fatalError("Manager loss failed to seal validation")}
    let stopped=try packet(.stop,instance:gate.instance,receipt:receipt)
    _=try gate.handle(stopped,peer:peer,uid:geteuid())
    guard try gate.handle(stopped,peer:peer,uid:geteuid()) == .stop(.localExited),fake.stops==1 else {fatalError("Stop action replayed")}
    let changed=ServiceRecordedLaunch(service:.mlx,id:UUID().uuidString.lowercased(),identity:receipt.identity,boot:receipt.boot,profileHash:profile)
    do {_=try gate.handle(packet(.lookupStop,id:stopped.id,instance:gate.instance,receipt:changed),peer:peer,uid:geteuid());fatalError("Stop scope changed under original ID")}
    catch ControlError.invalid_request {}
    let cold=try ServingCustodyGate(runtime:fake,manager:executable,imageSHA256:hash);try cold.bindManager(peer)
    guard try cold.handle(packet(.lookupStop,id:stopped.id,instance:cold.instance,receipt:receipt),peer:peer,uid:geteuid()) == .stop(.uncertain),fake.stops==1 else {fatalError("Cold custody cache fabricated history")}
    print("PASS: fixed custody frames, original receipt correlation, once-only dispatch, manager rebind and validation revocation; synthetic custody only")
}
