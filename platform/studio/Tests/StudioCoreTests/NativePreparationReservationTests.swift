import Foundation
import CSQLite

private final class PreparationReservationSource:NativePreparationReserving,@unchecked Sendable {
    enum Mode:CaseIterable {case healthy,lineageFailure,lineageMismatch,unknownClock,oldClock,futureClock,expired,foreignPeer,foreignModel,equivalentUnicode,futureLocalTime,invalidStamp}
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
        return NativeRequestLineageSample(peer:peer,sampledAt:HostResources.nowMilliseconds(),lineage:NativeRequestLineage(instance:instance,
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
            let missing=mode == .lineageFailure || mode == .lineageMismatch
            guard (value.lineage==nil)==missing else {fatalError("Failed/mismatched lineage became coherent")}
            let current=mode == .healthy || mode == .lineageFailure || mode == .lineageMismatch
            guard registration.leaseWindowIsCurrent(now:registration.verifiedAt)==current,
                  !registration.leaseWindowIsCurrent(now:registration.verifiedAt-1),
                  !registration.leaseWindowIsCurrent(now:registration.sample.requestedAt+Int64(registration.acknowledgement.lifetimeMilliseconds)) else {fatalError("Receipt timing reset/extended an original native lease")}
        }
    }
    try runPreparationIdentityPersistenceTests(peer:peer)
    try runPreparationPlanBindingTests(peer:peer)
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
    }
}

private func runPreparationPlanBindingTests(peer:NativeControlPeer)throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),job=UUID().uuidString.lowercased(),other=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:"00000000-0000-4000-8000-000000000002",nativeEpoch:String(repeating:"a",count:32),
        canonicalModel:"fixture/model",nativeModel:"fixture/model",sequence:1,sampledAt:HostResources.nowMilliseconds())
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
    let binding=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:prepared,now:now)
    try binding.validate(plan:plan,scope:scope,now:now)
    guard binding.rootSequence==UInt64.max,binding.launchNonce==plan.nonce else {fatalError("Original plan/root identity lost")}
    let missing=PreparedNativeReservation(registration:prepared.registration,lineage:nil)
    do{_=try WorkerPreparationBinding.capture(plan:plan,journal:journal,prepared:missing,now:now);fatalError("Missing lineage became launch-plan binding")}catch RuntimeError.identity {}
    try journal.claim(job:other,attempt:0,model:scope.canonicalModel,scope:scope)
    let otherPlan=try journal.planWorkerStart(job:other,attempt:0)
    do{try binding.validate(plan:otherPlan,scope:scope,now:now);fatalError("Preparation crossed original plan")}catch RuntimeError.identity {}
    let expiry=prepared.registration.sample.requestedAt+Int64(prepared.registration.acknowledgement.lifetimeMilliseconds)
    do{try binding.validate(plan:plan,scope:scope,now:expiry);fatalError("Expired preparation binding renewed")}catch RuntimeError.identity {}
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
                  uncertain:Bool=false,transitioning:Bool=false,version:Int=4,samplePeer:NativeControlPeer?=nil,stamp:Int64?=nil)->NativePrimaryActivitySample {
        let busy=rows.filter{$0.counts != .zero}.map{NativePrimaryModelActivity(model:$0.model,preparing:$0.counts.preparing,queued:$0.counts.queued,active:$0.counts.active,responding:$0.counts.responding)}
        let primary=NativePrimaryActivity(phaseVersion:version,instance:instance,sampleSequence:13,sampledAt:stamp ?? now,uncertain:uncertain,
            owners:1+ingress+queued+active+responding,ingress:ingress,preparing:1,queued:queued,active:active,responding:responding,models:busy)
        return NativePrimaryActivitySample(peer:samplePeer ?? peer,receivedAt:now,registry:NativeRegistryActivity(primary:primary,registryGeneration:7,transitioning:transitioning,models:rows))
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
    let another=NativeRegistryModelFact(model:"fixture/c",readyDeclared:true,transitioning:false,uncertain:false,claimable:true,counts:.zero)
    guard evaluate(activity(rows:[target,idle,another]))==nil,
          evaluate(current,at:registration.sample.requestedAt+5000)==nil else {fatalError("Multiple ready models/expired lease accepted")}
    guard source.counts.0==1,source.counts.1==1 else {fatalError("Owned preparation consistency repeated native IO")}
}
