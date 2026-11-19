import Foundation

private final class VMObservationFixture:VMObservationWork,@unchecked Sendable {
    var requests:[(SandboxConfiguration,String,Int64)]=[]
    var replies:[VMReadResult]=[]
    var capacity=false
    func submit(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws {
        if capacity {throw AdmissionError.capacity}
        requests.append((configuration,id,leaseUntil))
    }
    func drain()->[VMReadResult] {let result=replies;replies=[];return result}
}

func runReadOnlyVMResourceTests() throws {
    let hash=String(repeating:"a",count:64),id=String(repeating:"b",count:64)
    let configuration=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:hash,image:"sha256:"+hash,memory:512<<20,cpus:1)
    var job=try DurableJob(id:configuration.job,idempotency:UUID().uuidString.lowercased(),ownerHash:hash,requestHash:hash,created:1000)
    job.state = .running
    let record=SandboxRecord(configuration:configuration,runtimeID:id,createIssued:true,startIssued:true)
    let host=ResourceSample(sampledAt:1000,physical:32<<30,available:16<<30,vmAvailable:nil,diskFree:32<<30,cpu:0,pressure:.normal,thermal:.nominal,cpuSampledAt:1000)
    func sample(_ stamp:Int64=1000,_ covered:Bool=true)->VMKernelSample {
        VMKernelSample(sampledAt:stamp,total:16<<30,free:8<<30,bootHash:hash,
            envelope:VMResourceObservation(runtimeHash:hash,sampledAt:stamp,configuredCap:12<<30,total:16<<30,free:8<<30,allVMConsumersCovered:covered))
    }
    func reply(_ value:VMKernelSample)->VMReadResult {VMReadResult(job:job.id,runtimeID:id,result:.success(value))}
    let work=VMObservationFixture(),reader=ReadOnlyVMResources(work:work)
    reader.tick(records:[],jobs:[job],physical:host.physical,now:1000)
    guard work.requests.isEmpty,reader.applying(to:host,now:1000).vmAvailable==nil else {fatalError("VM observation created an unowned target")}
    for mutate in 0..<5 {
        var invalid=record,invalidJob=job
        switch mutate {
        case 0:invalid.createIssued=false
        case 1:invalid.startIssued=false
        case 2:invalid.removalProven=true
        case 3:invalid.runtimeID=nil
        default:invalidJob.state = .revoking
        }
        reader.tick(records:[invalid],jobs:[invalidJob],physical:host.physical,now:1000)
    }
    reader.tick(records:[record],jobs:[job],physical:host.physical,now:job.lease.expires-4999)
    guard work.requests.isEmpty else {fatalError("VM observation entered a target without original ownership/lease")}
    var renewed=job
    try renewed.lease.renew(now:5000)
    let renewedWork=VMObservationFixture(),renewedReader=ReadOnlyVMResources(work:renewedWork)
    renewedReader.tick(records:[record],jobs:[renewed],physical:host.physical,now:4999)
    guard renewedWork.requests.isEmpty else {fatalError("VM_OBSERVATION_RESTORED_LEASE_CLOCK_REOPENED")}
    // This first coordinator has seen a later wall clock. A fresh independent
    // coordinator tests the healthy timeline without resetting a live fence.
    let healthyWork=VMObservationFixture(),healthy=ReadOnlyVMResources(work:healthyWork)
    healthy.tick(records:[record],jobs:[job],physical:host.physical,now:1000)
    healthy.tick(records:[record],jobs:[job],physical:host.physical,now:3000)
    guard healthyWork.requests.count==1,healthyWork.requests[0].2==job.lease.expires else {fatalError("VM observation replaced pending work or extended its lease")}
    healthyWork.replies=[reply(sample())]
    healthy.tick(records:[record],jobs:[job],physical:host.physical,now:3001)
    guard healthy.applying(to:host,now:3001).vmAvailable==4<<30,
          healthy.applying(to:host,now:3001).vmSampledAt==1000,healthy.epoch(now:3001)==hash,
          healthyWork.requests.count==2,healthy.epoch(now:6001)==nil else {fatalError("VM observation lost whole-envelope accounting/original freshness")}
    let cachedWork=VMObservationFixture(),cached=ReadOnlyVMResources(work:cachedWork)
    cached.tick(records:[record],jobs:[job],physical:host.physical,now:3000)
    var cachedCap=sample(3001)
    cachedCap.envelope=sample(1000).envelope
    cachedWork.replies=[reply(cachedCap)]
    cached.tick(records:[record],jobs:[job],physical:host.physical,now:3001)
    guard cached.applying(to:host,now:6000).vmSampledAt==1000,cached.epoch(now:6000)==hash,
          cached.applying(to:host,now:6001).vmAvailable==nil,cached.epoch(now:6001)==nil else {
        fatalError("Read-only VM cap inherited the newer kernel's freshness")
    }
    let replayWork=VMObservationFixture(),replay=ReadOnlyVMResources(work:replayWork)
    replay.tick(records:[record],jobs:[job],physical:host.physical,now:3000)
    replayWork.replies=[reply(sample(2999))]
    replay.tick(records:[record],jobs:[job],physical:host.physical,now:3001)
    guard replay.epoch(now:3001)==nil,replay.applying(to:host,now:3001).vmAvailable==nil else {
        fatalError("VM envelope predating submitted work became current capacity")
    }
    healthyWork.replies=[VMReadResult(job:job.id,runtimeID:id,result:.failure(.unavailable))]
    healthy.tick(records:[record],jobs:[job],physical:host.physical,now:4000)
    // The original envelope is still within its freshness window. Failure,
    // not elapsed age, must withdraw the cached value and source epoch.
    guard healthy.epoch(now:4000)==nil,healthy.applying(to:host,now:4000).vmAvailable==nil else {
        fatalError("Unsuccessful VM collection kept a previously fresh envelope")
    }
    healthy.tick(records:[record],jobs:[job],physical:host.physical,now:6000)
    guard healthyWork.requests.count==2,healthy.epoch(now:6000)==nil else {fatalError("VM observation replayed uncertain resource work")}

    for mode in 0..<7 {
        let source=VMObservationFixture(),subject=ReadOnlyVMResources(work:source)
        subject.tick(records:[record],jobs:[job],physical:host.physical,now:1000)
        var currentRecord=record,currentJob=job,value=sample()
        var physical=host.physical
        switch mode {
        case 0:currentJob.state = .revoking
        case 1:currentRecord.runtimeID=String(repeating:"c",count:64)
        case 2:value=sample(1000,false)
        case 3:physical=8<<30
        case 4:value=sample(7002)
        case 5:value=sample(-1)
        default:currentJob.lease.revoke()
        }
        source.replies=[reply(value)]
        subject.tick(records:[currentRecord],jobs:[currentJob],physical:physical,now:1001)
        guard subject.epoch(now:1001)==nil,subject.applying(to:host,now:1001).vmAvailable==nil else {fatalError("VM observation accepted a lost target, lease or invalid envelope")}
    }
    let revokedWork=VMObservationFixture(),revoked=ReadOnlyVMResources(work:revokedWork)
    revoked.tick(records:[record],jobs:[job],physical:host.physical,now:1000)
    revokedWork.replies=[reply(sample())]
    revoked.tick(records:[record],jobs:[job],physical:host.physical,now:1001)
    revoked.tick(records:[],jobs:[job],physical:host.physical,now:1002)
    guard revoked.epoch(now:1002)==nil else {fatalError("VM observation retained a sample after observed target loss")}
    let lostWork=VMObservationFixture(),lost=ReadOnlyVMResources(work:lostWork)
    lost.tick(records:[record],jobs:[job],physical:host.physical,now:1000)
    lost.tick(records:[],jobs:[job],physical:host.physical,now:1001)
    lostWork.replies=[reply(sample(1002))]
    lost.tick(records:[record],jobs:[job],physical:host.physical,now:1002)
    lost.tick(records:[record],jobs:[job],physical:host.physical,now:3000)
    guard lostWork.requests.count==1,lost.epoch(now:3000)==nil else {
        fatalError("Restored target resurrected VM work after observed ownership loss")
    }
    let expiryWork=VMObservationFixture(),expiring=ReadOnlyVMResources(work:expiryWork)
    let expiry=job.lease.expires,edge=expiry-5000
    expiring.tick(records:[record],jobs:[job],physical:host.physical,now:edge)
    expiryWork.replies=[reply(sample(edge))]
    expiring.tick(records:[record],jobs:[job],physical:host.physical,now:edge+1)
    guard expiryWork.requests.count==1,expiring.epoch(now:expiry-1)==hash,expiring.epoch(now:expiry)==nil,
          expiring.applying(to:host,now:expiry).vmAvailable==nil else {fatalError("VM observation must finish within its original lease without authorizing another read")}
    // Renewal may authorize later work, but cannot rescue a result from an
    // earlier submission that arrives exactly at that submission's expiry.
    let lateWork=VMObservationFixture(),late=ReadOnlyVMResources(work:lateWork)
    late.tick(records:[record],jobs:[job],physical:host.physical,now:edge)
    var extended=job
    try extended.lease.renew(now:edge+1)
    lateWork.replies=[reply(sample(expiry-1))]
    late.tick(records:[record],jobs:[extended],physical:host.physical,now:expiry)
    guard lateWork.requests.count==1,late.epoch(now:expiry)==nil else {
        fatalError("Renewal extended an expired original VM observation or replayed its failed target")
    }
    let retainedWork=VMObservationFixture(),retained=ReadOnlyVMResources(work:retainedWork)
    retained.tick(records:[record],jobs:[job],physical:host.physical,now:edge)
    retainedWork.replies=[reply(sample(expiry-2))]
    retained.tick(records:[record],jobs:[extended],physical:host.physical,now:expiry-1)
    guard retained.applying(to:host,now:expiry-1).vmSampledAt==expiry-2 else {
        fatalError("Valid original lease lost a fresh completed VM read")
    }
    retained.tick(records:[record],jobs:[extended],physical:host.physical,now:expiry)
    guard retained.epoch(now:expiry)==nil,retained.applying(to:host,now:expiry).vmAvailable==nil else {
        fatalError("Renewal prolonged an older VM cache after original lease expiry")
    }
    let rollbackWork=VMObservationFixture(),rollback=ReadOnlyVMResources(work:rollbackWork)
    rollback.tick(records:[record],jobs:[job],physical:host.physical,now:1000)
    rollback.tick(records:[record],jobs:[job],physical:host.physical,now:999)
    rollbackWork.replies=[reply(sample())]
    rollback.tick(records:[record],jobs:[job],physical:host.physical,now:3000)
    guard rollbackWork.requests.count==1,rollback.epoch(now:3000)==nil else {fatalError("VM observation clock rollback reopened pending work")}
    let capacityWork=VMObservationFixture(),capacity=ReadOnlyVMResources(work:capacityWork)
    capacityWork.capacity=true;capacity.tick(records:[record],jobs:[job],physical:host.physical,now:1000)
    capacityWork.capacity=false;capacity.tick(records:[record],jobs:[job],physical:host.physical,now:1001)
    guard capacityWork.requests.count==1 else {fatalError("Unsubmitted capacity refusal lost its original target")}
    // Development entry returns before any installed metadata or daemon call.
    guard try VMObservationConfiguration.load(directory:FileManager.default.temporaryDirectory)==nil else {fatalError("Development VM observation obtained installed policy")}
    for kind in 0..<3 {
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        let configuration=AsyncVMObservationConfiguration {
            entered.signal();guard release.wait(timeout:.now()+2) == .success else {throw RuntimeError.deadline}
            if kind==1 {throw RuntimeError.identity}
            return kind==2 ? VMObservationFixture():nil
        }
        guard entered.wait(timeout:.now()+1) == .success,configuration.poll()==nil else {fatalError("VM configuration blocked or published before its original worker")}
        release.signal()
        let end=ProcessInfo.processInfo.systemUptime+1
        var result:VMObservationConfigurationOutcome?
        while result==nil,ProcessInfo.processInfo.systemUptime<end {result=configuration.poll();Thread.sleep(forTimeInterval:0.001)}
        switch (kind,result) {
        case (0,.unconfigured?),(1,.unavailable?),(2,.configured? ):break
        default:fatalError("VM configuration lost its exact one-shot outcome")
        }
        guard configuration.poll()==nil else {fatalError("VM configuration replayed its result")}
    }
    print("PASS: readonly VM observation retains one original work slot, exact owned target/lease, envelope clocks and uncertainty; no task or lifecycle operations")
}
