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
    let gate=try SessionLaunchGate(manager:manager,approvedApplications:[.mlx:try VerifiedExecutable(path:path,sha256:appHash),.orbstack:try VerifiedExecutable(path:path,sha256:appHash)])
    var calls=0
    let id=UUID().uuidString.lowercased()
    func packet(_ id:String,instance:String?=nil,profile:String?=nil,extra:[String:Any]=[:])throws->Data {
        var value:[String:Any]=["version":1,"id":id,"operation":"launch","service":"mlx","instance":instance ?? gate.instance,"profile":profile ?? gate.profile]
        for (key,item) in extra {value[key]=item}
        return try JSONSerialization.data(withJSONObject:value)
    }
    let first=try packet(id)
    for extra in [["argv":["/bin/sh"]],["role":"operator"],["path":"/Applications/Foreign.app"]] as [[String:Any]] {
        do {_ = try gate.handle(packet(UUID().uuidString.lowercased(),extra:extra),peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in calls+=1;return .uncertain});fatalError("Session accepted caller-selected authority")}catch ControlError.invalid_request {}
    }
    do {_ = try gate.handle(first,peer:peer,uid:0,consoleReady:true,now:1000,launch:{_,_ in calls+=1;return .uncertain});fatalError("Root caller acquired session launch authority")}catch ControlError.unauthorized {}
    let foreign=NativeControlPeer(pid:peer.pid,start:peer.start+1,executable:manager)
    do {_ = try gate.handle(first,peer:foreign,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in calls+=1;return .uncertain});fatalError("Reused manager PID acquired launch authority")}catch ControlError.unauthorized {}
    guard calls==0 else {fatalError("Rejected session packet invoked native transport")}
    guard try gate.handle(first,peer:peer,uid:geteuid(),consoleReady:false,now:1000,launch:{_,_ in calls+=1;return .uncertain}) == .notSent else {fatalError("Missing GUI session dispatched a launch")}
    guard try gate.handle(first,peer:peer,uid:geteuid(),consoleReady:true,now:1001,launch:{_,_ in calls+=1;return .uncertain}) == .notSent,calls==0 else {fatalError("Consumed not-sent request replayed after session change")}
    let uncertain=try packet(UUID().uuidString.lowercased())
    guard try gate.handle(uncertain,peer:peer,uid:geteuid(),consoleReady:true,now:1002,launch:{service,_ in guard service == .mlx else {fatalError("Wrong fixed service")};calls+=1;return .uncertain}) == .uncertain,
          try gate.handle(uncertain,peer:peer,uid:geteuid(),consoleReady:true,now:1003,launch:{_,_ in calls+=1;return .notSent}) == .uncertain,calls==1 else {fatalError("Unknown launch was replayed or rewritten")}
    let wrongInstance=try packet(UUID().uuidString.lowercased(),instance:UUID().uuidString.lowercased())
    guard try gate.handle(wrongInstance,peer:peer,uid:geteuid(),consoleReady:true,now:1004,launch:{_,_ in calls+=1;return .uncertain}) == .wrongInstance,calls==1 else {fatalError("Another helper generation accepted a command")}
    let next=try packet(UUID().uuidString.lowercased())
    guard try gate.handle(next,peer:peer,uid:geteuid(),consoleReady:true,now:999,launch:{_,_ in calls+=1;return .uncertain}) == .uncertain,
          try gate.handle(next,peer:peer,uid:geteuid(),consoleReady:true,now:2000,launch:{_,_ in calls+=1;return .uncertain}) == .uncertain,calls==1 else {fatalError("Session clock rollback reopened execution")}
    // A second synthetic profile uses this actual test image as its approved
    // app. No application is launched; the gate must independently verify the
    // real UID/path/hash/kernel-start tuple before acknowledging callback data.
    let proofGate=try SessionLaunchGate(manager:manager,approvedApplications:[.mlx:manager,.orbstack:manager])
    var proofCalls=0
    let badIdentity=try packet(UUID().uuidString.lowercased(),instance:proofGate.instance,profile:proofGate.profile,extra:["service":"orbstack"])
    guard try proofGate.handle(badIdentity,peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in proofCalls+=1;return .started(ServiceIdentity(pid:peer.pid,start:peer.start,sha256:appHash))}) == .uncertain else {fatalError("Unapproved started identity was accepted")}
    let pathGate=try SessionLaunchGate(manager:manager,approvedApplications:[.mlx:try VerifiedExecutable(path:"/usr/bin/true",sha256:hash),.orbstack:manager])
    let pathPacket=try packet(UUID().uuidString.lowercased(),instance:pathGate.instance,profile:pathGate.profile)
    guard try pathGate.handle(pathPacket,peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in .started(ServiceIdentity(pid:peer.pid,start:peer.start,sha256:hash))}) == .uncertain else {fatalError("Started identity accepted matching hash at unapproved executable path")}
    let completedID=UUID().uuidString.lowercased(),completed=try packet(completedID,instance:proofGate.instance,profile:proofGate.profile)
    let identity=ServiceIdentity(pid:peer.pid,start:peer.start,sha256:hash)
    guard try proofGate.handle(completed,peer:peer,uid:geteuid(),consoleReady:true,now:1001,launch:{_,_ in proofCalls+=1;return .started(identity)}) == .started(identity) else {fatalError("Actual approved process identity was refused")}
    let lookup=try packet(completedID,instance:proofGate.instance,profile:proofGate.profile,extra:["operation":"lookup"])
    guard try proofGate.handle(lookup,peer:peer,uid:geteuid(),consoleReady:true,now:1002,launch:{_,_ in proofCalls+=1;return .uncertain}) == .started(identity),proofCalls==2 else {fatalError("Acknowledged lookup replayed a launch")}
    let unknown=try packet(UUID().uuidString.lowercased(),instance:proofGate.instance,profile:proofGate.profile,extra:["operation":"lookup"])
    guard try proofGate.handle(unknown,peer:peer,uid:geteuid(),consoleReady:true,now:1003,launch:{_,_ in proofCalls+=1;return .notSent}) == .uncertain,proofCalls==2 else {fatalError("Missing helper history became non-dispatch proof")}
    // Delayed native completions can resolve only the original outstanding
    // request. A timeout, new helper or unrelated presence cannot mint it.
    let delayed=try SessionLaunchGate(manager:manager,approvedApplications:[.mlx:manager,.orbstack:manager])
    let delayedID=UUID().uuidString.lowercased()
    let delayedPacket=try packet(delayedID,instance:delayed.instance,profile:delayed.profile)
    guard try delayed.handle(delayedPacket,peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in .uncertain}) == .uncertain else {fatalError("Delayed launch was acknowledged early")}
    guard delayed.claimDispatch(id:delayedID,service:.mlx,now:1000),!delayed.claimDispatch(id:delayedID,service:.mlx,now:1000),
          !delayed.acknowledgeNotSent(id:delayedID,service:.mlx) else {fatalError("Native dispatch permit replayed or became non-dispatch")}
    guard try !delayed.acknowledgeStarted(id:UUID().uuidString.lowercased(),service:.mlx,identity:identity),
          try !delayed.acknowledgeStarted(id:delayedID,service:.orbstack,identity:identity),
          try !delayed.acknowledgeStarted(id:delayedID,service:.mlx,identity:ServiceIdentity(pid:peer.pid,start:peer.start+1,sha256:hash)),
          try delayed.acknowledgeStarted(id:delayedID,service:.mlx,identity:identity),
          try !delayed.acknowledgeStarted(id:delayedID,service:.mlx,identity:identity) else {fatalError("Late acknowledgement correlation/identity/one-use check failed")}
    let delayedLookup=try packet(delayedID,instance:delayed.instance,profile:delayed.profile,extra:["operation":"lookup"])
    guard try delayed.handle(delayedLookup,peer:peer,uid:geteuid(),consoleReady:true,now:1001,launch:{_,_ in fatalError("Lookup replayed delayed launch")}) == .started(identity) else {fatalError("Delayed acknowledgement not retained")}
    let notSentID=UUID().uuidString.lowercased()
    guard try delayed.handle(packet(notSentID,instance:delayed.instance,profile:delayed.profile),peer:peer,uid:geteuid(),consoleReady:false,now:1002,launch:{_,_ in fatalError("No-session request dispatched")}) == .notSent,
          try !delayed.acknowledgeStarted(id:notSentID,service:.mlx,identity:identity) else {fatalError("Completion rewrote non-dispatch proof")}
    let otherGeneration=try SessionLaunchGate(manager:manager,approvedApplications:[.mlx:manager,.orbstack:manager])
    guard try !otherGeneration.acknowledgeStarted(id:delayedID,service:.mlx,identity:identity) else {fatalError("New helper adopted old completion")}
    let fencedID=UUID().uuidString.lowercased(),fencedPacket=try packet(fencedID,instance:delayed.instance,profile:delayed.profile)
    guard try delayed.handle(fencedPacket,peer:peer,uid:geteuid(),consoleReady:true,now:1003,launch:{_,_ in .uncertain}) == .uncertain,
          try delayed.handle(fencedPacket,peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in fatalError("Rollback replayed launch")}) == .uncertain,
          try !delayed.acknowledgeStarted(id:fencedID,service:.mlx,identity:identity) else {fatalError("Late callback bypassed permanent clock fence")}
    let validationGate=try SessionLaunchGate(manager:manager,approvedApplications:[.mlx:manager,.orbstack:manager])
    let validationID=UUID().uuidString.lowercased(),validationPacket=try packet(validationID,instance:validationGate.instance,profile:validationGate.profile)
    guard try validationGate.handle(validationPacket,peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in .uncertain}) == .uncertain,
          !validationGate.acknowledgeNotSent(id:UUID().uuidString.lowercased(),service:.mlx),
          !validationGate.acknowledgeNotSent(id:validationID,service:.orbstack),
          validationGate.acknowledgeNotSent(id:validationID,service:.mlx),
          !validationGate.acknowledgeNotSent(id:validationID,service:.mlx),
          !delayed.acknowledgeNotSent(id:fencedID,service:.mlx) else {fatalError("Local pre-effect non-dispatch acknowledgement escaped correlation/fencing")}
    let validationLookup=try packet(validationID,instance:validationGate.instance,profile:validationGate.profile,extra:["operation":"lookup"])
    guard try validationGate.handle(validationLookup,peer:peer,uid:geteuid(),consoleReady:true,now:1001,launch:{_,_ in fatalError("Validation failure replayed application operation")}) == .notSent else {fatalError("Completed validation refusal did not remain not-sent")}
    guard !validationGate.claimDispatch(id:validationID,service:.mlx,now:1001),!delayed.claimDispatch(id:fencedID,service:.mlx,now:2000) else {fatalError("Final result or clock fence permitted delayed native dispatch")}
    let dispatchClock=try SessionLaunchGate(manager:manager,approvedApplications:[.mlx:manager,.orbstack:manager])
    let clockID=UUID().uuidString.lowercased(),clockPacket=try packet(clockID,instance:dispatchClock.instance,profile:dispatchClock.profile)
    guard try dispatchClock.handle(clockPacket,peer:peer,uid:geteuid(),consoleReady:true,now:1000,launch:{_,_ in .uncertain}) == .uncertain,
          !dispatchClock.claimDispatch(id:clockID,service:.mlx,now:999),
          !dispatchClock.claimDispatch(id:clockID,service:.mlx,now:2000) else {fatalError("Dispatch did not independently check current wall clock or retain rollback fence")}
    print("PASS: fixed session launch wire, exact manager kernel identity/user, no caller argv/path/role, GUI gate, generation binding, correlated delayed completion and once-only uncertain/not-sent replay fencing; fake transport only")
}
