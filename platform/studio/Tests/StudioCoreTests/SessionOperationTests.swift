import Foundation
import Darwin
import CryptoKit

func runSessionOperationTests() throws {
    var image=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
    guard proc_pidpath(getpid(),&image,UInt32(image.count))>0,
          let path=String(bytes:image.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw RuntimeError.identity}
    let hash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let manager=try VerifiedExecutable(path:path,sha256:hash),appHash=String(repeating:"a",count:64)
    let peer=NativeControlPeer(pid:getpid(),start:try WorkerResources.startIdentifier(pid:getpid()),executable:manager)
    _=try ServiceIdentity.verified(peer:peer,expectedUID:geteuid(),deadline:ProcessInfo.processInfo.systemUptime+2)
    let gate=try SessionLaunchGate(manager:manager,approvedHashes:[.mlx:appHash,.orbstack:appHash])
    var calls=0
    let id=UUID().uuidString.lowercased()
    func packet(_ id:String,instance:String?=nil,profile:String?=nil,extra:[String:Any]=[:])throws->Data {
        var value:[String:Any]=["version":1,"id":id,"operation":"launch","service":"mlx","instance":instance ?? gate.instance,"profile":profile ?? gate.profile]
        for (key,item) in extra {value[key]=item}
        return try JSONSerialization.data(withJSONObject:value)
    }
    let first=try packet(id)
    for extra in [["argv":["/bin/sh"]],["role":"operator"],["path":"/Applications/Foreign.app"]] as [[String:Any]] {
        do {_ = try gate.handle(packet(UUID().uuidString.lowercased(),extra:extra),peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_ in calls+=1;return .uncertain});fatalError("Session accepted caller-selected authority")}catch ControlError.invalid_request {}
    }
    do {_ = try gate.handle(first,peer:peer,uid:0,consoleReady:true,now:1000,launch:{_ in calls+=1;return .uncertain});fatalError("Root caller acquired session launch authority")}catch ControlError.unauthorized {}
    let foreign=NativeControlPeer(pid:peer.pid,start:peer.start+1,executable:manager)
    do {_ = try gate.handle(first,peer:foreign,uid:geteuid(),consoleReady:true,now:1000,launch:{_ in calls+=1;return .uncertain});fatalError("Reused manager PID acquired launch authority")}catch ControlError.unauthorized {}
    guard calls==0 else {fatalError("Rejected session packet invoked native transport")}
    guard try gate.handle(first,peer:peer,uid:geteuid(),consoleReady:false,now:1000,launch:{_ in calls+=1;return .uncertain}) == .notSent else {fatalError("Missing GUI session dispatched a launch")}
    guard try gate.handle(first,peer:peer,uid:geteuid(),consoleReady:true,now:1001,launch:{_ in calls+=1;return .uncertain}) == .notSent,calls==0 else {fatalError("Consumed not-sent request replayed after session change")}
    let uncertain=try packet(UUID().uuidString.lowercased())
    guard try gate.handle(uncertain,peer:peer,uid:geteuid(),consoleReady:true,now:1002,launch:{service in guard service == .mlx else {fatalError("Wrong fixed service")};calls+=1;return .uncertain}) == .uncertain,
          try gate.handle(uncertain,peer:peer,uid:geteuid(),consoleReady:true,now:1003,launch:{_ in calls+=1;return .notSent}) == .uncertain,calls==1 else {fatalError("Unknown launch was replayed or rewritten")}
    let wrongInstance=try packet(UUID().uuidString.lowercased(),instance:UUID().uuidString.lowercased())
    guard try gate.handle(wrongInstance,peer:peer,uid:geteuid(),consoleReady:true,now:1004,launch:{_ in calls+=1;return .uncertain}) == .wrongInstance,calls==1 else {fatalError("Another helper generation accepted a command")}
    let next=try packet(UUID().uuidString.lowercased())
    guard try gate.handle(next,peer:peer,uid:geteuid(),consoleReady:true,now:999,launch:{_ in calls+=1;return .uncertain}) == .uncertain,
          try gate.handle(next,peer:peer,uid:geteuid(),consoleReady:true,now:2000,launch:{_ in calls+=1;return .uncertain}) == .uncertain,calls==1 else {fatalError("Session clock rollback reopened execution")}
    // A second synthetic profile uses this actual test image as its approved
    // app. No application is launched; the gate must independently verify the
    // real UID/path/hash/kernel-start tuple before acknowledging callback data.
    let proofGate=try SessionLaunchGate(manager:manager,approvedHashes:[.mlx:hash,.orbstack:hash])
    var proofCalls=0
    let badIdentity=try packet(UUID().uuidString.lowercased(),instance:proofGate.instance,profile:proofGate.profile,extra:["service":"orbstack"])
    guard try proofGate.handle(badIdentity,peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_ in proofCalls+=1;return .started(ServiceIdentity(pid:peer.pid,start:peer.start,sha256:appHash))}) == .uncertain else {fatalError("Unapproved started identity was accepted")}
    let completedID=UUID().uuidString.lowercased(),completed=try packet(completedID,instance:proofGate.instance,profile:proofGate.profile)
    let identity=ServiceIdentity(pid:peer.pid,start:peer.start,sha256:hash)
    guard try proofGate.handle(completed,peer:peer,uid:geteuid(),consoleReady:true,now:1001,launch:{_ in proofCalls+=1;return .started(identity)}) == .started(identity) else {fatalError("Actual approved process identity was refused")}
    let lookup=try packet(completedID,instance:proofGate.instance,profile:proofGate.profile,extra:["operation":"lookup"])
    guard try proofGate.handle(lookup,peer:peer,uid:geteuid(),consoleReady:true,now:1002,launch:{_ in proofCalls+=1;return .uncertain}) == .started(identity),proofCalls==2 else {fatalError("Acknowledged lookup replayed a launch")}
    let unknown=try packet(UUID().uuidString.lowercased(),instance:proofGate.instance,profile:proofGate.profile,extra:["operation":"lookup"])
    guard try proofGate.handle(unknown,peer:peer,uid:geteuid(),consoleReady:true,now:1003,launch:{_ in proofCalls+=1;return .notSent}) == .uncertain,proofCalls==2 else {fatalError("Missing helper history became non-dispatch proof")}
    print("PASS: fixed session launch wire, exact manager kernel identity/user, no caller argv/path/role, GUI gate, generation binding and once-only uncertain/not-sent replay fencing; fake transport only")
}
