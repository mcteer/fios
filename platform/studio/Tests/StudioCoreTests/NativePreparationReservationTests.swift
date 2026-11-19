import Foundation
import CSQLite

private final class PreparationReservationSource:NativePreparationReserving,@unchecked Sendable {
    enum Mode:CaseIterable {case healthy,lineageFailure,lineageMismatch,lineagePredatesReceipt,unknownClock,oldClock,futureClock,expired,foreignPeer,foreignModel,equivalentUnicode,futureLocalTime,invalidStamp}
    let peer:NativeControlPeer
    let mode:Mode
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var reserves=0,reads=0
    var counts:(Int,Int) {lock.lock();defer {lock.unlock()};return (reserves,reads)}
    init(peer:NativeControlPeer,mode:Mode) {self.peer=peer;self.mode=mode}
    func reservePreparation(instance:String,correlationID:String,model:String,lifetimeMilliseconds:UInt32,after sequence:UInt64)throws->NativePreparationSample {
        lock.lock();reserves+=1;lock.unlock();entered.signal()
        guard release.wait(timeout:.now()+2) == .success else {throw NativeControlError.deadline}
        let now=HostResources.nowMilliseconds(),start=now+(mode == .futureLocalTime ? 100:mode == .expired ? -20:0)
        let sourceTime:Int64? = mode == .unknownClock ? nil:mode == .oldClock ? now-1000:mode == .futureClock ? now+100:mode == .invalidStamp ? 0:start
        let actualPeer=mode == .foreignPeer ? NativeControlPeer(pid:peer.pid+1,start:peer.start,executable:peer.executable):peer
        let actualModel=mode == .foreignModel ? "fixture/other":mode == .equivalentUnicode ? "fixture/cafe\u{301}":model
        return NativePreparationSample(peer:actualPeer,requestedAt:start,receivedAt:mode == .futureLocalTime ? start:now,
            acknowledgement:NativePreparationAcknowledgement(operation:.reserve,instance:instance,correlationID:correlationID,model:actualModel,
                rootSequence:UInt64.max,sampleSequence:sequence+1,sourceSampledAt:sourceTime,lifetimeMilliseconds:lifetimeMilliseconds))
    }
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample {
        lock.lock();reads+=1;lock.unlock()
        if mode == .lineageFailure {throw NativeControlError.unavailable}
        let stamp=HostResources.nowMilliseconds()-(mode == .lineagePredatesReceipt ? 1000:0)
        return NativeRequestLineageSample(peer:peer,sampledAt:stamp,lineage:NativeRequestLineage(instance:instance,
            correlationID:correlationID,sampleSequence:12,rootSequence:mode == .lineageMismatch ? 7:UInt64.max,
            found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:1,active:0,responding:0))
    }
}
func runNativePreparationReservationTests()throws {
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    for mode in PreparationReservationSource.Mode.allCases {
        let source=PreparationReservationSource(peer:peer,mode:mode),began=ProcessInfo.processInfo.systemUptime
        let pending=PendingNativePreparation(source:source,instance:String(repeating:"a",count:32),correlationID:String(repeating:"b",count:64),
            model:"fixture/caf\u{e9}",lifetimeMilliseconds:mode == .expired ? 1:5000,after:10)
        guard ProcessInfo.processInfo.systemUptime-began<0.1,source.entered.wait(timeout:.now()+2) == .success,pending.take()==nil else {fatalError("Preparation RPC blocked serialized caller")}
        source.release.signal()
        var reply:Result<PreparedNativeReservation,NativeControlError>?
        let end=ProcessInfo.processInfo.systemUptime+2
        while reply==nil && ProcessInfo.processInfo.systemUptime<end {reply=pending.take();if reply==nil {usleep(1000)}}
        guard let reply,pending.take()==nil,source.counts.0==1 else {fatalError("Preparation result lost/replayed or reservation retried")}
        switch mode {
        case .foreignPeer,.foreignModel,.equivalentUnicode,.futureLocalTime,.invalidStamp:
            guard case .failure=reply,source.counts.1==0 else {fatalError("Foreign/malformed preparation entered original identity scope")}
        default:
            let value=try reply.get(),registration=value.registration
            guard registration.acknowledgement.rootSequence==UInt64.max,source.counts.1==1 else {fatalError("Verified reservation identity lost or lineage retried")}
            let missing=mode == .lineageFailure || mode == .lineageMismatch || mode == .lineagePredatesReceipt
            guard (value.lineage==nil)==missing else {fatalError("Failed/mismatched lineage became coherent")}
            let current=mode == .healthy || missing
            guard registration.leaseWindowIsCurrent(now:registration.verifiedAt)==current,
                  !registration.leaseWindowIsCurrent(now:registration.verifiedAt-1),
                  !registration.leaseWindowIsCurrent(now:registration.sample.requestedAt+Int64(registration.acknowledgement.lifetimeMilliseconds)) else {fatalError("Receipt timing reset/extended an original native lease")}
        }
    }
    try runPreparationIdentityPersistenceTests(peer:peer)
    try runPreparationPlanBindingTests(peer:peer)
    try runPreparationPlanBindingTests(peer:peer,transientBeforeCapture:true)
    try runOwnedPreparationCoherenceTests(peer:peer)
    print("PASS: finite off-loop original preparation identity, once-only RPC/result, exact Unicode/peer scope, optional lineage and nonrenewable timing; no native authority")
}

private func runPreparationIdentityPersistenceTests(peer:NativeControlPeer)throws {
    for mode in [PreparationReservationSource.Mode.lineageFailure,.expired] {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let job=UUID().uuidString.lowercased(),older=UUID().uuidString.lowercased(),now=HostResources.nowMilliseconds()
        let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
            managerEpoch:"00000000-0000-4000-8000-000000000002",nativeEpoch:String(repeating:"a",count:32),
            canonicalModel:"fixture/caf\u{e9}",nativeModel:"fixture/caf\u{e9}",sequence:1,sampledAt:now)
        let source=PreparationReservationSource(peer:peer,mode:mode);source.release.signal()
        let pending=PendingNativePreparation(source:source,instance:scope.nativeEpoch,correlationID:try scope.nativeRequestCorrelationID(job:job,attempt:0),
            model:scope.nativeModel,lifetimeMilliseconds:mode == .expired ? 1:5000,after:10)
        var result:Result<PreparedNativeReservation,NativeControlError>?
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while result==nil && ProcessInfo.processInfo.systemUptime<deadline {result=pending.take();if result==nil {usleep(1000)}}
        guard let result else {fatalError("Preparation persistence receipt unavailable")}
        let registration=try result.get().registration,late=registration.verifiedAt+6000
        guard !registration.leaseWindowIsCurrent(now:late) else {fatalError("Late persistence renewed native timing")}
        do {
            let journal=try Journal(directory:directory)
            for id in [job,older] {try journal.claim(job:id,attempt:0,model:scope.canonicalModel,scope:scope);try journal.markDispatched(job:id,attempt:0);try journal.markUncertain(job:id,attempt:0)}
            // Two handles in this isolated test process reproduce a real SQL
            // writer outage; no second application or production DB is opened.
            var blocker:OpaquePointer?
            guard sqlite3_open(directory.appendingPathComponent("state.sqlite").path,&blocker)==SQLITE_OK,let blocker else {fatalError("Preparation storage fixture unavailable")}
            guard sqlite3_exec(blocker,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {sqlite3_close(blocker);fatalError("Preparation storage fixture not locked")}
            do {
                _=try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:registration,now:late)
                sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil);sqlite3_close(blocker)
                fatalError("Preparation identity fixture did not encounter real writer contention")
            } catch JournalError.storage {}
            guard sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil)==SQLITE_OK,sqlite3_close(blocker)==SQLITE_OK else {fatalError("Preparation writer fixture release failed")}
            guard source.counts.0==1,pending.take()==nil else {fatalError("Storage failure reissued native preparation")}
            guard try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:registration,now:late) else {fatalError("Late original preparation identity lost")}
            _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:nil,now:late+1)
            guard try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:registration,now:late+2),
                  try journal.originalNativeRoot(job:job,attempt:0,scope:scope,peer:peer)==UInt64.max,
                  try journal.uncertainCount()==2 else {fatalError("Original receipt replaced uncertainty with live/native authority")}
        }
        do {
            let restored=try Journal(directory:directory)
            guard try restored.originalNativeRoot(job:job,attempt:0,scope:scope,peer:peer)==UInt64.max,
                  try restored.uncertainCount()==2,try restored.unresolvedCount()==2 else {fatalError("Preparation identity/older uncertainty lost across restart")}
        }
        guard source.counts.0==1,source.counts.1==1 else {fatalError("Persistence retried original native operations")}
        for fence in ["clock","peer","rollback"] {
            let fencedDirectory=directory.appendingPathComponent(fence),journal=try Journal(directory:fencedDirectory)
            try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
            try journal.markDispatched(job:job,attempt:0)
            try journal.markUncertain(job:job,attempt:0)
            _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:nil,now:late+10)
            if fence=="clock" {
                _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:nil,now:late+9)
            }else if fence=="peer" {
                let changed=NativeControlPeer(pid:peer.pid+1,start:peer.start,executable:peer.executable)
                _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:changed,sample:nil,now:late+11)
            }
            guard try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:registration,now:fence=="rollback" ? late+9:late+12) else {fatalError("Fenced original preparation identity was discarded")}
            var reader:OpaquePointer?,row:OpaquePointer?
            guard sqlite3_open_v2(fencedDirectory.appendingPathComponent("state.sqlite").path,&reader,SQLITE_OPEN_READONLY,nil)==SQLITE_OK,let reader else {throw JournalError.storage}
            defer {sqlite3_close(reader)}
            guard sqlite3_prepare_v2(reader,"SELECT payload FROM native_lineages",-1,&row,nil)==SQLITE_OK,let row else {throw JournalError.storage}
            defer {sqlite3_finalize(row)}
            guard sqlite3_step(row)==SQLITE_ROW,let bytes=sqlite3_column_text(row,0) else {throw JournalError.storage}
            let checkpoint=Data(String(cString:bytes).utf8)
            guard
                  let value=try JSONSerialization.jsonObject(with:checkpoint) as? [String:Any],
                  value["root"] as? String==String(UInt64.max),value["fenced"] as? Bool==true,
                  try journal.originalNativeRoot(job:job,attempt:0,scope:scope,peer:peer)==nil,
                  try journal.unresolvedCount()==1,try journal.uncertainCount()==1 else {fatalError("Historical preparation identity cleared a live-source fence")}
            var consumer=try NativeRequestLineageConsumer(scope:scope,job:job,attempt:0,peer:peer,checkpoint:checkpoint)
            guard case .unknown=consumer.accept(nil,now:late+20),consumer.fenced else {fatalError("Restored historical identity regained live authority")}
        }
    }
}

private func runPreparationPlanBindingTests(peer:NativeControlPeer,transientBeforeCapture:Bool=false)throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),job=UUID().uuidString.lowercased(),other=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:"00000000-0000-4000-8000-000000000002",nativeEpoch:String(repeating:"a",count:32),
        canonicalModel:"fixture/model",nativeModel:"fixture/model",sequence:1,sampledAt:HostResources.nowMilliseconds())
    _=try journal.reserveJob(DurableJob(id:job,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"c",count:64),requestHash:String(repeating:"d",count:64),created:scope.sampledAt))
    try journal.transitionJob(id:job,to:.running,now:scope.sampledAt)
    try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
    let plan=try journal.planWorkerStart(job:job,attempt:0);try journal.markDispatched(job:job,attempt:0)
    let source=PreparationReservationSource(peer:peer,mode:.healthy);source.release.signal()
    let pending=PendingNativePreparation(source:source,instance:scope.nativeEpoch,correlationID:try scope.nativeRequestCorrelationID(job:job,attempt:0),model:scope.nativeModel,after:10)
    var reply:Result<PreparedNativeReservation,NativeControlError>?
    let deadline=ProcessInfo.processInfo.systemUptime+2
    while reply==nil && ProcessInfo.processInfo.systemUptime<deadline {reply=pending.take();if reply==nil {usleep(1000)}}
    guard let reply else {fatalError("Original preparation binding unavailable")}
    let prepared=try reply.get(),now=HostResources.nowMilliseconds()
    do{_=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:prepared,now:now);fatalError("Uncheckpointed preparation became bound")}catch RuntimeError.identity {}
    guard try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:prepared.registration,now:now) else {fatalError("Original preparation identity not stored")}
    if transientBeforeCapture {
        let sibling=UUID().uuidString.lowercased()
        try journal.claim(job:sibling,attempt:0,model:scope.canonicalModel)
        try journal.complete(job:sibling,attempt:0)
        do { _=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:prepared,now:now);fatalError("First capture reused preparation after transient sibling") }
        catch RuntimeError.identity {}
        _=try WorkerPreparationBinding.captureForNonDispatch(plan:plan,journal:journal,registration:prepared.registration)
        guard try journal.unresolvedCount()==1,source.counts.0==1,source.counts.1==1 else {throw JournalError.invalid}
        return
    }
    let binding=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:prepared,now:now)
    try binding.validate(plan:plan,scope:scope,journal:journal,now:now)
    guard binding.rootSequence==UInt64.max,binding.launchNonce==plan.nonce else {fatalError("Original plan/root identity lost")}
    let subject=try NativePreparationSubject(payload:["job_id":job,"attempt":0,"root_sequence":String(UInt64.max),"correlation_id":binding.correlationID])
    let primary=NativePrimaryActivity(phaseVersion:4,instance:scope.nativeEpoch,sampleSequence:13,sampledAt:now,uncertain:false,
        owners:1,ingress:0,preparing:1,queued:0,active:0,responding:0,
        models:[NativePrimaryModelActivity(model:scope.nativeModel,preparing:1,queued:0,active:0,responding:0)])
    let registry=NativeRegistryActivity(primary:primary,registryGeneration:7,transitioning:false,models:[
        NativeRegistryModelFact(model:scope.nativeModel,readyDeclared:false,transitioning:false,uncertain:false,claimable:true,counts:NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0)),
        NativeRegistryModelFact(model:"fixture/idle",readyDeclared:true,transitioning:false,uncertain:false,claimable:true,counts:.zero)])
    let activity=NativePrimaryActivitySample(peer:peer,receivedAt:now,registry:registry)
    guard let lineage=prepared.lineage,
          try binding.observation(lineage:lineage,activity:activity,journal:journal,now:now)==nil,
          let observation=try binding.observation(lineage:lineage,activity:activity,journal:journal,sourceCoverage:.all_clients,now:now) else {fatalError("Original scoped observation lost its separate coverage ceiling")}
    let frame=try observation.encoded(subject:subject,managerEpoch:scope.managerEpoch,journal:journal,now:now)
    let object=try JSONSerialization.jsonObject(with:frame) as! [String:Any]
    guard object["root_sequence"] as? String==String(UInt64.max),object["registry_ready_model"] as? String=="fixture/idle",
          object["native_model"] as? String==scope.nativeModel,
          WireScalar.integer(object["lease_requested_at"])==prepared.registration.sample.requestedAt else {fatalError("Scoped export changed original lease or resident identity")}
    let wrong=try NativePreparationSubject(payload:["job_id":job,"attempt":0,"root_sequence":"1","correlation_id":binding.correlationID])
    do{_=try observation.encoded(subject:wrong,managerEpoch:scope.managerEpoch,journal:journal,now:now);fatalError("Scoped observation crossed original root")}catch RuntimeError.identity {}
    let missing=PreparedNativeReservation(registration:prepared.registration,lineage:nil)
    do{_=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:missing,now:now);fatalError("Missing lineage became launch-plan binding")}catch RuntimeError.identity {}
    // A low-level fixture claim with no native binding exercises a transient
    // local admission change without resolving any native uncertainty.
    let transient=UUID().uuidString.lowercased()
    try journal.claim(job:transient,attempt:0,model:scope.canonicalModel)
    try journal.complete(job:transient,attempt:0)
    guard try journal.unresolvedCount()==1 else {throw JournalError.invalid}
    do{_=try observation.encoded(subject:subject,managerEpoch:scope.managerEpoch,journal:journal,now:now);fatalError("Transient sibling claim revived older preparation observation")}catch RuntimeError.identity {}
    try journal.claim(job:other,attempt:0,model:scope.canonicalModel,scope:scope)
    do{_=try observation.encoded(subject:subject,managerEpoch:scope.managerEpoch,journal:journal,now:now);fatalError("Scoped observation ignored independent unresolved inference")}catch RuntimeError.identity {}
    guard try binding.observation(lineage:lineage,activity:activity,journal:journal,sourceCoverage:.all_clients,now:now)==nil else {fatalError("Fresh metadata laundered independent inference uncertainty")}
    let otherPlan=try journal.planWorkerStart(job:other,attempt:0)
    do{try binding.validate(plan:otherPlan,scope:scope,journal:journal,now:now);fatalError("Preparation crossed original plan")}catch RuntimeError.identity {}
    let expiry=prepared.registration.sample.requestedAt+Int64(prepared.registration.acknowledgement.lifetimeMilliseconds)
    do{try binding.validate(plan:plan,scope:scope,journal:journal,now:expiry);fatalError("Expired preparation binding renewed")}catch RuntimeError.identity {}
    let beforeRetirement=try journal.preparationBindingCheckpoint(plan:plan,peer:peer,root:UInt64.max)
    guard try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:nil,now:now)==nil,
          try journal.preparationBindingCheckpoint(plan:plan,peer:peer,root:UInt64.max) != beforeRetirement,
          try journal.unresolvedCount()==2 else {fatalError("Unknown retirement did not invalidate captured binding or changed inference custody")}
    let beforeRefusal=try journal.preparationBindingCheckpoint(plan:plan,peer:peer,root:UInt64.max)
    do {
        var writer:OpaquePointer?
        guard sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path,&writer,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let writer else {throw JournalError.storage}
        defer {sqlite3_exec(writer,"ROLLBACK",nil,nil,nil);sqlite3_close(writer)}
        guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        do {
            _=try journal.observeRetirement(job:job,attempt:0,scope:scope,peer:peer,sample:nil,now:now)
            fatalError("Contended retirement checkpoint unexpectedly persisted")
        } catch JournalError.storage {}
    }
    let afterRefusal=try journal.preparationBindingCheckpoint(plan:plan,peer:peer,root:UInt64.max)
    guard afterRefusal != beforeRefusal,afterRefusal.lineage==beforeRefusal.lineage,
          try journal.unresolvedCount()==2 else {fatalError("Failed observation write retained old local lease binding or changed durable custody")}
    _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:nil,now:now)
    do{try binding.validate(plan:plan,scope:scope,journal:journal,now:now);fatalError("Unknown lineage poll retained launch binding")}catch RuntimeError.identity {}
    do{_=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:prepared,now:now);fatalError("Invalidated preparation observation recaptured for same plan")}catch RuntimeError.identity {}
    _=try WorkerPreparationBinding.captureForNonDispatch(plan:plan,journal:journal,registration:prepared.registration)
    try journal.markUncertain(job:job,attempt:0)
    do{try binding.validate(plan:plan,scope:scope,journal:journal,now:now+1);fatalError("Uncertain inference retained launch binding")}catch RuntimeError.identity {}
    guard plan.consume(),!plan.consume(),source.counts.0==1,source.counts.1==1 else {fatalError("Binding created a process/consumed plan or retried native RPC")}
}

private func runOwnedPreparationCoherenceTests(peer:NativeControlPeer)throws {
    let instance=String(repeating:"a",count:32),id=String(repeating:"b",count:64),model="fixture/a"
    let source=PreparationReservationSource(peer:peer,mode:.healthy);source.release.signal()
    let pending=PendingNativePreparation(source:source,instance:instance,correlationID:id,model:model,after:10)
    var reply:Result<PreparedNativeReservation,NativeControlError>?
    let end=ProcessInfo.processInfo.systemUptime+2
    while reply==nil && ProcessInfo.processInfo.systemUptime<end {reply=pending.take();if reply==nil {usleep(1000)}}
    guard let reply else {fatalError("Owned preparation fixture unavailable")}
    let prepared=try reply.get(),registration=prepared.registration,now=HostResources.nowMilliseconds()
    guard let lineage=prepared.lineage else {fatalError("Owned preparation original lookup unavailable")}
    let target=NativeRegistryModelFact(model:model,readyDeclared:false,transitioning:false,uncertain:false,claimable:true,
        counts:NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0))
    let idle=NativeRegistryModelFact(model:"fixture/b",readyDeclared:true,transitioning:false,uncertain:false,claimable:true,counts:.zero)
    func activity(rows:[NativeRegistryModelFact]=[target,idle],ingress:Int=0,queued:Int=0,active:Int=0,responding:Int=0,
                  uncertain:Bool=false,transitioning:Bool=false,version:Int=4,samplePeer:NativeControlPeer?=nil,stamp:Int64?=nil,receivedAt:Int64?=nil)->NativePrimaryActivitySample {
        let busy=rows.filter{$0.counts != .zero}.map{NativePrimaryModelActivity(model:$0.model,preparing:$0.counts.preparing,queued:$0.counts.queued,active:$0.counts.active,responding:$0.counts.responding)}
        let primary=NativePrimaryActivity(phaseVersion:version,instance:instance,sampleSequence:13,sampledAt:stamp ?? now,uncertain:uncertain,
            owners:1+ingress+queued+active+responding,ingress:ingress,preparing:1,queued:queued,active:active,responding:responding,models:busy)
        return NativePrimaryActivitySample(peer:samplePeer ?? peer,receivedAt:receivedAt ?? now,registry:NativeRegistryActivity(primary:primary,registryGeneration:7,transitioning:transitioning,models:rows))
    }
    func evaluate(_ sample:NativePrimaryActivitySample,coverage:NativeCoverage = .all_clients,at:Int64?=nil)->NativeOwnedPreparation? {
        NativeOwnedPreparationCoherence.evaluate(registration:registration,lineage:lineage,activity:sample,sourceCoverage:coverage,now:at ?? now)
    }
    let generic=NativeActivityCoherence.evaluate(coverage:.all_clients,sourceCoverage:.all_clients,
        totals:target.counts,unattributed:.zero,
        models:[NativeModelActivity(model:model,resident:false,counts:target.counts),NativeModelActivity(model:"fixture/b",resident:true,counts:.zero)],transitioning:false)
    guard generic.state == .unknown,!generic.permits(target:model) else {fatalError("Scoped preparation weakened generic conflicting-resident refusal")}
    let current=activity()
    guard let result=evaluate(current),result.target.utf8.elementsEqual(model.utf8),result.registryReadyModel=="fixture/b",
          current.registry!.conservativeActivity().state == .unknown else {fatalError("Original preparation changed global idle/residency semantics")}
    guard evaluate(current,coverage:.unknown)==nil,evaluate(current,coverage:.unsupported)==nil else {fatalError("Partial source raised independent coverage ceiling")}
    let unavailable=NativeRegistryModelFact(model:model,readyDeclared:false,transitioning:false,uncertain:false,claimable:false,counts:target.counts)
    let legacy=NativeRegistryModelFact(model:model,readyDeclared:false,transitioning:false,uncertain:false,counts:target.counts)
    for sample in [activity(rows:[unavailable,idle]),activity(rows:[legacy],version:3),activity(ingress:1),activity(queued:1),activity(active:1),activity(responding:1),
                   activity(uncertain:true),activity(transitioning:true),activity(stamp:now+1),
                   activity(samplePeer:NativeControlPeer(pid:43,start:peer.start,executable:peer.executable))] {
        guard evaluate(sample)==nil else {fatalError("Unknown/conflicting source became owned preparation consistency")}
    }
    let competing=NativeRegistryModelFact(model:"fixture/c",readyDeclared:false,transitioning:false,uncertain:false,claimable:true,
        counts:NativePhaseCounts(ingress:0,preparing:0,queued:0,active:1,responding:0))
    guard evaluate(activity(rows:[target,idle,competing],active:1))==nil else {fatalError("Competing coherent native work accepted as original preparation only")}
    let wrongRoot=NativeRequestLineageSample(peer:peer,sampledAt:lineage.sampledAt,lineage:NativeRequestLineage(instance:instance,correlationID:id,
        sampleSequence:12,rootSequence:7,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:1,active:0,responding:0))
    guard NativeOwnedPreparationCoherence.evaluate(registration:registration,lineage:wrongRoot,activity:current,sourceCoverage:.all_clients,now:now)==nil else {fatalError("Foreign original root accepted")}
    let reorderedLineage=NativeRequestLineageSample(peer:peer,sampledAt:now+3,lineage:lineage.lineage)
    guard NativeOwnedPreparationCoherence.evaluate(registration:registration,lineage:reorderedLineage,
        activity:activity(stamp:now+2,receivedAt:now+4),sourceCoverage:.all_clients,now:now+4)==nil else {
        fatalError("Higher sequence with pre-lineage registry clock accepted")
    }
    var sourceClock=lineage.lineage
    sourceClock.sourceCapturedAt=now+3
    guard NativeOwnedPreparationCoherence.evaluate(registration:registration,
        lineage:NativeRequestLineageSample(peer:peer,sampledAt:lineage.sampledAt,lineage:sourceClock),
        activity:activity(stamp:now+2,receivedAt:now+4),sourceCoverage:.all_clients,now:now+4)==nil else {
        fatalError("Registry preceded original lineage source capture")
    }
    sourceClock.sourceCapturedAt=now+2
    sourceClock.operations=NativeRequestQueueCounts(queued:0,active:0)
    guard NativeOwnedPreparationCoherence.evaluate(registration:registration,
        lineage:NativeRequestLineageSample(peer:peer,sampledAt:lineage.sampledAt,lineage:sourceClock),
        activity:activity(stamp:now+2,receivedAt:now+4),sourceCoverage:.all_clients,now:now+4) != nil else {
        fatalError("Matching timestamp and empty reported operation counts refused coherent observation")
    }
    for operations in [NativeRequestQueueCounts(queued:1,active:0),NativeRequestQueueCounts(queued:0,active:1)] {
        var busyLineage=lineage.lineage;busyLineage.operations=operations
        guard NativeOwnedPreparationCoherence.evaluate(registration:registration,
            lineage:NativeRequestLineageSample(peer:peer,sampledAt:lineage.sampledAt,lineage:busyLineage),
            activity:current,sourceCoverage:.all_clients,now:now)==nil else {fatalError("Lineage reported pending work but preparation looked pristine")}
    }
    let another=NativeRegistryModelFact(model:"fixture/c",readyDeclared:true,transitioning:false,uncertain:false,claimable:true,counts:.zero)
    guard evaluate(activity(rows:[target,idle,another]))==nil,
          evaluate(current,at:registration.sample.requestedAt+5000)==nil else {fatalError("Multiple ready models/expired lease accepted")}
    guard source.counts.0==1,source.counts.1==1 else {fatalError("Owned preparation consistency repeated native IO")}
}

func runPreparationFactoryNeverSpawnedTests(factory:PythonWorkerFactory)throws {
    for withdraw in [false,true] {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let journal=try Journal(directory:directory),job=UUID().uuidString.lowercased(),created=HostResources.nowMilliseconds()
        let endpoint="http://127.0.0.1:1/v1",epoch=UUID().uuidString.lowercased()
        let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(endpoint),nativeEpoch:String(repeating:"a",count:32),sequence:1,
            sampledAt:created,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
        let dispatch=WorkerDispatchBinding(baseURL:endpoint,guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"b",count:64),managerEpoch:epoch,
            canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
        let scope=try dispatch.inferenceScope()
        _=try journal.reserveJob(DurableJob(id:job,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"c",count:64),requestHash:String(repeating:"d",count:64),created:created))
        try journal.transitionJob(id:job,to:.running,now:created)
        try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
        let plan=try journal.planWorkerStart(job:job,attempt:0);try journal.markDispatched(job:job,attempt:0)
        let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"e",count:64)))
        let source=PreparationReservationSource(peer:peer,mode:.healthy);source.release.signal()
        let request=PendingNativePreparation(source:source,instance:scope.nativeEpoch,correlationID:try scope.nativeRequestCorrelationID(job:job,attempt:0),model:scope.nativeModel,after:10)
        let deadline=ProcessInfo.processInfo.systemUptime+2
        var result:Result<PreparedNativeReservation,NativeControlError>?
        while result==nil && ProcessInfo.processInfo.systemUptime<deadline {result=request.take();if result==nil {usleep(1000)}}
        guard let result else {throw NativeControlError.deadline}
        let prepared=try result.get(),now=HostResources.nowMilliseconds()
        guard try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:prepared.registration,now:now),let lineage=prepared.lineage else {throw RuntimeError.identity}
        let preparation=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:prepared,now:now)
        let primary=NativePrimaryActivity(phaseVersion:4,instance:scope.nativeEpoch,sampleSequence:13,sampledAt:now,uncertain:false,
            owners:1,ingress:0,preparing:1,queued:0,active:0,responding:0,models:[NativePrimaryModelActivity(model:scope.nativeModel,preparing:1,queued:0,active:0,responding:0)])
        let activity=NativePrimaryActivitySample(peer:peer,receivedAt:now,registry:NativeRegistryActivity(primary:primary,registryGeneration:7,transitioning:false,models:[
            NativeRegistryModelFact(model:scope.nativeModel,readyDeclared:false,transitioning:false,uncertain:false,claimable:true,counts:NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0))]))
        guard let observation=try preparation.observation(lineage:lineage,activity:activity,journal:journal,sourceCoverage:.all_clients,now:now) else {throw RuntimeError.identity}
        let evidence:WorkerNeverSpawnedEvidence
        if withdraw {
            try journal.markUncertain(job:job,attempt:0)
            evidence=try factory.withdrawUnstartedPreparation(plan:plan,preparation:preparation)
        }else {
            let pending=try factory.beginPreparationStart(binding:dispatch,plan:plan,preparation:preparation,observation:observation,journal:journal,
                started:Int64(ProcessInfo.processInfo.systemUptime*1000),now:now,initiallyCancelled:true)
            var outcome:Result<StartedPythonWorker,WorkerStartFailure>?
            let end=ProcessInfo.processInfo.systemUptime+2
            while outcome==nil && ProcessInfo.processInfo.systemUptime<end {outcome=pending.take();if outcome==nil {usleep(1000)}}
            guard case .failure(.neverSpawned(let captured))=outcome,pending.take()==nil else {throw RuntimeError.identity}
            evidence=captured
        }
        guard evidence.handoff==nil,evidence.preparation?.rootSequence==UInt64.max,try journal.workerGrants().isEmpty else {fatalError("Preparation became legacy cancellation evidence or created a process")}
        try journal.recordWorkerNeverSpawned(job:job,attempt:0,evidence:evidence)
        guard try journal.activeLaunchCount()==0,try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
              try journal.requestCount(job:job)==1,try journal.inferenceScope(job:job,attempt:0)?.state == .uncertain,
              try journal.originalNativeRoot(job:job,attempt:0,scope:scope,peer:peer)==UInt64.max else {fatalError("Local no-spawn acknowledgement cleared native preparation uncertainty/history")}
        do{_=try factory.withdrawUnstartedPreparation(plan:plan,preparation:preparation);fatalError("Preparation plan consumed twice")}catch RuntimeError.identity {}
    }
    print("PASS: original preparation factory cancellation/unused withdrawal reap local launch only; typed root, native uncertainty and spent history retained")
}

func runPreparationFactoryTransportTests(factory:PythonWorkerFactory,base:String,guardDirectory:URL,epoch:String)throws {
    let cache=guardDirectory.appendingPathComponent("preparation.json"),mode=guardDirectory.appendingPathComponent("preparation-mode")
    try Data("fixture".utf8).write(to:mode)
    defer {try? FileManager.default.removeItem(at:cache);try? FileManager.default.removeItem(at:mode)}
    try Data(String(repeating:"3",count:32).utf8).write(to:guardDirectory.appendingPathComponent("native-epoch"))
    var reapedStates:[(URL,String,Bool)]=[]
    for scenario in [(available:true,closed:false),(available:false,closed:true),(available:false,closed:false)] {
        let available=scenario.available
        let directory=guardDirectory.appendingPathComponent(UUID().uuidString)
        let journal=try Journal(directory:directory),job=UUID().uuidString.lowercased(),created=HostResources.nowMilliseconds()
        let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:String(repeating:"3",count:32),sequence:1,
            sampledAt:created,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
        let dispatch=WorkerDispatchBinding(baseURL:base,guardPath:guardDirectory.appendingPathComponent("observe.sock").path,host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:epoch,
            canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
        let scope=try dispatch.inferenceScope()
        _=try journal.reserveJob(DurableJob(id:job,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"c",count:64),requestHash:String(repeating:"d",count:64),created:created))
        try journal.transitionJob(id:job,to:.running,now:created)
        try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
        let plan=try journal.planWorkerStart(job:job,attempt:0);try journal.markDispatched(job:job,attempt:0)
        let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"e",count:64)))
        let source=PreparationReservationSource(peer:peer,mode:.healthy);source.release.signal()
        let pending=PendingNativePreparation(source:source,instance:scope.nativeEpoch,correlationID:try scope.nativeRequestCorrelationID(job:job,attempt:0),model:scope.nativeModel,after:10)
        var result:Result<PreparedNativeReservation,NativeControlError>?
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while result==nil && ProcessInfo.processInfo.systemUptime<deadline {result=pending.take();if result==nil {usleep(1000)}}
        guard let result else {throw NativeControlError.deadline}
        let prepared=try result.get(),now=HostResources.nowMilliseconds()
        guard try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:prepared.registration,now:now),let lineage=prepared.lineage else {throw RuntimeError.identity}
        let preparation=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:prepared,now:now)
        let primary=NativePrimaryActivity(phaseVersion:4,instance:scope.nativeEpoch,sampleSequence:13,sampledAt:now,uncertain:false,
            owners:1,ingress:0,preparing:1,queued:0,active:0,responding:0,models:[NativePrimaryModelActivity(model:scope.nativeModel,preparing:1,queued:0,active:0,responding:0)])
        let activity=NativePrimaryActivitySample(peer:peer,receivedAt:now,registry:NativeRegistryActivity(primary:primary,registryGeneration:7,transitioning:false,models:[
            NativeRegistryModelFact(model:scope.nativeModel,readyDeclared:false,transitioning:false,uncertain:false,claimable:true,counts:NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0)),
            NativeRegistryModelFact(model:"fixture/idle-other",readyDeclared:true,transitioning:false,uncertain:false,claimable:true,counts:.zero)]))
        guard let observation=try preparation.observation(lineage:lineage,activity:activity,journal:journal,sourceCoverage:.all_clients,now:now) else {throw RuntimeError.identity}
        let subject=try NativePreparationSubject(payload:["job_id":job,"attempt":0,"root_sequence":String(UInt64.max),"correlation_id":preparation.correlationID])
        if available {try observation.encoded(subject:subject,managerEpoch:epoch,journal:journal,now:now).write(to:cache,options:.atomic)}else if FileManager.default.fileExists(atPath:cache.path) {try FileManager.default.removeItem(at:cache)}
        let started=Int64(ProcessInfo.processInfo.systemUptime*1000)
        let operation=try factory.beginPreparationStart(binding:dispatch,plan:plan,preparation:preparation,observation:observation,journal:journal,started:started,now:now)
        var transport:Result<StartedPythonWorker,WorkerStartFailure>?
        let spawnedBy=ProcessInfo.processInfo.systemUptime+2
        while transport==nil && ProcessInfo.processInfo.systemUptime<spawnedBy {transport=operation.take();if transport==nil {usleep(1000)}}
        guard let transport else {throw RuntimeError.deadline}
        let worker=try transport.get().bind(journal:journal,key:WorkerLaunchKey(job:job,attempt:0),nonce:plan.nonce,started:started,readyAt:Int64(ProcessInfo.processInfo.systemUptime*1000))
        let packet=try JSONSerialization.data(withJSONObject:["v":1,"type":"run","job_id":job,"attempt":0,"model":scope.nativeModel,"epoch":epoch,
            "endpoint_hash":scope.endpointHash,"expires_at":prepared.registration.sample.requestedAt+4900,"context":[["role":"user","content":"fixture preparation"]]])
        try worker.enqueue(packet,expectedModel:scope.nativeModel,endpointHash:scope.endpointHash,epoch:epoch,now:HostResources.nowMilliseconds())
        var posts:Int?,done:String?,text=""
        let finishBy=ProcessInfo.processInfo.systemUptime+10
        while !worker.reaped && ProcessInfo.processInfo.systemUptime<finishBy {
            for event in try worker.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:true) {
                if case .usage(let count,_)=event {posts=count}
                if case .complete=event {done="complete"}
                if case .failed=event {done="error"}
                if case .text(_,let part)=event {text+=part}
            }
            usleep(5000)
        }
        guard worker.reaped,posts == (available ? 1:0),done == (available ? "complete":"error"),!available || text.contains("MOCK_ONLY"),
              try journal.activeLaunchCount()==0,try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
              try journal.requestCount(job:job)==1,try journal.inferenceScope(job:job,attempt:0)?.state == .uncertain,
              worker.zeroPostEvidence==nil else {fatalError("Preparation transport lost exact scope or promoted local output/reap into native proof")}
        if available {
            guard worker.zeroPostPreparationEvidence==nil else {fatalError("Posted preparation worker emitted no-POST evidence")}
        }else {
            guard let evidence=worker.zeroPostPreparationEvidence else {fatalError("PREPARATION_REAPED_ZERO_POST_EVIDENCE_MISSING")}
            let older=UUID().uuidString.lowercased()
            try journal.claim(job:older,attempt:0,model:scope.canonicalModel,scope:scope)
            try journal.markDispatched(job:older,attempt:0);try journal.markUncertain(job:older,attempt:0)
            let closing=PristineCloseFixture(peer:peer,mode:scenario.closed ? "valid":"missing")
            closing.release.signal()
            let coordinator=NativePreparationNonDispatch(journal:journal,source:closing)
            try coordinator.enqueue(.reaped(evidence))
            let closeBy=ProcessInfo.processInfo.systemUptime+3
            while coordinator.pending && ProcessInfo.processInfo.systemUptime<closeBy {try coordinator.poll(now:HostResources.nowMilliseconds());usleep(1000)}
            let receipt=try journal.preparationClosureReceipt(job:job,attempt:0)
            guard !coordinator.pending,closing.count==1,
                  try journal.inferenceScope(job:job,attempt:0)?.state == (scenario.closed ? .not_sent:.uncertain),
                  try journal.inferenceScope(job:older,attempt:0)?.state == .uncertain,
                  try journal.unresolvedCount()==(scenario.closed ? 1:2),try journal.uncertainCount()==(scenario.closed ? 1:2),
                  receipt?.version==2,receipt?.localProducer=="reaped_zero_post",receipt?.grantSHA256 != nil,
                  receipt?.state==(scenario.closed ? "not_sent":"attempted"),try journal.requestCount(job:job)==1 else {fatalError("PREPARATION_REAPED_ZERO_POST_COMPOUND_CLOSURE_FAILED")}
            reapedStates.append((directory,job,scenario.closed))
        }
    }
    for (directory,job,closed) in reapedStates {
        let restored=try Journal(directory:directory),receipt=try restored.preparationClosureReceipt(job:job,attempt:0)
        guard receipt?.version==2,receipt?.localProducer=="reaped_zero_post",receipt?.grantSHA256 != nil,
              receipt?.state==(closed ? "not_sent":"attempted"),
              try restored.inferenceScope(job:job,attempt:0)?.state == (closed ? .not_sent:.uncertain),
              try restored.uncertainCount()==(closed ? 1:2) else {fatalError("Reaped preparation grant/decision lost across restart")}
    }
    let queries=try String(contentsOf:guardDirectory.appendingPathComponent("preparation-queries"),encoding:.utf8).split(separator:"\n")
    guard queries==["preparation","preparation","preparation"] else {fatalError("Scoped preparation retried or fell back to global activity")}
    print("PASS: actual metadata3 factory/installed private child/scoped Unix guard/exact preparation header;1 mock POST or0 on unknown; reaped zero-POST plus exact pristine close resolves only original scope, unknown close retains uncertainty/history")
}

private final class ManagedPreparationSource:NativePreparationManaging,@unchecked Sendable {
    enum Mode {case healthy,reserveFailure,primaryFailure}
    let peer:NativeControlPeer
    let mode:Mode
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var instance="",correlation="",model=""
    private var sequence:UInt64=0
    private var calls=[0,0,0,0]
    var counts:[Int] {lock.lock();defer{lock.unlock()};return calls}
    init(peer:NativeControlPeer,mode:Mode){self.peer=peer;self.mode=mode}
    func reservePreparation(instance:String,correlationID:String,model:String,lifetimeMilliseconds:UInt32,after sequence:UInt64)throws->NativePreparationSample {
        lock.lock();calls[0]+=1;lock.unlock();entered.signal()
        guard release.wait(timeout:.now()+2) == .success else {throw NativeControlError.deadline}
        if mode == .reserveFailure {throw NativeControlError.unavailable}
        lock.lock();self.instance=instance;correlation=correlationID;self.model=model;self.sequence=sequence+1;let next=self.sequence;lock.unlock()
        let now=HostResources.nowMilliseconds()
        return NativePreparationSample(peer:peer,requestedAt:now,receivedAt:now,acknowledgement:NativePreparationAcknowledgement(operation:.reserve,instance:instance,
            correlationID:correlationID,model:model,rootSequence:UInt64.max,sampleSequence:next,sourceSampledAt:now,lifetimeMilliseconds:lifetimeMilliseconds))
    }
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample {
        lock.lock();calls[1]+=1;sequence+=1;let next=sequence;lock.unlock()
        return NativeRequestLineageSample(peer:peer,sampledAt:HostResources.nowMilliseconds(),lineage:NativeRequestLineage(instance:instance,correlationID:correlationID,
            sampleSequence:next,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:1,active:0,responding:0))
    }
    func primaryActivity(instance:String,after afterSequence:UInt64)throws->NativePrimaryActivitySample {
        lock.lock();calls[2]+=1;sequence=max(sequence,afterSequence)+1;let next=sequence,model=self.model;lock.unlock()
        if mode == .primaryFailure {throw NativeControlError.unavailable}
        let now=HostResources.nowMilliseconds()
        let primary=NativePrimaryActivity(phaseVersion:4,instance:instance,sampleSequence:next,sampledAt:now,uncertain:false,
            owners:1,ingress:0,preparing:1,queued:0,active:0,responding:0,models:[NativePrimaryModelActivity(model:model,preparing:1,queued:0,active:0,responding:0)])
        return NativePrimaryActivitySample(peer:peer,receivedAt:now,registry:NativeRegistryActivity(primary:primary,registryGeneration:7,transitioning:false,models:[
            NativeRegistryModelFact(model:model,readyDeclared:false,transitioning:false,uncertain:false,claimable:true,counts:NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0)),
            NativeRegistryModelFact(model:"fixture/idle-other",readyDeclared:true,transitioning:false,uncertain:false,claimable:true,counts:.zero)]))
    }
    func withdrawPreparation(instance:String,correlationID:String,model:String,rootSequence:UInt64,after afterSequence:UInt64)throws->NativePreparationSample {
        lock.lock();calls[3]+=1;sequence=max(sequence,afterSequence)+1;let next=sequence;lock.unlock()
        let now=HostResources.nowMilliseconds()
        return NativePreparationSample(peer:peer,requestedAt:now,receivedAt:now,acknowledgement:NativePreparationAcknowledgement(operation:.withdraw,instance:instance,
            correlationID:correlationID,model:model,rootSequence:rootSequence,sampleSequence:next,sourceSampledAt:now,lifetimeMilliseconds:0))
    }
}

func runPreparationBrokerTests(factory:PythonWorkerFactory,base:String,guardDirectory:URL,epoch:String)throws {
    let cache=guardDirectory.appendingPathComponent("preparation.json"),mode=guardDirectory.appendingPathComponent("preparation-mode"),awaiting=guardDirectory.appendingPathComponent("preparation-await")
    try Data("fixture".utf8).write(to:mode);try Data("fixture".utf8).write(to:awaiting)
    defer {for path in [cache,mode,awaiting]{try? FileManager.default.removeItem(at:path)}}
    try Data(String(repeating:"4",count:32).utf8).write(to:guardDirectory.appendingPathComponent("native-epoch"))
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"e",count:64)))
    for scenario in ["healthy","reserveFailure","primaryFailure","cancelled","storageFailure"] {
        let testMode:ManagedPreparationSource.Mode = scenario=="reserveFailure" ? .reserveFailure:scenario=="primaryFailure" ? .primaryFailure:.healthy
        try? FileManager.default.removeItem(at:cache)
        let directory=guardDirectory.appendingPathComponent(UUID().uuidString),journal=try Journal(directory:directory)
        let id=UUID().uuidString.lowercased(),owner=String(repeating:"c",count:64),created=HostResources.nowMilliseconds()
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"d",count:64),created:created))
        try journal.transitionJob(id:id,to:.running,now:created)
        let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:String(repeating:"4",count:32),sequence:1,
            sampledAt:created,allClientLifecycleCoverage:true,residentModel:"fixture/idle-other",outstandingOwners:0,loading:false)
        let binding=WorkerDispatchBinding(baseURL:base,guardPath:guardDirectory.appendingPathComponent("observe.sock").path,host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:epoch,
            canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
        let scope=try binding.inferenceScope(),native=ManagedPreparationSource(peer:peer,mode:testMode)
        let broker=ModelBroker(journal:journal,factory:factory,preparationSource:native,preparationCoverage:{.all_clients})
        var admission=AdmissionPolicy()
        let resource=ResourceSample(sampledAt:created,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:created)
        if scenario=="healthy" {
            let blocked=ModelBroker(journal:journal,factory:factory,preparationSource:native,preparationCoverage:{.unknown})
            do {
                try blocked.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,
                    nativeCapacityProven:true,sample:resource,admission:&admission,now:created)
                fatalError("Metadata or generic source raised independent preparation coverage")
            }catch AdmissionError.capacity {}
            guard native.counts==[0,0,0,0],try journal.requestCount(job:id)==0,try journal.activeLaunchCount()==0 else {fatalError("Unknown preparation floor spent budget or called native source")}
        }
        let start=ProcessInfo.processInfo.systemUptime
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture broker preparation")],binding:binding,
            nativeCapacityProven:true,sample:resource,admission:&admission,now:created)
        guard ProcessInfo.processInfo.systemUptime-start<0.1,native.entered.wait(timeout:.now()+1) == .success,
              try journal.workerGrants().isEmpty,try journal.inferenceScope(job:id,attempt:0)?.state == .dispatched else {fatalError("Preparation broker blocked or spawned before reservation")}
        if scenario=="cancelled" {try broker.cancel(job:id,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000))}
        native.release.signal()
        if scenario=="storageFailure" {
            let readyBy=ProcessInfo.processInfo.systemUptime+1
            while native.counts[2]==0 && ProcessInfo.processInfo.systemUptime<readyBy {usleep(1000)}
            guard native.counts[2]==1 else {throw NativeControlError.deadline}
            usleep(5000)
            var writer:OpaquePointer?
            guard sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path,&writer,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let writer else {throw JournalError.storage}
            defer {sqlite3_close(writer)}
            guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
            let heldUntil=ProcessInfo.processInfo.systemUptime+0.05
            while ProcessInfo.processInfo.systemUptime<heldUntil {
                _=try broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in binding})
                usleep(1000)
            }
            guard try journal.workerGrants().isEmpty else {fatalError("Preparation storage failure spawned a child")}
            guard sqlite3_exec(writer,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        }
        let subject=try NativePreparationSubject(payload:["job_id":id,"attempt":0,"root_sequence":String(UInt64.max),"correlation_id":scope.nativeRequestCorrelationID(job:id,attempt:0)])
        var posts:Int?,completed=false,failure:String?
        let finishBy=ProcessInfo.processInfo.systemUptime+10
        while broker.active(job:id) && ProcessInfo.processInfo.systemUptime<finishBy {
            let now=HostResources.nowMilliseconds()
            let unknown=NativeSnapshot(host:binding.host,endpointHash:snapshot.endpointHash,nativeEpoch:snapshot.nativeEpoch,sequence:1,sampledAt:now,
                allClientLifecycleCoverage:false,residentModel:nil,outstandingOwners:0,loading:false)
            let current=WorkerDispatchBinding(baseURL:base,guardPath:binding.guardPath,host:binding.host,profileHash:binding.profileHash,managerEpoch:epoch,
                canonicalModel:binding.canonicalModel,nativeModel:binding.nativeModel,nativeSnapshot:unknown,nativeCompatibilityAccepted:true,apiKey:nil)
            guard try !NativeAdmission.permitsDispatch(current,now:now) else {fatalError("Scoped broker raised generic unknown activity")}
            let events=try broker.poll(now:now,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in current})
            if let sample=broker.preparationObservation(subject,now:now),let data=try? sample.encoded(subject:subject,managerEpoch:epoch,journal:journal,now:now) {try data.write(to:cache,options:.atomic)}
            for event in events[id] ?? [] {
                if case .usage(let count,_)=event {posts=count}
                if case .complete=event {completed=true}
                if case .failed(let code)=event {failure=code}
            }
            usleep(5000)
        }
        guard !broker.active(job:id),try journal.activeLaunchCount()==0,try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
              try journal.requestCount(job:id)==1,try journal.inferenceScope(job:id,attempt:0)?.state == .uncertain else {fatalError("Preparation broker lost local/native separation")}
        if scenario == "healthy" {
            guard completed,posts==1,native.counts==[1,1,1,0] else {
                fatalError("Preparation broker did not launch exact once-only original scope: completed=\(completed), posts=\(posts.map(String.init) ?? "none"), failure=\(failure ?? "none"), reserve/lineage/consume/withdraw=\(native.counts)")
            }
        }else {
            let limit=ProcessInfo.processInfo.systemUptime+1
            while scenario != "reserveFailure" && native.counts[3]==0 && ProcessInfo.processInfo.systemUptime<limit {usleep(1000)}
            guard try journal.workerGrants().isEmpty,posts==nil,!completed,native.counts[0]==1,
                  native.counts[3] == (scenario == "reserveFailure" ? 0:1) else {fatalError("Failed preparation spawned/retried or laundered withdrawal metadata")}
        }
    }
    print("PASS: broker off-loop original preparation/checked scope/actual installed child; generic unknown stays closed; source failures reap local launch and retain native uncertainty")
}

private final class PristineCloseFixture:NativePristinePreparationClosing,@unchecked Sendable {
    let peer:NativeControlPeer
    let mode:String
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),finished=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var calls=0
    var count:Int {lock.lock();defer{lock.unlock()};return calls}
    init(peer:NativeControlPeer,mode:String) {self.peer=peer;self.mode=mode}
    func closePristinePreparation(instance:String,correlationID:String,model:String,rootSequence:UInt64,after sequence:UInt64)throws->NativePristinePreparationSample {
        lock.lock();calls+=1;lock.unlock();entered.signal()
        defer{finished.signal()}
        guard release.wait(timeout:.now()+2) == .success else {throw NativeControlError.deadline}
        if mode=="missing" {throw NativeControlError.unavailable}
        let now=HostResources.nowMilliseconds()
        return NativePristinePreparationSample(peer:peer,requestedAt:mode=="stale" ? now-6000:now,receivedAt:now,
            closure:NativePristinePreparationClosure(instance:mode=="epoch" ? String(repeating:"f",count:32):instance,
                correlationID:correlationID,model:mode=="model" ? "fixture/other":model,
                rootSequence:mode=="root" ? 1:rootSequence,sampleSequence:10000,
                sourceSampledAt:mode=="clock" ? nil:now))
    }
}
func runPreparationNonDispatchTests(factory:PythonWorkerFactory)throws {
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    for mode in ["valid","cleanup","storage","restart","missing","epoch","model","root","clock","stale"] {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let job=UUID().uuidString.lowercased(),older=UUID().uuidString.lowercased(),now=HostResources.nowMilliseconds()
        do {
        let journal=try Journal(directory:directory)
        let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
            managerEpoch:"00000000-0000-4000-8000-000000000002",nativeEpoch:String(repeating:"a",count:32),
            canonicalModel:"fixture/model",nativeModel:"fixture/model",sequence:1,sampledAt:now)
        try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
        let plan=try journal.planWorkerStart(job:job,attempt:0);try journal.markDispatched(job:job,attempt:0)
        let reserving=ManagedPreparationSource(peer:peer,mode:.healthy);reserving.release.signal()
        let pending=PendingNativePreparation(source:reserving,instance:scope.nativeEpoch,correlationID:try scope.nativeRequestCorrelationID(job:job,attempt:0),model:scope.nativeModel,after:10)
        var prepared:Result<PreparedNativeReservation,NativeControlError>?
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while prepared==nil && ProcessInfo.processInfo.systemUptime<deadline {prepared=pending.take();if prepared==nil{usleep(1000)}}
        guard let prepared else {throw RuntimeError.deadline}
        let reservation=try prepared.get(),captured=HostResources.nowMilliseconds()
        guard try journal.observePreparationRegistration(job:job,attempt:0,scope:scope,peer:peer,sample:reservation.registration,now:captured) else {throw JournalError.conflict}
        let binding:WorkerPreparationBinding
        if mode=="cleanup" {
            let expired=reservation.registration.sample.requestedAt+5000
            do{_=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:reservation,now:expired);fatalError("Expired preparation acquired launch binding")}catch RuntimeError.identity{}
            binding=try WorkerPreparationBinding.captureForNonDispatch(plan:plan,journal:journal,registration:reservation.registration)
            do{try binding.validate(plan:plan,scope:scope,journal:journal,now:captured);fatalError("Cleanup preparation binding authorized launch")}catch RuntimeError.identity{}
        }else {binding=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:reservation,now:captured)}
        let evidence=try factory.withdrawUnstartedPreparation(plan:plan,preparation:binding)
        try journal.recordWorkerNeverSpawned(job:job,attempt:0,evidence:evidence)
        try journal.claim(job:older,attempt:0,model:scope.canonicalModel,scope:scope)
        try journal.markDispatched(job:older,attempt:0);try journal.markUncertain(job:older,attempt:0)
        let source=PristineCloseFixture(peer:peer,mode:mode)
        let coordinator=NativePreparationNonDispatch(journal:journal,source:source)
        try coordinator.enqueue(evidence)
        if mode=="restart" {
            guard try journal.beginPristinePreparationClose(evidence:evidence) else {throw JournalError.conflict}
            guard try journal.preparationClosureReceipt(job:job,attempt:0)?.state=="attempted" else {fatalError("Pristine attempt lost on restart")}
            try coordinator.poll(now:HostResources.nowMilliseconds())
            guard !coordinator.pending,source.count==0,try journal.uncertainCount()==2 else {fatalError("Restart retried native close or released uncertainty")}
        }else {
        var blocker:OpaquePointer?
        if mode=="storage" {
            guard sqlite3_open(directory.appendingPathComponent("state.sqlite").path,&blocker)==SQLITE_OK,let blocker,
                  sqlite3_exec(blocker,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
            do {try coordinator.poll(now:HostResources.nowMilliseconds());fatalError("Pristine intent ignored SQLite writer outage")}catch JournalError.storage{}
            guard source.count==0,coordinator.pending,sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {fatalError("RPC preceded durable pristine attempt")}
        }
        try coordinator.poll(now:HostResources.nowMilliseconds())
        guard source.entered.wait(timeout:.now()+2) == .success,
              try journal.preparationClosureReceipt(job:job,attempt:0)?.state=="attempted" else {fatalError("Close started before durable intent")}
        if let blocker {guard sqlite3_exec(blocker,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}}
        source.release.signal()
        guard source.finished.wait(timeout:.now()+2) == .success else {throw RuntimeError.deadline}
        usleep(2000)
        if let blocker {
            do {try coordinator.poll(now:HostResources.nowMilliseconds());fatalError("Pristine result ignored SQLite writer outage")}catch JournalError.storage{}
            guard coordinator.pending,source.count==1,sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil)==SQLITE_OK,
                  sqlite3_close(blocker)==SQLITE_OK else {fatalError("Storage recovery lost/repeated pristine result")}
        }
        let finish=ProcessInfo.processInfo.systemUptime+2
        while coordinator.pending && ProcessInfo.processInfo.systemUptime<finish {try coordinator.poll(now:HostResources.nowMilliseconds());usleep(1000)}
        let accepted=mode=="valid" || mode=="cleanup" || mode=="storage"
        guard !coordinator.pending,source.count==1,
              try journal.inferenceScope(job:job,attempt:0)?.state == (accepted ? .not_sent:.uncertain),
              try journal.inferenceScope(job:older,attempt:0)?.state == .uncertain,
              try journal.unresolvedCount()==(accepted ? 1:2),try journal.uncertainCount()==(accepted ? 1:2),
              try journal.workerGrants().isEmpty,try journal.activeLaunchCount()==0,
              try journal.preparationClosureReceipt(job:job,attempt:0)?.state==(accepted ? "not_sent":"attempted") else {fatalError("PRISTINE_COMPOUND_DECISION_INVALID_\(mode)")}
        }
        } // Release the original journal/coordinator before a new application opens it.
        let accepted=mode=="valid" || mode=="cleanup" || mode=="storage"
        let restored=try Journal(directory:directory)
        guard try restored.preparationClosureReceipt(job:job,attempt:0)?.state==(accepted ? "not_sent":"attempted"),
              try restored.inferenceScope(job:job,attempt:0)?.state == (accepted ? .not_sent:.uncertain),
              try restored.uncertainCount()==(accepted ? 1:2) else {fatalError("Pristine compound decision changed across restart")}
    }
    print("PASS: pristine close durable intent precedes one RPC, writer outages retain exact result, crash refuses replay, scoped no-spawn decisions preserve older uncertainty")
}

private final class PristineManagedPreparationFixture:NativePreparationManaging,NativePristinePreparationClosing,@unchecked Sendable {
    let base:ManagedPreparationSource
    let closing:PristineCloseFixture
    let lineageFinished=DispatchSemaphore(value:0)
    var peer:NativeControlPeer {base.peer}
    init(peer:NativeControlPeer) {base=ManagedPreparationSource(peer:peer,mode:.healthy);closing=PristineCloseFixture(peer:peer,mode:"valid")}
    func reservePreparation(instance:String,correlationID:String,model:String,lifetimeMilliseconds:UInt32,after sequence:UInt64)throws->NativePreparationSample {
        try base.reservePreparation(instance:instance,correlationID:correlationID,model:model,lifetimeMilliseconds:lifetimeMilliseconds,after:sequence)
    }
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample {defer{lineageFinished.signal()};throw NativeControlError.unavailable}
    func primaryActivity(instance:String,after sequence:UInt64)throws->NativePrimaryActivitySample {throw NativeControlError.unavailable}
    func withdrawPreparation(instance:String,correlationID:String,model:String,rootSequence:UInt64,after sequence:UInt64)throws->NativePreparationSample {
        try base.withdrawPreparation(instance:instance,correlationID:correlationID,model:model,rootSequence:rootSequence,after:sequence)
    }
    func closePristinePreparation(instance:String,correlationID:String,model:String,rootSequence:UInt64,after sequence:UInt64)throws->NativePristinePreparationSample {
        try closing.closePristinePreparation(instance:instance,correlationID:correlationID,model:model,rootSequence:rootSequence,after:sequence)
    }
}
func runPristinePreparationBrokerCancellationTest(factory:PythonWorkerFactory)throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds(),base="http://127.0.0.1:1/v1",epoch=String(repeating:"a",count:32)
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:epoch,sequence:1,sampledAt:now,
        allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/observe.sock",host:snapshot.host,profileHash:String(repeating:"f",count:64),
        managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let scope=try binding.inferenceScope(),older=UUID().uuidString.lowercased(),job=UUID().uuidString.lowercased(),owner=String(repeating:"c",count:64)
    try journal.claim(job:older,attempt:0,model:scope.canonicalModel,scope:scope);try journal.markDispatched(job:older,attempt:0);try journal.markUncertain(job:older,attempt:0)
    _=try journal.reserveJob(DurableJob(id:job,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"d",count:64),created:now))
    try journal.transitionJob(id:job,to:.running,now:now)
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    let source=PristineManagedPreparationFixture(peer:peer),broker=ModelBroker(journal:journal,factory:factory,preparationSource:source,preparationCoverage:{.all_clients})
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:now)
    try broker.submit(job:job,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,
        nativeCapacityProven:true,sample:sample,admission:&admission,now:now)
    guard source.base.entered.wait(timeout:.now()+2) == .success else {throw RuntimeError.deadline}
    try broker.cancel(job:job,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000))
    let oldTick=HostResources.nowMilliseconds(),clockBy=ProcessInfo.processInfo.systemUptime+2
    while HostResources.nowMilliseconds()<=oldTick && ProcessInfo.processInfo.systemUptime<clockBy {usleep(1000)}
    guard HostResources.nowMilliseconds()>oldTick else {throw RuntimeError.deadline}
    source.base.release.signal();source.closing.release.signal()
    guard source.lineageFinished.wait(timeout:.now()+2) == .success else {throw RuntimeError.deadline}
    // The callback is newer than this poll's captured tick. Retain the exact
    // reply without treating ordinary publication order as clock regression.
    let oldBy=ProcessInfo.processInfo.systemUptime+2
    while broker.active(job:job) && ProcessInfo.processInfo.systemUptime<oldBy {
        _=try broker.poll(now:oldTick,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in binding})
        usleep(1000)
    }
    guard broker.active(job:job),source.base.counts[3]==0,source.closing.count==0 else {fatalError("PRISTINE_CALLBACK_NEWER_THAN_POLL_BECAME_SOURCE_FENCE")}

    let end=ProcessInfo.processInfo.systemUptime+3
    while (broker.active(job:job) || broker.nativeNonDispatchPending) && ProcessInfo.processInfo.systemUptime<end {
        _=try broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in binding})
        usleep(1000)
    }
    let checks:[String:Bool]=[
        "inactive":!broker.active(job:job),"close_finished":!broker.nativeNonDispatchPending,
        "one_reserve":source.base.counts[0]==1,"no_weak_withdraw":source.base.counts[3]==0,"one_close":source.closing.count==1,
        "own_not_sent":try journal.inferenceScope(job:job,attempt:0)?.state == .not_sent,
        "receipt":try journal.preparationClosureReceipt(job:job,attempt:0)?.state=="not_sent",
        "older_uncertain":try journal.inferenceScope(job:older,attempt:0)?.state == .uncertain,
        "one_uncertain":try journal.uncertainCount()==1,"one_unresolved":try journal.unresolvedCount()==1,
        "no_grant":try journal.workerGrants().isEmpty,"no_launch":try journal.activeLaunchCount()==0,
        "one_request":try journal.requestCount(job:job)==1,"enclosing_job_running":try journal.jobs().first(where:{$0.id==job})?.state == .running]
    guard checks.values.allSatisfy({$0}) else {
        FileHandle.standardError.write(Data(("PRISTINE_BROKER_FAILED_CHECKS "+checks.filter{!$0.value}.keys.sorted().joined(separator:",")+"\n").utf8))
        fatalError("PRISTINE_BROKER_ORIGINAL_CANCELLATION_NOT_CLOSED")
    }
    print("PASS: broker cancellation with missing live lineage combines original cleanup-only preparation/no-spawn/one pristine close; older uncertainty and enclosing job retained")
}
