import Foundation
import Dispatch

private final class VMProfileFixture:VMResourceReading,NativeVMCapReading,@unchecked Sendable {
    var time:Int64=10000
    var tick:TimeInterval=1
    var boot=String(repeating:"b",count:64)
    var reads=0,captures=0,releases=0
    var failCap=false
    var rollbackOnRead=false
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        reads+=1
        if rollbackOnRead {time-=500}
        return VMKernelSample(sampledAt:time,total:8<<30,free:4<<30,bootHash:boot)
    }
    func capture(liveness:NativeVMLivenessProof)throws->NativeVMCap {
        captures+=1
        if failCap {throw RuntimeError.launch}
        return NativeVMCap(bytes:16<<30,sampledAt:time)
    }
    func releaseAfterVerifiedAbsence(id:String) {releases+=1}
    func reader()->VMResourceProfileReader {
        VMResourceProfileReader(kernel:self,cap:self,profileHash:String(repeating:"a",count:64),reviewDigest:String(repeating:"c",count:64),physical:128<<30,
            now:{self.time},uptime:{self.tick})
    }
}
private final class SlowVMProfileKernel:VMResourceReading,@unchecked Sendable {
    let entered=DispatchSemaphore(value:0),resume=DispatchSemaphore(value:0)
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        entered.signal();_ = resume.wait(timeout:.now()+1.5)
        return VMKernelSample(sampledAt:10000,total:8<<30,free:4<<30,bootHash:String(repeating:"b",count:64))
    }
    func releaseAfterVerifiedAbsence(id:String) {}
}
func runVMResourceProfileReaderTests() throws {
    let config=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"d",count:64),image:"sha256:"+String(repeating:"e",count:64),memory:512<<20,cpus:1)
    let id=String(repeating:"f",count:64),fixture=VMProfileFixture(),reader=fixture.reader()
    guard fixture.reads==0,fixture.captures==0 else {fatalError("Resource construction performed I/O")}
    do {_=try reader.read(configuration:config,id:id,leaseUntil:14999);fatalError("Short lease performed resource work")}catch RuntimeError.deadline {}
    guard fixture.reads==0,fixture.captures==0 else {fatalError("Invalid lease reached kernel source")}
    let first=try reader.read(configuration:config,id:id,leaseUntil:60000)
    guard fixture.reads==1,fixture.captures==1,first.envelope?.sampledAt==10000 else {fatalError("Initial authenticated sample was re-read or re-dated")}
    fixture.time=12000;fixture.tick=3
    let second=try reader.read(configuration:config,id:id,leaseUntil:60000)
    guard fixture.reads==2,fixture.captures==1,second.sampledAt==12000,second.envelope?.sampledAt==10000 else {fatalError("Profile lost independent original cap time")}
    fixture.boot=String(repeating:"0",count:64);fixture.time=14000;fixture.tick=5
    do {_=try reader.read(configuration:config,id:id,leaseUntil:60000);fatalError("Changed boot replaced bound resource epoch")}catch RuntimeError.identity {}
    let stopped=fixture.reads
    reader.releaseAfterVerifiedAbsence(id:id)
    fixture.boot=String(repeating:"b",count:64);fixture.time=14001
    do {_=try reader.read(configuration:config,id:id,leaseUntil:60000);fatalError("Cleanup revived fenced resource profile")}catch RuntimeError.identity {}
    guard fixture.reads==stopped,fixture.releases==1 else {fatalError("Fenced profile executed more metadata work")}
    let failed=VMProfileFixture();failed.failCap=true
    let failedReader=failed.reader()
    do {_=try failedReader.read(configuration:config,id:id,leaseUntil:60000);fatalError("Failed cap admitted capacity")}catch RuntimeError.launch {}
    failed.failCap=false;failed.boot=String(repeating:"0",count:64);failed.time=12000;failed.tick=3
    do {_=try failedReader.read(configuration:config,id:id,leaseUntil:60000);fatalError("Failed first capture allowed profile rebind")}catch RuntimeError.identity {}
    guard failed.captures==1 else {fatalError("Failed first capture reset bound epoch")}
    let clock=VMProfileFixture();clock.rollbackOnRead=true
    let clockReader=clock.reader()
    do {_=try clockReader.read(configuration:config,id:id,leaseUntil:60000);fatalError("Bootstrap clock rollback admitted capacity")}catch RuntimeError.identity {}
    clock.rollbackOnRead=false;clock.time=10001
    do {_=try clockReader.read(configuration:config,id:id,leaseUntil:60000);fatalError("Bootstrap clock fence revived")}catch RuntimeError.identity {}
    guard clock.reads==1,clock.captures==0 else {fatalError("Clock fence performed more native work")}
    let slow=SlowVMProfileKernel(),slowCap=VMProfileFixture(),finished=DispatchSemaphore(value:0)
    let slowReader=VMResourceProfileReader(kernel:slow,cap:slowCap,profileHash:String(repeating:"a",count:64),reviewDigest:String(repeating:"c",count:64),physical:128<<30,
        now:{10000},uptime:{1})
    DispatchQueue.global().async {
        defer {finished.signal()}
        _=try? slowReader.read(configuration:config,id:id,leaseUntil:60000)
    }
    guard slow.entered.wait(timeout:.now()+2) == .success else {slow.resume.signal();fatalError("Slow resource fixture never entered")}
    let began=ProcessInfo.processInfo.systemUptime
    slowReader.releaseAfterVerifiedAbsence(id:id)
    let elapsed=ProcessInfo.processInfo.systemUptime-began
    slow.resume.signal()
    guard finished.wait(timeout:.now()+3) == .success else {fatalError("Slow resource fixture failed to finish")}
    guard elapsed<0.5 else {fatalError("VM cleanup waited for source I/O")}
    print("PASS: synthetic trusted profile composition: one original first sample, no constructor/invalid-lease I/O, original cap age and sticky first-failure/boot/clock/cleanup fences; no installed VM authority")
}
