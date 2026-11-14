import Foundation

private final class DrainControllerClock:@unchecked Sendable {var value:TimeInterval=1}

func runServiceDrainControllerTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),epoch=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let cache=ServiceDrainObservationCache(),clock=DrainControllerClock()
    let controller=try ServiceDrainController(journal:journal,tasks:tasks,managerEpoch:epoch,observations:cache,uptime:{clock.value})
    let identity=ServiceIdentity(pid:42,start:100,sha256:String(repeating:"b",count:64))
    func job()throws->String {
        let id=UUID().uuidString.lowercased()
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"c",count:64),created:1000))
        try journal.transitionJob(id:id,to:.running,now:1000);return id
    }
    func snapshot(jobs:[String],requests:[String],source:String="native-fixture",manager:String?=nil,stamp:Int64=1000,external:Bool?=false,idle:Bool?=false)throws->ServiceDrainSnapshot {
        let scope=try ServiceAffectedScope(service:.mlx,identity:identity,managerEpoch:manager ?? epoch,nativeEpoch:source,nativeScopeDigest:String(repeating:"d",count:64),runtimeScopeDigest:nil,ownedJobs:jobs,unresolvedManagedRequests:requests,sampledAt:stamp)
        return ServiceDrainSnapshot(scope:scope,nativeIdle:idle,externalNativeWork:external,unmanagedRuntimeWork:nil)
    }
    do {_=try controller.begin(service:.mlx,role:.operator,now:1000,uptime:1000);throw RuntimeError.identity}
    catch ServiceError.stale {}
    guard try journal.recordedDesired(service:.mlx)==nil else {throw JournalError.conflict}
    let owned=try job(),other=try job()
    try journal.claim(job:other,attempt:0,model:"fixture/model",requestID:other)
    try journal.markUncertain(job:other,attempt:0)
    cache.publish(try snapshot(jobs:[owned],requests:[owned]),for:.mlx)
    do {
        _=try controller.begin(service:.mlx,role:.operator,now:1000,uptime:1000)
        FileHandle.standardError.write(Data("DRAIN_ACCEPTED_SUBSTITUTED_DURABLE_REQUEST\n".utf8));throw JournalError.conflict
    }catch ServiceError.invalid {}
    cache.publish(try snapshot(jobs:[owned],requests:[other]),for:.mlx)
    for role:ControlRole in [.observer,.task,.sandbox] {
        do {_=try controller.begin(service:.mlx,role:role,now:1000,uptime:1000);throw RuntimeError.identity}
        catch ServiceError.invalid {}
    }
    guard try journal.recordedDesired(service:.mlx)==nil else {throw JournalError.conflict}
    let began=try controller.begin(service:.mlx,role:.operator,now:1000,uptime:1000)
    guard began.state == .draining,began.revokeOwned==[owned],
          try journal.desired(service:"mlx")=="maintenance",
          try journal.jobs().first(where:{$0.id==owned})?.state == .removed,
          try journal.jobs().first(where:{$0.id==other})?.state == .running,
          try journal.uncertainCount()==1 else {throw JournalError.conflict}
    // A producer cannot hide durable uncertainty to turn drain readiness green.
    cache.publish(try snapshot(jobs:[],requests:[],stamp:1001,idle:true),for:.mlx)
    guard try controller.poll(service:.mlx,now:1001,uptime:1001).state == .refused(.activityUnknown),
          try journal.uncertainCount()==1 else {
        FileHandle.standardError.write(Data("DRAIN_HID_DURABLE_UNCERTAINTY\n".utf8));throw JournalError.conflict
    }
    cache.publish(try snapshot(jobs:[],requests:[other],stamp:1002,idle:true),for:.mlx)
    guard try controller.poll(service:.mlx,now:1002,uptime:1002).state == .refused(.activityUnknown) else {throw JournalError.conflict}
    // Explicit new operator begin is required; a different queued job cannot
    // be captured by an earlier drain just because it appeared in the cache.
    cache.publish(try snapshot(jobs:[owned],requests:[other]),for:.mlx)
    _=try controller.begin(service:.mlx,role:.operator,now:1000,uptime:1000)
    let queued=try job()
    cache.publish(try snapshot(jobs:[queued],requests:[other],stamp:1001),for:.mlx)
    guard try controller.poll(service:.mlx,now:1001,uptime:1001).state == .refused(.scopeChanged),
          try journal.jobs().first(where:{$0.id==queued})?.state == .running else {throw JournalError.conflict}
    cache.publish(try snapshot(jobs:[owned],requests:[other]),for:.mlx)
    _=try controller.begin(service:.mlx,role:.operator,now:1000,uptime:1000)
    clock.value=61
    cache.publish(try snapshot(jobs:[],requests:[other],stamp:1001),for:.mlx)
    guard try controller.poll(service:.mlx,now:1001,uptime:61000).state == .refused(.deadline) else {throw JournalError.conflict}
    let readyJournal=try Journal(directory:directory.appendingPathComponent("ready")),readyCache=ServiceDrainObservationCache()
    let ready=try ServiceDrainController(journal:readyJournal,tasks:TaskController(journal:readyJournal,broker:ModelBroker(journal:readyJournal)),managerEpoch:epoch,observations:readyCache)
    readyCache.publish(try snapshot(jobs:[],requests:[],idle:true),for:.mlx)
    guard try ready.begin(service:.mlx,role:.operator,now:1000,uptime:1000).state == .ready(identity) else {throw JournalError.conflict}
    readyCache.publish(try snapshot(jobs:[],requests:[],stamp:1001,external:true,idle:false),for:.mlx)
    guard try ready.poll(service:.mlx,now:1001,uptime:1001).state == .refused(.activeWork) else {throw JournalError.conflict}
    // A valid retained cleanup phase makes cancellation fail. Maintenance
    // must already be durable, and a producer cannot hide the unfinished job.
    let failedJournal=try Journal(directory:directory.appendingPathComponent("failed-revoke")),failedCache=ServiceDrainObservationCache()
    let failed=try ServiceDrainController(journal:failedJournal,tasks:TaskController(journal:failedJournal,broker:ModelBroker(journal:failedJournal)),managerEpoch:epoch,observations:failedCache)
    let stopping=UUID().uuidString.lowercased()
    _=try failedJournal.reserveJob(DurableJob(id:stopping,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"e",count:64),created:1000))
    for state:JobState in [.running,.revoking,.stopping] {try failedJournal.transitionJob(id:stopping,to:state,now:1000)}
    failedCache.publish(try snapshot(jobs:[stopping],requests:[]),for:.mlx)
    do {_=try failed.begin(service:.mlx,role:.operator,now:1000,uptime:1000);throw RuntimeError.identity}
    catch JournalError.conflict {}
    guard try failedJournal.desired(service:"mlx")=="maintenance" else {
        FileHandle.standardError.write(Data("DRAIN_REVOKED_BEFORE_MAINTENANCE\n".utf8));throw JournalError.conflict
    }
    failedCache.publish(try snapshot(jobs:[],requests:[],stamp:1001,idle:true),for:.mlx)
    guard try failed.poll(service:.mlx,now:1001,uptime:1001).state == .refused(.activityUnknown) else {
        FileHandle.standardError.write(Data("DRAIN_HID_OWNED_LEDGER_JOB\n".utf8));throw JournalError.conflict
    }
    print("PASS: source-cache-bound operator drain persists maintenance before owned revoke, retains independent uncertainty/jobs, refuses hidden claims/new scope, expires at60s and rechecks ready; synthetic source, no native actuator")
}
