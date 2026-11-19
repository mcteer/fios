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
    var kernelTimestampDelta:Int64=0
    var steadyDeltaOnRead:TimeInterval=0
    var uptimeReads=0
    func completionEdgeUptime()->TimeInterval {
        uptimeReads+=1
        if uptimeReads==6 {return 4}
        return steady
    }
    var wallAtCapPublication:Int64?
    func capture(liveness:NativeVMLivenessProof,checkpoint:()throws->Void)throws->NativeVMCap {
        if let wallAtCapPublication {time=wallAtCapPublication;try checkpoint()}
        captures+=1;if fail {throw RuntimeError.launch}
        return NativeVMCap(bytes:capValue,sampledAt:stale ? time-6000:time)
    }
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        reads+=1;time+=advanceOnRead;steady+=steadyDeltaOnRead;return VMKernelSample(sampledAt:time+kernelTimestampDelta,total:8<<30,free:4<<30,bootHash:boot)
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
    for delta:Int64 in [-1,1] {
        let unbound=SharedKernelFixture();unbound.kernelTimestampDelta=delta
        let guarded=SharedKernelVMReader(kernel:unbound,cap:unbound,permission:permission,physical:128<<30,now:{unbound.time},uptime:{unbound.steady})
        do {_=try guarded.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Out-of-read kernel stamp authorized cap probe")}catch RuntimeError.identity {}
        guard unbound.captures==0 else {fatalError("Invalid kernel time reached native cap source")}
    }
    for delta in [Double.nan,-0.5,5.001] {
        let bad=SharedKernelFixture();bad.steadyDeltaOnRead=delta
        let guarded=SharedKernelVMReader(kernel:bad,cap:bad,permission:permission,physical:128<<30,now:{bad.time},uptime:{bad.steady})
        do {_=try guarded.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Invalid elapsed kernel read reached cap probe")}catch RuntimeError.identity {}
        guard bad.captures==0 else {fatalError("Invalid elapsed kernel read queried cap")}
    }
    let expired=SharedKernelFixture();expired.advanceOnRead=5000
    let expiring=SharedKernelVMReader(kernel:expired,cap:expired,permission:permission,physical:128<<30,now:{expired.time},uptime:{expired.steady})
    do {_=try expiring.read(configuration:configuration,id:id,leaseUntil:15000);fatalError("Expired lease reached cap probe")}catch RuntimeError.deadline {}
    guard expired.captures==0 else {fatalError("Cap queried after lease expired during kernel read")}
    let preflight=SharedKernelFixture();preflight.wallAtCapPublication=11001
    let preflightReader=SharedKernelVMReader(kernel:preflight,cap:preflight,permission:permission,physical:128<<30,
        now:{preflight.time},uptime:{preflight.steady})
    do {_=try preflightReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Aged kernel published cap lookup")}
    catch RuntimeError.deadline {}
    guard preflight.captures==0 else {fatalError("Cap publication ran on an aged kernel proof")}
    let boundary=SharedKernelFixture();boundary.wallAtCapPublication=11000
    let boundaryReader=SharedKernelVMReader(kernel:boundary,cap:boundary,permission:permission,physical:128<<30,
        now:{boundary.time},uptime:{boundary.steady})
    let accepted=try boundaryReader.read(configuration:configuration,id:id,leaseUntil:60000)
    guard boundary.captures==1,accepted.envelope?.sampledAt==10000 else {fatalError("Exact cap publication edge lost original kernel time")}
    let capRollback=SharedKernelFixture();capRollback.wallAtCapPublication=9999
    let rollbackReader=SharedKernelVMReader(kernel:capRollback,cap:capRollback,permission:permission,physical:128<<30,
        now:{capRollback.time},uptime:{capRollback.steady})
    do {_=try rollbackReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Cap lookup accepted pre-spawn rollback")}
    catch RuntimeError.identity {}
    capRollback.wallAtCapPublication=nil;capRollback.time=10001
    do {_=try rollbackReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Cap lookup rollback fence revived")}
    catch RuntimeError.identity {}
    guard capRollback.captures==0,capRollback.reads==1 else {fatalError("Cap rollback performed additional source work")}
    let aging=SharedKernelFixture()
    let agingReader=SharedKernelVMReader(kernel:aging,cap:aging,permission:permission,physical:128<<30,now:{aging.time},uptime:{aging.steady})
    _=try agingReader.read(configuration:configuration,id:id,leaseUntil:60000)
    aging.steady=3.5;aging.steadyDeltaOnRead=0.5;aging.time=13000
    _=try agingReader.read(configuration:configuration,id:id,leaseUntil:60000)
    guard aging.captures==2 else {fatalError("Slow kernel read extended cached VM cap beyond its reuse window")}
    let reuseEdge=SharedKernelFixture()
    let edgeReader=SharedKernelVMReader(kernel:reuseEdge,cap:reuseEdge,permission:permission,physical:128<<30,
        now:{reuseEdge.time},uptime:reuseEdge.completionEdgeUptime)
    _=try edgeReader.read(configuration:configuration,id:id,leaseUntil:60000)
    reuseEdge.time=12999;reuseEdge.steady=3.999
    do {_=try edgeReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("VM cap reuse remained valid after its completion window")}
    catch RuntimeError.identity {}
    guard reuseEdge.captures==1 else {fatalError("Expired cached cap triggered new I/O inside completion")}
    reuseEdge.time=13001;reuseEdge.steady=4.001
    let refreshed=try edgeReader.read(configuration:configuration,id:id,leaseUntil:60000)
    guard reuseEdge.captures==2,refreshed.envelope?.sampledAt==13001 else {
        fatalError("Independent read did not restore capacity from a freshly captured cap")
    }
    let rewind=SharedKernelFixture()
    let rewindReader=SharedKernelVMReader(kernel:rewind,cap:rewind,permission:permission,physical:128<<30,now:{rewind.time},uptime:{rewind.steady})
    _=try rewindReader.read(configuration:configuration,id:id,leaseUntil:60000)
    rewind.steady=0.5
    do {_=try rewindReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Rewound monotonic clock reached VM metadata")}catch RuntimeError.identity {}
    rewind.steady=2
    do {_=try rewindReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Monotonic clock fence revived")}catch RuntimeError.identity {}
    guard rewind.reads==1,rewind.captures==1 else {fatalError("Fenced clock performed more VM reads")}
    let between=SharedKernelFixture();between.advanceOnRead=500
    let betweenReader=SharedKernelVMReader(kernel:between,cap:between,permission:permission,physical:128<<30,now:{between.time},uptime:{between.steady})
    _=try betweenReader.read(configuration:configuration,id:id,leaseUntil:60000)
    between.time=10250
    do {_=try betweenReader.read(configuration:configuration,id:id,leaseUntil:60000);fatalError("Rollback after completion but before next start revived authority")}catch RuntimeError.identity {}
    print("PASS: explicitly reviewed shared-kernel coverage (synthetic only), independent cap/kernel freshness, bounded configuration reuse, cap epoch changes, no failure fallback and irreversible boot/clock fences; no machine inventory invented")
}
