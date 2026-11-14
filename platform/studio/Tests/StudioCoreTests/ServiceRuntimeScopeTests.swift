import Foundation
import Darwin

// Ordinary observation-before-job-publication ordering. No runtime or actuator.
func runServiceRuntimeScopeTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),cache=ServiceDrainObservationCache()
    let epoch=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
    let identity=ServiceIdentity(pid:42,start:100,sha256:String(repeating:"b",count:64))
    let drain=try ServiceDrainController(journal:journal,tasks:TaskController(journal:journal,broker:ModelBroker(journal:journal)),managerEpoch:epoch,observations:cache)
    let force=try ServiceForceController(journal:journal,managerEpoch:epoch,observations:cache)
    func snapshot(_ service:ManagedService = .orbstack,jobs:[String]=[],stamp:Int64=1000)throws->ServiceDrainSnapshot {
        ServiceDrainSnapshot(scope:try ServiceAffectedScope(service:service,identity:identity,managerEpoch:epoch,nativeEpoch:"runtime-scope-fixture",
            nativeScopeDigest:String(repeating:"c",count:64),runtimeScopeDigest:service == .orbstack ? String(repeating:"d",count:64):nil,
            ownedJobs:jobs,unresolvedManagedRequests:[],sampledAt:stamp),nativeIdle:true,externalNativeWork:false,
            unmanagedRuntimeWork:service == .orbstack ? false:nil)
    }
    cache.publish(try snapshot(),for:.orbstack)
    let id=UUID().uuidString.lowercased()
    let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"e",count:64),created:1000)
    _=try journal.reserveSandbox(job:job,configuration:SandboxConfiguration(job:id,nonce:String(repeating:"f",count:64),image:"sha256:"+String(repeating:"a",count:64),memory:512<<20,cpus:1))
    var missing=false
    do {
        _=try drain.begin(service:.orbstack,role:.operator,now:1000,uptime:1000)
        FileHandle.standardError.write(Data("DRAIN_ACCEPTED_SCOPE_BEFORE_DURABLE_SANDBOX\n".utf8));missing=true
    }catch ServiceError.invalid {}
    do {
        _=try force.prepare(service:.orbstack,role:.operator,now:1000)
        FileHandle.standardError.write(Data("FORCE_ACCEPTED_SCOPE_BEFORE_DURABLE_SANDBOX\n".utf8));missing=true
    }catch ServiceError.invalid {}
    if missing {exit(77)} // Precise baseline witness, never a crash/timeout.
    guard try journal.recordedDesired(service:.orbstack)==nil,
          try journal.jobs().first(where:{$0.id==id})?.state == .reserved else {throw RuntimeError.identity}
    // A sandbox without a native request does not become an MLX lifecycle job.
    cache.publish(try snapshot(.mlx),for:.mlx)
    _=try force.prepare(service:.mlx,role:.operator,now:1000)
    cache.publish(try snapshot(jobs:[id]),for:.orbstack)
    let challenge=try force.prepare(service:.orbstack,role:.operator,now:1000)
    guard try force.confirm(service:.orbstack,role:.operator,token:challenge.token,scopeDigest:challenge.scopeDigest,now:1000) == .forceQuit(identity),
          try journal.jobs().first(where:{$0.id==id})?.state == .reserved else {throw RuntimeError.identity}
    let progress=try drain.begin(service:.orbstack,role:.operator,now:1000,uptime:1000)
    guard progress.state == .draining,progress.revokeOwned==[id],
          try journal.jobs().first(where:{$0.id==id})?.state == .revoking else {throw RuntimeError.identity}
    cache.publish(try snapshot(stamp:1001),for:.orbstack)
    guard try drain.poll(service:.orbstack,now:1001,uptime:1001).state == .refused(.activityUnknown) else {throw RuntimeError.identity}
    // Trusted fixture receipt: create was never issued. Historical removed
    // rows do not remain an active runtime job or prove native terminality.
    try journal.confirmSandboxAbsent(job:id)
    for state:JobState in [.stopping,.removing,.removed] {try journal.transitionJob(id:id,to:state,now:1001)}
    cache.publish(try snapshot(stamp:1002),for:.orbstack)
    guard try drain.begin(service:.orbstack,role:.operator,now:1002,uptime:1002).state == .ready(identity) else {throw RuntimeError.identity}
    _=try force.prepare(service:.orbstack,role:.operator,now:1002)
    try runRecoveredRuntimeScopeTests(directory:directory.appendingPathComponent("recovered"))
    print("PASS: runtime scopes account for durable retained sandbox jobs, preserve service independence and exclude removed history; metadata only, no actuator")
}

private func runRecoveredRuntimeScopeTests(directory:URL)throws {
    let id=UUID().uuidString.lowercased(),request=UUID().uuidString.lowercased()
    let owner=String(repeating:"a",count:64)
    do {
        let before=try Journal(directory:directory)
        let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:1000)
        var sandbox=try before.reserveSandbox(job:job,configuration:SandboxConfiguration(job:id,nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1))
        // Durable checkpoint before a possible runtime create. No runtime is
        // called; absence cannot later prove that this operation was not sent.
        sandbox.createIssued=true;try before.saveSandbox(sandbox)
        try before.transitionJob(id:id,to:.creating,now:1000)
        try before.claim(job:id,attempt:0,model:"fixture/runtime-recovery",requestID:request)
        try before.markUncertain(job:id,attempt:0)
    }
    let recovered=try Journal(directory:directory),cache=ServiceDrainObservationCache()
    guard try recovered.jobs().first(where:{$0.id==id})?.state == .reconciling,
          try recovered.uncertainCount()==1 else {throw RuntimeError.identity}
    let epoch=UUID().uuidString.lowercased(),identity=ServiceIdentity(pid:42,start:100,sha256:String(repeating:"e",count:64))
    let scope=try ServiceAffectedScope(service:.orbstack,identity:identity,managerEpoch:epoch,nativeEpoch:"recovered-runtime-fixture",
        nativeScopeDigest:String(repeating:"f",count:64),runtimeScopeDigest:String(repeating:"a",count:64),
        ownedJobs:[],unresolvedManagedRequests:[request],sampledAt:1001)
    cache.publish(ServiceDrainSnapshot(scope:scope,nativeIdle:false,externalNativeWork:false,unmanagedRuntimeWork:false),for:.orbstack)
    let drain=try ServiceDrainController(journal:recovered,tasks:TaskController(journal:recovered,broker:ModelBroker(journal:recovered)),managerEpoch:epoch,observations:cache)
    let force=try ServiceForceController(journal:recovered,managerEpoch:epoch,observations:cache)
    do {_=try drain.begin(service:.orbstack,role:.operator,now:1001,uptime:1001);throw RuntimeError.identity}
    catch ServiceError.invalid {}
    do {_=try force.prepare(service:.orbstack,role:.operator,now:1001);throw RuntimeError.identity}
    catch ServiceError.invalid {}
    do {try recovered.confirmSandboxAbsent(job:id);throw RuntimeError.identity}
    catch JournalError.conflict {}
    guard try recovered.recordedDesired(service:.orbstack)==nil,
          try recovered.jobs().first(where:{$0.id==id})?.state == .reconciling,
          try recovered.sandboxRecords().first(where:{$0.configuration.job==id})?.createIssued == true,
          try recovered.sandboxRecords().first(where:{$0.configuration.job==id})?.removalProven == false,
          try recovered.unresolvedRequestIDs()==[request],try recovered.uncertainCount()==1 else {throw RuntimeError.identity}
    print("PASS: recovered unresolved create remains in runtime scope and independent native uncertainty survives all refusals; metadata only")
}
