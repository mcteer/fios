import Foundation
import CSQLite

private final class DrainControllerClock:@unchecked Sendable {
    var value:TimeInterval=1
    var onMaintenanceCommit:(()->Void)?
}

func runServiceDrainControllerTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),epoch=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let cache=ServiceDrainObservationCache(),clock=DrainControllerClock()
    let controller=try ServiceDrainController(journal:journal,tasks:tasks,managerEpoch:epoch,observations:cache,uptime:{clock.value})
    let identity=ServiceIdentity(pid:42,start:100,sha256:String(repeating:"b",count:64))
    func job(in journal:Journal)throws->String {
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
    let owned=try job(in:journal),other=try job(in:journal)
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
    clock.value = .nan
    do {_=try controller.begin(service:.mlx,role:.operator,now:1000,uptime:1000);fatalError("Invalid policy clock accepted")}
    catch ServiceError.invalid {}
    guard try journal.recordedDesired(service:.mlx)==nil,controller.status(service:.mlx)==nil,
          try journal.jobs().first(where:{$0.id==owned})?.state == .running else {
        fatalError("Invalid drain clock changed durable intent before refusing")
    }
    clock.value=1
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
    let queued=try job(in:journal)
    cache.publish(try snapshot(jobs:[queued],requests:[other],stamp:1001),for:.mlx)
    guard try controller.poll(service:.mlx,now:1001,uptime:1001).state == .refused(.scopeChanged),
          try journal.jobs().first(where:{$0.id==queued})?.state == .running else {throw JournalError.conflict}
    cache.publish(try snapshot(jobs:[owned],requests:[other]),for:.mlx)
    _=try controller.begin(service:.mlx,role:.operator,now:1000,uptime:1000)
    clock.value=61
    cache.publish(try snapshot(jobs:[],requests:[other],stamp:1001),for:.mlx)
    guard try controller.poll(service:.mlx,now:1001,uptime:61000).state == .refused(.deadline) else {throw JournalError.conflict}
    cache.publish(try snapshot(jobs:[],requests:[other],stamp:1002),for:.mlx)
    _=try controller.begin(service:.mlx,role:.operator,now:1002,uptime:61001)
    let newerRequest=UUID().uuidString.lowercased()
    try journal.claim(job:queued,attempt:0,model:"fixture/model",requestID:newerRequest)
    try journal.markUncertain(job:queued,attempt:0)
    cache.publish(try snapshot(jobs:[],requests:[other,newerRequest],stamp:1003),for:.mlx)
    let expanded=try controller.poll(service:.mlx,now:1003,uptime:61002)
    guard expanded.state == .refused(.scopeChanged),expanded.revokeOwned.isEmpty,
          try journal.uncertainCount()==2,try journal.desired(service:"mlx")=="maintenance" else {
        fatalError("Drain expanded to include a new durable native attempt")
    }
    // The original controller routes returned IDs to real TaskController cancellation.
    // A complete but externally busy source must close admission without touching the job.
    cache.publish(try snapshot(jobs:[queued],requests:[other,newerRequest],stamp:1004,external:true),for:.mlx)
    let external=try controller.begin(service:.mlx,role:.operator,now:1004,uptime:61003)
    guard external.state == .refused(.activeWork),external.revokeOwned.isEmpty,
          try journal.jobs().first(where:{$0.id==queued})?.state == .running,
          try journal.uncertainCount()==2,try journal.desired(service:"mlx")=="maintenance" else {
        fatalError("Controller revoked durable owned work after external refusal")
    }
    let fenceDirectory=directory.appendingPathComponent("batch-writer-fence"),fenceJournal=try Journal(directory:fenceDirectory)
    let fenceTasks=TaskController(journal:fenceJournal,broker:ModelBroker(journal:fenceJournal)),fenceCache=ServiceDrainObservationCache()
    let first=try job(in:fenceJournal),second=try job(in:fenceJournal)
    try fenceJournal.claim(job:first,attempt:0,model:"fixture/model",requestID:first)
    try fenceJournal.markUncertain(job:first,attempt:0)
    let fenceClock=DrainControllerClock()
    let fenced=try ServiceDrainController(journal:fenceJournal,tasks:fenceTasks,managerEpoch:epoch,observations:fenceCache,
                                         uptime:{fenceClock.value},didPersistMaintenance:{fenceClock.onMaintenanceCommit?()})
    var writer:OpaquePointer?
    guard sqlite3_open_v2(fenceDirectory.appendingPathComponent("state.sqlite").path,&writer,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {throw JournalError.storage}
    defer {sqlite3_close(writer)}
    fenceCache.publish(try snapshot(jobs:[first,second],requests:[first],stamp:1005),for:.mlx)
    guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    do {_=try fenced.begin(service:.mlx,role:.operator,now:1005,uptime:61004);fatalError("Contended maintenance write was accepted")}
    catch JournalError.storage {}
    guard fenced.status(service:.mlx)==nil,!fenceTasks.cancellationPending(for:first),!fenceTasks.cancellationPending(for:second),
          sqlite3_exec(writer,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {fatalError("Failed maintenance write advertised deferred cancellation")}
    fenceClock.onMaintenanceCommit={
        guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {fatalError("Fixture could not hold writer fence after maintenance commit")}
    }
    do {_=try fenced.begin(service:.mlx,role:.operator,now:1005,uptime:61004);fatalError("Contended drain reported complete durable cancellation")}
    catch ServiceDrainBeginError.cancellationDeferred(let progress) {
        guard progress.state == .draining,Set(progress.revokeOwned)==Set([first,second]) else {throw ServiceError.invalid}
    }
    fenceClock.onMaintenanceCommit=nil
    guard fenceTasks.cancellationPending(for:first),fenceTasks.cancellationPending(for:second),
          try fenceJournal.uncertainCount()==1,try fenceJournal.desired(service:"mlx")=="maintenance" else {
        fatalError("Writer-contended drain stranded a sibling cancellation or changed uncertain custody")
    }
    guard sqlite3_exec(writer,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    let fenceOrbScope=try ServiceAffectedScope(service:.orbstack,identity:identity,managerEpoch:epoch,nativeEpoch:"native-fixture",
        nativeScopeDigest:String(repeating:"d",count:64),runtimeScopeDigest:String(repeating:"e",count:64),
        ownedJobs:[],unresolvedManagedRequests:[first],sampledAt:1006)
    fenceCache.publish(ServiceDrainSnapshot(scope:fenceOrbScope,nativeIdle:false,externalNativeWork:false,unmanagedRuntimeWork:false),for:.orbstack)
    guard try fenced.begin(service:.orbstack,role:.operator,now:1006,uptime:61005).state == .draining else {throw ServiceError.invalid}
    fenceCache.publish(nil,for:.orbstack)
    guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    do {try fenced.pollAll(now:1006,uptime:61005);fatalError("Contended multi-service drain did not report storage error")}catch JournalError.storage {}
    guard fenced.status(service:.orbstack)?.state == .refused(.activityUnknown),
          try fenceJournal.uncertainCount()==1 else {fatalError("MLX writer fence suppressed independent OrbStack source refusal")}
    guard sqlite3_exec(writer,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    try fenced.pollAll(now:1007,uptime:61006)
    guard try fenceJournal.jobs().allSatisfy({$0.state == .removed}),
          try fenceJournal.uncertainCount()==1 else {fatalError("Deferred drain cancellation did not retire exact local jobs")}
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
    failedCache.publish(try snapshot(jobs:[stopping],requests:[],stamp:1002),for:.mlx)
    let restoredScope=try failed.poll(service:.mlx,now:1002,uptime:1002)
    guard restoredScope.state == .refused(.activityUnknown),restoredScope.revokeOwned.isEmpty,
          try failedJournal.jobs().first(where:{$0.id==stopping})?.state == .stopping,
          try failedJournal.desired(service:"mlx")=="maintenance" else {
        fatalError("Restored source scope revived an attempt or changed durable cleanup")
    }
    let isolatedCache=ServiceDrainObservationCache()
    let mlx=try snapshot(jobs:[],requests:[],idle:true)
    let orbScope=try ServiceAffectedScope(service:.orbstack,identity:identity,managerEpoch:epoch,nativeEpoch:"fixture-native",
        nativeScopeDigest:String(repeating:"d",count:64),runtimeScopeDigest:String(repeating:"e",count:64),
        ownedJobs:[],unresolvedManagedRequests:[],sampledAt:1000)
    let orb=ServiceDrainSnapshot(scope:orbScope,nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:false)
    isolatedCache.publish(mlx,for:.mlx);isolatedCache.publish(orb,for:.orbstack)
    let mlxGeneration=isolatedCache.versionedSnapshot(for:.mlx)?.generation
    isolatedCache.publish(mlx,for:.orbstack)
    guard isolatedCache.snapshot(for:.orbstack)==nil,
          isolatedCache.versionedSnapshot(for:.mlx)?.generation==mlxGeneration,
          isolatedCache.snapshot(for:.mlx)?.scope.digest==mlx.scope.digest else {
        fatalError("Foreign service snapshot retained target readiness or changed source scope")
    }
    print("PASS: source-cache-bound operator drain persists maintenance before owned revoke, retains independent uncertainty/jobs, refuses hidden claims/new scope, expires at60s and rechecks ready; synthetic source, no native actuator")
}
