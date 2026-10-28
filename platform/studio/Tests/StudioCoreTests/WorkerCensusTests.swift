import Foundation
import Darwin

func runWorkerCensusTests() throws {
    let directory=URL(fileURLWithPath:"/tmp/fios-worker-census-"+UUID().uuidString.lowercased()).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let executable=directory.appendingPathComponent("private-sentinel")
    try FileManager.default.copyItem(at:URL(fileURLWithPath:"/bin/sleep"),to:executable)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
    // Copied Apple platform binaries cannot execute outside their sealed
    // location until this disposable copy is ad-hoc signed. No app modified.
    let sign=Process();sign.executableURL=URL(fileURLWithPath:"/usr/bin/codesign");sign.arguments=["--force","--sign","-","--timestamp=none",executable.path]
    sign.standardInput=FileHandle.nullDevice;sign.standardOutput=FileHandle.nullDevice;sign.standardError=FileHandle.nullDevice
    try sign.run();sign.waitUntilExit();guard sign.terminationStatus==0 else {throw RuntimeError.identity}
    let policy=try WorkerCensusPolicy(reviewDigest:String(repeating:"a",count:64),historicalExecutablePaths:[executable.path,URL(fileURLWithPath:CommandLine.arguments[0]).resolvingSymlinksInPath().path])
    var journal:Journal?=try Journal(directory:directory.appendingPathComponent("state"))
    let id=UUID().uuidString.lowercased()
    try journal!.claim(job:id,attempt:0,model:"fixture/model")
    let nonce=try journal!.planWorkerLaunch(job:id,attempt:0)
    let foreign=Process();foreign.executableURL=executable;foreign.arguments=["30"]
    foreign.standardInput=FileHandle.nullDevice;foreign.standardOutput=FileHandle.nullDevice;foreign.standardError=FileHandle.nullDevice
    try foreign.run()
    defer {if foreign.isRunning {foreign.terminate()};foreign.waitUntilExit()}
    journal=nil;journal=try Journal(directory:directory.appendingPathComponent("state"))
    var held=AdmissionPolicy()
    let recovery=try WorkerReconciler(journal:journal!,admission:&held,census:policy)
    guard recovery.degraded,recovery.pending==1,foreign.isRunning,try journal!.activeLaunchCount()==1 else {
        var path=[CChar](repeating:0,count:4096)
        let length=proc_pidpath(foreign.processIdentifier,&path,UInt32(path.count))
        let value=String(bytes:path.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) ?? ""
        fatalError("Census sentinel check: degraded=\(recovery.degraded) pending=\(recovery.pending) alive=\(foreign.isRunning) path_available=\(length>0) path_in_policy=\(policy.paths.contains(value))")
    }
    foreign.terminate();foreign.waitUntilExit() // Test-owned sentinel, never signalled by census.
    let proof=try policy.absence()
    do {try journal!.recordUnboundWorkerGone(job:id,attempt:0,nonce:nonce+"x",proof:proof);fatalError("Foreign launch nonce accepted")}catch JournalError.conflict {}
    guard try journal!.activeLaunchCount()==1 else {fatalError("Rejected proof mutated launch")}
    var released=AdmissionPolicy()
    let recovered=try WorkerReconciler(journal:journal!,admission:&released,census:policy)
    guard !recovered.degraded,recovered.pending==0,try journal!.activeLaunchCount()==0,
          try journal!.unresolvedCount()==1,try journal!.uncertainCount()==1 else {fatalError("Local absence cleared native uncertainty or failed to release local launch")}
    let sample=ResourceSample(sampledAt:10000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    try released.reserveWorker(key:"one",sample:sample,now:10000);try released.reserveWorker(key:"two",sample:sample,now:10000)
    try FileManager.default.removeItem(at:executable)
    try FileManager.default.copyItem(at:URL(fileURLWithPath:"/usr/bin/true"),to:executable)
    do {_=try policy.absence();fatalError("Replaced historical image retained census authority")}catch WorkerResourceError.unavailable {}
    print("PASS: reviewed metadata-only startup census retains foreign same-image sentinel without signalling, then proves unknown-PID local absence/nonce binding; native inference uncertainty stays intact")
}
