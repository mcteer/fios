import Foundation
import CryptoKit

private final class VMRunningFixture:VMRunningReading,VMResourceReading,@unchecked Sendable {
    var time:Int64=10000
    var tick:TimeInterval=1
    var running=true
    var source=String(repeating:"a",count:64)
    var capturedAt:Int64?=nil
    var advance:Int64=0
    var captures=0,reads=0,releases=0
    func capture()throws->VMRunningProof {
        captures+=1
        guard running else {throw RuntimeError.launch}
        return VMRunningProof(sourceSHA256:source,sampledAt:capturedAt ?? time)
    }
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        reads+=1;time+=advance
        return VMKernelSample(sampledAt:time,total:8<<30,free:4<<30,bootHash:String(repeating:"b",count:64))
    }
    func releaseAfterVerifiedAbsence(id:String) {releases+=1}
    func gated()->RunningVMResourceReader {
        RunningVMResourceReader(kernel:self,running:self,expectedCLIHash:String(repeating:"a",count:64),now:{self.time},uptime:{self.tick})
    }
}
func runVMRunningTests() throws {
    guard VerifiedVMRunningProbe.isRunning(CommandResult(status:0,output:Data("Running\n".utf8))) else {fatalError("Reviewed running status rejected")}
    for text in ["Running","running\n","Stopped\n"," Running\n","Running\nextra\n",""] {
        guard !VerifiedVMRunningProbe.isRunning(CommandResult(status:0,output:Data(text.utf8))) else {fatalError("Unreviewed status shape became running")}
    }
    guard !VerifiedVMRunningProbe.isRunning(CommandResult(status:1,output:Data("Running\n".utf8))) else {fatalError("Failed status became running")}
    guard let fixturePath=ProcessInfo.processInfo.environment["FIOS_PLATFORM_VM_STATUS_FIXTURE"] else {fatalError("Missing VM status helper")}
    let digest=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:fixturePath))).map {String(format:"%02x",$0)}.joined()
    let executable=try VerifiedExecutable(path:fixturePath,sha256:digest)
    let captured=try VerifiedVMRunningProbe(executable:executable,home:"/var/empty").capture()
    try captured.validate(expectedSHA256:digest,now:HostResources.nowMilliseconds())
    let config=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1)
    let id=String(repeating:"e",count:64),fixture=VMRunningFixture(),gate=fixture.gated()
    fixture.running=false
    do {_=try gate.read(configuration:config,id:id,leaseUntil:60000);fatalError("Stopped/unknown VM reached metadata reader")}catch RuntimeError.launch {}
    guard fixture.reads==0 else {fatalError("Status refusal still queried daemon")}
    fixture.running=true
    _=try gate.read(configuration:config,id:id,leaseUntil:60000)
    guard fixture.reads==1 else {fatalError("Positive running prerequisite failed")}
    fixture.source=String(repeating:"f",count:64)
    do {_=try gate.read(configuration:config,id:id,leaseUntil:60000);fatalError("Foreign status identity reached metadata reader")}catch RuntimeError.identity {}
    let calls=fixture.captures
    fixture.source=String(repeating:"a",count:64)
    gate.releaseAfterVerifiedAbsence(id:id)
    do {_=try gate.read(configuration:config,id:id,leaseUntil:60000);fatalError("Cleanup revived status identity fence")}catch RuntimeError.identity {}
    guard fixture.captures==calls,fixture.reads==1,fixture.releases==1 else {fatalError("Identity fence performed more native work")}
    for at:Int64 in [4999,11001] {
        let old=VMRunningFixture();old.capturedAt=at
        do {_=try old.gated().read(configuration:config,id:id,leaseUntil:60000);fatalError("Stale/future running proof reached metadata reader")}catch RuntimeError.deadline {}
        guard old.reads==0 else {fatalError("Stale status reached kernel")}
    }
    let delayed=VMRunningFixture();delayed.advance=5001
    do {_=try delayed.gated().read(configuration:config,id:id,leaseUntil:60000);fatalError("Expired running proof returned usable data")}catch RuntimeError.deadline {}
    let clock=VMRunningFixture(),clockGate=clock.gated()
    _=try clockGate.read(configuration:config,id:id,leaseUntil:60000)
    clock.time=9999
    do {_=try clockGate.read(configuration:config,id:id,leaseUntil:60000);fatalError("Clock rollback revived running prerequisite")}catch RuntimeError.identity {}
    print("PASS: exact reviewed running status, no metadata on stopped/unknown/foreign/stale source, independent post-read age and sticky identity/clock fences; no native lease or lifecycle authority")
}
