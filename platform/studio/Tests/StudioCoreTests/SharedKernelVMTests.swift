import Foundation

// Serialized fixture only; no native profile approval or native operations.
private final class SharedKernelFixture:NativeVMCapReading,VMResourceReading,@unchecked Sendable {
    var time:Int64=10000
    var steady:TimeInterval=1
    var capValue:UInt64=16<<30
    var boot=String(repeating:"b",count:64)
    var captures=0,reads=0
    var fail=false
    var stale=false
    var advanceOnRead:Int64=0
    func capture(liveness:NativeVMLivenessProof)throws->NativeVMCap {
        captures+=1;if fail {throw RuntimeError.launch}
        return NativeVMCap(bytes:capValue,sampledAt:stale ? time-6000:time)
    }
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        reads+=1;time+=advanceOnRead;return VMKernelSample(sampledAt:time,total:8<<30,free:4<<30,bootHash:boot)
    }
    func releaseAfterVerifiedAbsence(id:String) {}
}
func runSharedKernelVMTests()throws {
    let permission=try SharedVMKernelPermission(nativeProfileHash:String(repeating:"a",count:64),bootHash:String(repeating:"b",count:64),reviewDigest:String(repeating:"c",count:64))
    let configuration=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"d",count:64),image:"sha256:"+String(repeating:"e",count:64),memory:512<<20,cpus:1)
    let id=String(repeating:"f",count:64),fixture=SharedKernelFixture()
    let reader=SharedKernelVMReader(kernel:fixture,cap:fixture,permission:permission,physical:128<<30,now:{fixture.time},uptime:{fixture.steady})
    let proofSample=VMKernelSample(sampledAt:10000,total:8<<30,free:4<<30,bootHash:permission.bootHash)
    _=try NativeVMLivenessProof(sample:proofSample,expectedBootHash:permission.bootHash,now:10000)
    do {_=try NativeVMLivenessProof(sample:proofSample,expectedBootHash:permission.bootHash,now:11001);fatalError("Stale kernel allowed a native configuration query")}catch RuntimeError.identity {}
    do {_=try NativeVMLivenessProof(sample:proofSample,expectedBootHash:String(repeating:"0",count:64),now:10000);fatalError("Foreign boot allowed a native configuration query")}catch RuntimeError.identity {}
    let first=try reader.read(configuration:configuration,id:id,leaseUntil:60000)
    guard fixture.captures==1,let envelope=first.envelope,envelope.sampledAt==10000,
          VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:10000)==4<<30 else {fatalError("Shared-kernel envelope failed")}
    fixture.time=12000;fixture.steady=3
    let second=try reader.read(configuration:configuration,id:id,leaseUntil:60000)
    guard fixture.captures==1,second.sampledAt==12000,second.envelope?.sampledAt==10000 else {fatalError("Configuration was re-dated by a fresh kernel sample")}
    fixture.time=14000;fixture.steady=5;fixture.capValue=8<<30
    let third=try reader.read(configuration:configuration,id:id,leaseUntil:60000)
    guard fixture.captures==2,third.envelope?.sampledAt==14000,third.envelope?.runtimeHash != envelope.runtimeHash else {fatalError("Changed cap retained old VM epoch")}
    fixture.time=18000;fixture.steady=9;fixture.fail=true
    do {_=try reader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Failed native cap fell back to cached authority")}catch RuntimeError.launch {}
    fixture.fail=false;fixture.time=18001
    _=try reader.read(configuration:configuration,id:id,leaseUntil:60000)
    guard fixture.captures==4 else {fatalError("Failed source cache was silently reused")}
    fixture.time=20000;fixture.steady=11;fixture.boot=String(repeating:"0",count:64)
    do {_=try reader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Unenrolled kernel boot accepted")}catch RuntimeError.identity {}
    let reads=fixture.reads
    fixture.boot=permission.bootHash;fixture.time=20001
    do {_=try reader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Old kernel boot revived fenced authority")}catch RuntimeError.identity {}
    guard fixture.reads==reads else {fatalError("Fenced profile executed another metadata read")}
    let stale=SharedKernelFixture();stale.stale=true
    let staleReader=SharedKernelVMReader(kernel:stale,cap:stale,permission:permission,physical:128<<30,now:{stale.time},uptime:{stale.steady})
    do {_=try staleReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Stale native configuration became usable VM capacity")}catch RuntimeError.identity {}
    let clock=SharedKernelFixture()
    let clockReader=SharedKernelVMReader(kernel:clock,cap:clock,permission:permission,physical:128<<30,now:{clock.time},uptime:{clock.steady})
    _=try clockReader.read(configuration:configuration,id:id,leaseUntil:60000)
    clock.time=9999
    do {_=try clockReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Clock rollback retained VM authority")}catch RuntimeError.identity {}
    clock.time=10001
    do {_=try clockReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Clock rollback fence revived")}catch RuntimeError.identity {}
    let between=SharedKernelFixture();between.advanceOnRead=500
    let betweenReader=SharedKernelVMReader(kernel:between,cap:between,permission:permission,physical:128<<30,now:{between.time},uptime:{between.steady})
    _=try betweenReader.read(configuration:configuration,id:id,leaseUntil:60000)
    between.time=10250
    do {_=try betweenReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Rollback after completion but before next start revived authority")}catch RuntimeError.identity {}
    print("PASS: explicitly reviewed shared-kernel coverage (synthetic only), independent cap/kernel freshness, bounded configuration reuse, cap epoch changes, no failure fallback and irreversible boot/clock fences; no machine inventory invented")
}
