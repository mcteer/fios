import Foundation

struct ModelText:Sendable { let role:String;let content:String }

// Serialized by the manager's coordinator; no listener or task-selected
// endpoint. Integration must supply reviewed job scopes/native capacity proof
// and restore all durable reservations before permitting new dispatch.
final class ModelBroker {
    private struct Entry {
        let worker:PrivateWorker
        let attempt:Int
        let key:String
        let binding:WorkerDispatchBinding
        var preparation:WorkerPreparationBinding?=nil
    }
    private struct Starting {
        let operation:PendingPythonWorker
        let attempt:Int
        let key:String
        let nonce:String
        let started:Int64
        let packet:Data
        let binding:WorkerDispatchBinding
        var preparation:WorkerPreparationBinding?=nil
        var hasNativeHandoff=false
        var revoked=false
        var completion:Result<StartedPythonWorker,WorkerStartFailure>?
        var acknowledgementRecorded=false
    }
    private struct Preparing {
        let operation:PendingNativeHandoff
        let plan:PlannedWorkerStart
        let key:String
        let started:Int64
        let packet:Data
        let binding:WorkerDispatchBinding
        var completion:Result<PreparedNativeHandoff,NativeControlError>?
        var noSpawnEvidence:WorkerNeverSpawnedEvidence?
        var noSpawnRecorded=false
        var revoked=false
        var revokeJob=false
    }
    private struct LeasePreparing {
        let operation:PendingNativePreparation
        let plan:PlannedWorkerStart
        let key:String
        let started:Int64
        let packet:Data
        let binding:WorkerDispatchBinding
        var completion:Result<PreparedNativeReservation,NativeControlError>?
        var identityRecorded=false
        var noSpawn:WorkerNeverSpawnedEvidence?
        var revoked=false
    }
    private var leasePreparing:[String:LeasePreparing]=[:]
    private var preparationObservations:[String:NativePreparationObservation]=[:]
    private var preparationWithdrawals:[String:PendingNativePreparationWithdrawal]=[:]
    private let preparationSource:(any NativePreparationManaging)?
    private let preparationCoverage:()->NativeCoverage
    private var preparing:[String:Preparing]=[:]
    private let handoffSource:(any NativeHandoffPreparing)?
    private let nonDispatch:NativeHandoffNonDispatch?
    private var starting:[String:Starting]=[:]
    private let journal:Journal
    private let factory:PythonWorkerFactory?
    private var entries:[String:Entry]=[:]
    private var launchHolds:Set<WorkerLaunchKey>=[]
    private var scopes:[String:[Data]]=[:]
    private var previous:Int64=0
    static func restoreReservations(journal:Journal,admission:inout AdmissionPolicy) throws {
        for sandbox in try journal.sandboxRecords() where !sandbox.removalProven {
            try admission.restoreSandbox(sandbox.configuration)
        }
        for launch in try journal.activeLaunches() {
            try admission.restoreWorker(key:"model:\(launch.job):\(launch.attempt)")
        }
    }
    init(journal:Journal,factory:PythonWorkerFactory?=nil,handoffSource:(any NativeHandoffPreparing)?=nil,
         preparationSource:(any NativePreparationManaging)?=nil,preparationCoverage:@escaping ()->NativeCoverage={.unknown}) {
        self.journal=journal;self.factory=factory;self.handoffSource=handoffSource
        self.preparationSource=preparationSource;self.preparationCoverage=preparationCoverage
        nonDispatch=handoffSource.map {NativeHandoffNonDispatch(journal:journal,source:$0)}
    }
    private func job(_ id:String,owner:String?=nil,now:Int64) throws -> DurableJob {
        guard var found=try journal.jobs().first(where:{$0.id==id}),
              owner==nil || found.ownerHash==owner,found.state == .running else { throw AdmissionError.expired }
        let valid=now>=previous && found.lease.valid(now:now)
        previous=max(previous,now)
        guard valid else {
            try journal.transitionJob(id:id,to:.revoking,now:now)
            throw AdmissionError.expired
        }
        return found
    }
    // Swift String equality normalizes Unicode; enrolled identities are raw
    // UTF-8 bytes, including both canonical and native model identifiers.
    static func scopeIdentity(_ binding:WorkerDispatchBinding)->[Data] {
        [binding.host,binding.profileHash,binding.managerEpoch,binding.nativeSnapshot.nativeEpoch,
         binding.nativeSnapshot.endpointHash,binding.canonicalModel,binding.nativeModel].map {Data($0.utf8)}
    }
    func validate(context:[ModelText]) throws {
        guard let factory else {throw PolicyError.invalidObservation}
        guard !context.isEmpty,context.count<=1024,context.last?.role=="user",
              context.allSatisfy({["user","assistant"].contains($0.role)}),
              context.reduce(factory.metadata.policy_input_units,{$0+$1.content.utf16.count})<=128000 else { throw ControlError.invalid_request }
    }
    // The caller has already durably reserved this exact plan. This only
    // retains the once-only asynchronous result; it grants no launch authority.
    func retainStart(operation:PendingPythonWorker,plan:PlannedWorkerStart,binding:WorkerDispatchBinding,packet:Data,started:Int64)throws {
        guard !active(job:plan.job),try journal.activeLaunches().contains(where:{$0.job==plan.job && $0.attempt==plan.attempt && $0.nonce==plan.nonce}),
              try plan.scope.encoded()==binding.inferenceScope().encoded() else {throw RuntimeError.identity}
        starting[plan.job]=Starting(operation:operation,attempt:plan.attempt,key:"model:\(plan.job):\(plan.attempt)",nonce:plan.nonce,
            started:started,packet:packet,binding:binding)
    }
    func submit(job id:String,owner:String,requestID:String,context:[ModelText],binding:WorkerDispatchBinding,
                nativeCapacityProven:Bool,sample:ResourceSample,admission:inout AdmissionPolicy,now:Int64) throws {
        guard try ServiceAdmissionPolicy.permits(journal:journal,model:true,sandbox:false) else {throw AdmissionError.capacity}
        guard let factory else {throw PolicyError.invalidObservation}
        try validate(context:context)
        let owned=try job(id,owner:owner,now:now)
        guard preparationSource == nil || (preparationCoverage() == .all_clients && factory.metadata.native_preparation_version==1) else {throw AdmissionError.capacity}
        guard nativeCapacityProven,entries[id]==nil,starting[id]==nil,preparing[id]==nil,leasePreparing[id]==nil,launchHolds.isEmpty,
              try NativeAdmission.permitsDispatch(binding,now:now)
        else { throw AdmissionError.capacity }
        let scope=Self.scopeIdentity(binding)
        guard scopes[id]==nil || scopes[id]==scope else { throw JournalError.conflict }
        let ownedGrants=Set(entries.map { "\($0.key):\($0.value.attempt)" })
        guard try journal.activeLaunchCount()==entries.count+starting.count+preparing.count+leasePreparing.count,
              try journal.workerGrants().allSatisfy({ownedGrants.contains("\($0.job):\($0.attempt)")}) else { throw AdmissionError.capacity }
        let ordinal=try journal.requestCount(job:id)
        guard ordinal<4 else { throw JournalError.trackingLimit }
        let key="model:\(id):\(ordinal)"
        // Reservation precedes both durable permission and actual process spawn.
        try admission.reserveWorker(key:key,sample:sample,now:now)
        do { try journal.claim(job:id,attempt:ordinal,model:binding.canonicalModel,requestID:requestID,scope:binding.inferenceScope()) }
        catch { admission.releaseWorkerAfterReap(key:key);throw error } // No process was spawned.
        scopes[id]=scope
        let packet=try JSONSerialization.data(withJSONObject:["v":1,"type":"run","job_id":id,"attempt":ordinal,
            "model":binding.nativeModel,"epoch":binding.managerEpoch,"endpoint_hash":binding.nativeSnapshot.endpointHash,
            "expires_at":min(now+5000,owned.lease.expires),"context":context.map {["role":$0.role,"content":$0.content]}])
        do {
            let plan=try journal.planWorkerStart(job:id,attempt:ordinal)
            let started=Int64(ProcessInfo.processInfo.systemUptime*1000)
            if let preparationSource {
                let correlation=try plan.scope.nativeRequestCorrelationID(job:id,attempt:ordinal)
                try journal.markDispatched(job:id,attempt:ordinal)
                leasePreparing[id]=LeasePreparing(operation:PendingNativePreparation(source:preparationSource,instance:plan.scope.nativeEpoch,
                    correlationID:correlation,model:plan.scope.nativeModel,after:binding.nativeSnapshot.sequence),
                    plan:plan,key:key,started:started,packet:packet,binding:binding)
                return
            }
            if let handoffSource {
                _=try NativeControlWire.instanceBytes(plan.scope.nativeEpoch)
                let correlation=try plan.scope.nativeRequestCorrelationID(job:id,attempt:ordinal)
                try journal.markDispatched(job:id,attempt:ordinal)
                let operation=PendingNativeHandoff(source:handoffSource,instance:plan.scope.nativeEpoch,correlationID:correlation)
                preparing[id]=Preparing(operation:operation,plan:plan,key:key,started:started,packet:packet,binding:binding)
                return
            }
            let operation=try factory.beginStart(binding:binding,plan:plan,started:started,now:now)
            try retainStart(operation:operation,plan:plan,binding:binding,packet:packet,started:started)
        } catch {
            try journal.markUncertain(job:id,attempt:ordinal)
            // Do not guess away a possibly spawned child or free its512MiB.
            // Known bound failures reach the serialized reaper; unbound
            // failures stay held until reviewed historical absence proof.
            launchHolds.insert(WorkerLaunchKey(job:id,attempt:ordinal))
            throw error
        }
    }
    // Source identity/freshness retention only, never new admission or a
    // relabeling of generic unknown activity during original preparation.
    private static func retainsPreparationSource(_ current:WorkerDispatchBinding,original:WorkerDispatchBinding,now:Int64)->Bool {
        let snapshot=current.nativeSnapshot
        return NativeAdmission.bindingIsCoherent(current) && scopeIdentity(current)==scopeIdentity(original)
            && snapshot.sequence>=original.nativeSnapshot.sequence && snapshot.sequence<=UInt64(ActivityPolicy.maximumTimestamp)
            && (0...ActivityPolicy.maximumTimestamp).contains(now) && (0...ActivityPolicy.maximumTimestamp).contains(snapshot.sampledAt)
            && (-1000...5000).contains(now-snapshot.sampledAt)
    }
    func preparationObservation(_ subject:NativePreparationSubject,now:Int64)->NativePreparationObservation? {
        guard preparationCoverage() == .all_clients,active(job:subject.job) else {return nil}
        return preparationObservations[subject.job] // The manager rechecks subject/journal/lease before encoding.
    }
    private func enqueuePreparationWithdrawal(_ binding:WorkerPreparationBinding,scope:InferenceScope,job:String,attempt:Int) {
        guard preparationSource != nil else {return}
        enqueuePreparationWithdrawal(instance:scope.nativeEpoch,correlation:binding.correlationID,model:scope.nativeModel,
            root:binding.rootSequence,after:binding.registrationSequence,key:"\(job):\(attempt)")
    }
    private func enqueuePreparationWithdrawal(instance:String,correlation:String,model:String,root:UInt64,after sequence:UInt64,key:String) {
        guard let preparationSource,preparationWithdrawals[key]==nil else {return}
        preparationWithdrawals[key]=PendingNativePreparationWithdrawal(source:preparationSource,instance:instance,correlationID:correlation,model:model,root:root,after:sequence)
    }
    private func pollPreparationLeases(now:Int64,uptime:Int64,admission:inout AdmissionPolicy,
                                       source:(String)throws->WorkerDispatchBinding?,result:inout [String:[ModelWorkerEvent]])throws {
        for (id,var pending) in leasePreparing {
            if pending.completion==nil {pending.completion=pending.operation.take()}
            let lease=(try? job(id,now:now)) != nil
            let current=try? source(id)
            let coherent=current.map{preparationCoverage() == .all_clients && Self.retainsPreparationSource($0,original:pending.binding,now:now)} ?? false
            if !pending.revoked && (!lease || !coherent || uptime<pending.started || uptime-pending.started>=10000) {pending.revoked=true}
            leasePreparing[id]=pending
            guard let completion=pending.completion else {continue}
            var registered:VerifiedNativePreparationRegistration?
            do {
                let value=try completion.get();registered=value.registration
                if !pending.identityRecorded {
                    guard try journal.observePreparationRegistration(job:id,attempt:pending.plan.attempt,scope:pending.plan.scope,
                        peer:value.registration.peer,sample:value.registration,now:now) else {throw NativeControlError.unavailable}
                    pending.identityRecorded=true;leasePreparing[id]=pending
                }
                if !pending.revoked,let lineage=value.lineage,let activity=value.activity,let factory {
                    let binding=try WorkerPreparationBinding.capture(plan:pending.plan,journal:journal,prepared:value,now:now)
                    guard let observation=try binding.observation(lineage:lineage,activity:activity,journal:journal,sourceCoverage:preparationCoverage(),now:now) else {throw NativeControlError.unavailable}
                    let operation=try factory.beginPreparationStart(binding:pending.binding,plan:pending.plan,preparation:binding,observation:observation,journal:journal,
                        started:pending.started,now:now)
                    starting[id]=Starting(operation:operation,attempt:pending.plan.attempt,key:pending.key,nonce:pending.plan.nonce,started:pending.started,
                        packet:pending.packet,binding:pending.binding,preparation:binding)
                    preparationObservations[id]=observation;leasePreparing.removeValue(forKey:id);continue
                }
                pending.revoked=true
            }catch JournalError.storage {
                pending.revoked=true;leasePreparing[id]=pending;continue // Retain once-only completion; never a delayed launch.
            }catch {pending.revoked=true}
            leasePreparing[id]=pending
            do {
                if lease {try journal.transitionJob(id:id,to:.revoking,now:now)}
                try journal.markUncertain(job:id,attempt:pending.plan.attempt)
                // Known registration facts must commit before dropping them.
                if registered != nil && !pending.identityRecorded {continue}
                if pending.noSpawn==nil,let factory {pending.noSpawn=try factory.withdrawUnstartedNativeAttempt(plan:pending.plan,journal:journal);leasePreparing[id]=pending}
                guard let evidence=pending.noSpawn else {continue}
                try journal.recordWorkerNeverSpawned(job:id,attempt:pending.plan.attempt,evidence:evidence)
                if let registered {
                    let ack=registered.acknowledgement
                    enqueuePreparationWithdrawal(instance:ack.instance,correlation:ack.correlationID,model:ack.model,root:ack.rootSequence,after:ack.sampleSequence,key:"\(id):\(pending.plan.attempt)")
                }
                admission.releaseWorkerAfterReap(key:pending.key)
                leasePreparing.removeValue(forKey:id);preparationObservations.removeValue(forKey:id)
                result[id]=[.interrupted]
            }catch JournalError.storage {leasePreparing[id]=pending}
        }
    }
    var failedLaunches:Set<WorkerLaunchKey> {launchHolds}
    static func reconcileFailedLaunches(_ held:Set<WorkerLaunchKey>,journal:Journal,admission:inout AdmissionPolicy)throws->Set<WorkerLaunchKey> {
        var retained=held
        for key in held where try journal.workerLaunchReaped(job:key.job,attempt:key.attempt) {
            admission.releaseWorkerAfterReap(key:key.reservationKey)
            retained.remove(key)
        }
        return retained
    }
    func cancel(job:String,uptime:Int64) throws {
        if let entry=entries[job] { try entry.worker.cancel(now:uptime) }
        if var pending=leasePreparing[job],!pending.revoked {
            pending.revoked=true;leasePreparing[job]=pending
            try journal.markUncertain(job:job,attempt:pending.plan.attempt)
        }
        if var pending=preparing[job],!pending.revoked {
            pending.revoked=true;preparing[job]=pending
            try journal.markUncertain(job:job,attempt:pending.plan.attempt)
        }
        if var pending=starting[job],!pending.revoked {
            pending.revoked=true;pending.operation.cancel();starting[job]=pending
            try journal.markUncertain(job:job,attempt:pending.attempt)
            launchHolds.insert(WorkerLaunchKey(job:job,attempt:pending.attempt))
        }
    }
    func poll(now:Int64,uptime:Int64,admission:inout AdmissionPolicy,
              source:(String)throws->WorkerDispatchBinding?) throws -> [String:[ModelWorkerEvent]] {
        try nonDispatch?.poll(now:now)
        launchHolds=try Self.reconcileFailedLaunches(launchHolds,journal:journal,admission:&admission)
        var result:[String:[ModelWorkerEvent]]=[:]
        for (key,operation) in preparationWithdrawals where operation.take() != nil {preparationWithdrawals.removeValue(forKey:key)}
        try pollPreparationLeases(now:now,uptime:uptime,admission:&admission,source:source,result:&result)
        for (id,var pending) in preparing {
            if pending.completion == nil {pending.completion=pending.operation.take()}
            preparing[id]=pending
            let lease=(try? job(id,now:now)) != nil
            let current=try? source(id)
            let coherent=current.map {binding in
                Self.scopeIdentity(binding)==Self.scopeIdentity(pending.binding)
                    && binding.nativeSnapshot.sequence>=pending.binding.nativeSnapshot.sequence
                    && ((try? NativeAdmission.retainsSource(binding,now:now)) ?? false)
            } ?? false
            if !pending.revoked && (!lease || !coherent || uptime<pending.started || uptime-pending.started>=10000) {
                pending.revoked=true;pending.revokeJob=true
            }
            preparing[id]=pending
            if pending.revoked {
                do {
                    if pending.revokeJob && lease {try journal.transitionJob(id:id,to:.revoking,now:now)}
                    try journal.markUncertain(job:id,attempt:pending.plan.attempt)
                }catch JournalError.storage {continue}
            }
            guard let finished=pending.completion else {continue}
            do {
                let value=try finished.get(),peer=value.registration.peer
                let previousRoot=try journal.originalNativeRoot(job:id,attempt:pending.plan.attempt,scope:pending.plan.scope,peer:peer)
                guard try journal.observeHandoffRegistration(job:id,attempt:pending.plan.attempt,scope:pending.plan.scope,
                          peer:peer,sample:value.registration,now:now),
                      let lineage=value.lineage,
                      value.registration.sampledAt<=lineage.sampledAt,
                      value.registration.sampledAt>=0,now>=value.registration.sampledAt,
                      now-value.registration.sampledAt<=5000 else {throw NativeControlError.unavailable}
                if let original=previousRoot {
                    // A readonly poll can checkpoint a newer sample before this
                    // asynchronous reply is drained. Preserve that checkpoint.
                    guard original==value.registration.result.rootSequence else {throw NativeControlError.invalid}
                }else {
                    guard case .live=try journal.observeLineage(job:id,attempt:pending.plan.attempt,scope:pending.plan.scope,peer:peer,sample:lineage,now:now) else {throw NativeControlError.unavailable}
                }
                // Cancellation still records known original identity, but can
                // never turn that metadata into a process or permission bytes.
                guard !pending.revoked,let factory else {throw NativeControlError.unavailable}
                let handoff=try WorkerHandoffBinding.capture(plan:pending.plan,journal:journal,peer:peer)
                let operation=try factory.beginStart(binding:pending.binding,plan:pending.plan,started:pending.started,now:now,handoff:handoff)
                starting[id]=Starting(operation:operation,attempt:pending.plan.attempt,key:pending.key,nonce:pending.plan.nonce,started:pending.started,packet:pending.packet,binding:pending.binding,hasNativeHandoff:true)
                preparing.removeValue(forKey:id)
            }catch JournalError.storage {
                // Retain the once-only reply and local reservation until its
                // original metadata can commit. Never retry RPC/spawn or turn
                // recovered storage into a delayed worker permission.
                pending.revoked=true;pending.revokeJob=true;preparing[id]=pending
            }catch {
                // This preparation path has never called the worker factory.
                // An unused plan can produce factory evidence, but it cannot
                // resolve native ownership without exact native cancellation.
                do {
                    try journal.markUncertain(job:id,attempt:pending.plan.attempt)
                    if pending.noSpawnEvidence == nil,let factory,
                       case .success(let registered)=finished {
                        var cleanup:WorkerHandoffBinding?
                        do {cleanup=try WorkerHandoffBinding.captureForNonDispatch(plan:pending.plan,journal:journal,peer:registered.registration.peer)}
                        catch RuntimeError.identity {cleanup=nil}
                        if let cleanup {
                            pending.noSpawnEvidence=try factory.withdrawUnstarted(plan:pending.plan,handoff:cleanup)
                            preparing[id]=pending
                        }
                    }
                    if let evidence=pending.noSpawnEvidence {
                        if !pending.noSpawnRecorded {
                            try journal.recordWorkerNeverSpawned(job:id,attempt:pending.plan.attempt,evidence:evidence)
                            pending.noSpawnRecorded=true;preparing[id]=pending
                        }
                        try nonDispatch?.enqueue(.neverSpawned(evidence))
                    }else {
                        // No authenticated original root: retain native doubt.
                        try journal.recordWorkerNotStarted(job:id,attempt:pending.plan.attempt,nonce:pending.plan.nonce)
                    }
                }catch JournalError.storage {
                    pending.revoked=true;pending.revokeJob=true;preparing[id]=pending;continue
                }
                preparing.removeValue(forKey:id)
                admission.releaseWorkerAfterReap(key:pending.key)
                result[id]=pending.revoked ? [.interrupted]:[.failed(code:"model_unavailable")]
            }
        }
        for (id,var pending) in starting {
            let lease=(try? job(id,now:now)) != nil
            let current=try? source(id)
            let eligible=current.map { binding in
                Self.scopeIdentity(binding)==Self.scopeIdentity(pending.binding)
                    && binding.nativeSnapshot.sequence>=pending.binding.nativeSnapshot.sequence
                    && (pending.preparation != nil ? (preparationCoverage() == .all_clients && Self.retainsPreparationSource(binding,original:pending.binding,now:now)):
                        ((try? pending.hasNativeHandoff ? NativeAdmission.retainsSource(binding,now:now):NativeAdmission.permitsDispatch(binding,now:now)) ?? false))
            } ?? false
            if !pending.revoked && (!lease || !eligible || uptime<pending.started || uptime-pending.started>=10000) {
                pending.revoked=true;pending.operation.cancel()
                if lease {try journal.transitionJob(id:id,to:.revoking,now:now)}
                try journal.markUncertain(job:id,attempt:pending.attempt)
                launchHolds.insert(WorkerLaunchKey(job:id,attempt:pending.attempt))
            }
            starting[id]=pending
            if pending.completion == nil {pending.completion=pending.operation.take()}
            starting[id]=pending
            guard let finished=pending.completion else {continue}
            // A no-process acknowledgement is repeatable journal I/O, but its
            // opaque once-only producer result must survive a storage failure.
            // A started transport cannot be rebound after ownership transfer.
            let retainOnStorageFailure:Bool
            switch finished {
            case .failure(.neverSpawned),.failure(.cancelled):retainOnStorageFailure=true
            default:retainOnStorageFailure=false
            }
            if !retainOnStorageFailure {starting.removeValue(forKey:id)}
            do {
                switch finished {
                case .success(let transport):
                    let worker=try transport.bind(journal:journal,key:WorkerLaunchKey(job:id,attempt:pending.attempt),nonce:pending.nonce,started:pending.started,readyAt:uptime)
                    if pending.revoked {try worker.cancel(now:uptime);result[id]=[.interrupted]}
                    else {try worker.enqueue(pending.packet,expectedModel:pending.binding.nativeModel,endpointHash:pending.binding.nativeSnapshot.endpointHash,epoch:pending.binding.managerEpoch,now:now)}
                    entries[id]=Entry(worker:worker,attempt:pending.attempt,key:pending.key,binding:pending.binding,preparation:pending.preparation)
                    launchHolds.remove(WorkerLaunchKey(job:id,attempt:pending.attempt))
                case .failure(.cancelled):
                    if !pending.acknowledgementRecorded {
                        try journal.recordWorkerNotStarted(job:id,attempt:pending.attempt,nonce:pending.nonce)
                        pending.acknowledgementRecorded=true;starting[id]=pending
                    }
                    admission.releaseWorkerAfterReap(key:pending.key)
                    launchHolds.remove(WorkerLaunchKey(job:id,attempt:pending.attempt))
                    result[id]=[.interrupted]
                case .failure(.neverSpawned(let evidence)):
                    if !pending.acknowledgementRecorded {
                        try journal.recordWorkerNeverSpawned(job:id,attempt:pending.attempt,evidence:evidence)
                        pending.acknowledgementRecorded=true;starting[id]=pending
                    }
                    if evidence.handoff != nil {try nonDispatch?.enqueue(.neverSpawned(evidence))}
                    if let preparation=evidence.preparation {enqueuePreparationWithdrawal(preparation,scope:try pending.binding.inferenceScope(),job:id,attempt:pending.attempt)}
                    preparationObservations.removeValue(forKey:id)
                    admission.releaseWorkerAfterReap(key:pending.key)
                    launchHolds.remove(WorkerLaunchKey(job:id,attempt:pending.attempt))
                    result[id]=[.interrupted]
                case .failure(.unavailable):throw RuntimeError.launch
                }
                starting.removeValue(forKey:id)
            }catch JournalError.storage where retainOnStorageFailure {
                pending.revoked=true
                starting[id]=pending
                launchHolds.insert(WorkerLaunchKey(job:id,attempt:pending.attempt))
                continue
            }catch {
                starting.removeValue(forKey:id)
                try journal.markUncertain(job:id,attempt:pending.attempt)
                launchHolds.insert(WorkerLaunchKey(job:id,attempt:pending.attempt))
                result[id]=pending.revoked ? [.interrupted]:[.failed(code:"internal_error")]
            }
        }
        for (id,entry) in entries {
            let lease=(try? job(id,now:now)) != nil
            let current=try? source(id)
            let coherent=current.map { binding in
                return Self.scopeIdentity(binding)==Self.scopeIdentity(entry.binding)
                    && binding.nativeSnapshot.sequence>=entry.binding.nativeSnapshot.sequence
                    && (entry.preparation != nil ? (preparationCoverage() == .all_clients && Self.retainsPreparationSource(binding,original:entry.binding,now:now)):
                        ((try? NativeAdmission.retainsSource(binding,now:now)) ?? false))
            } ?? false
            if lease && !coherent { try journal.transitionJob(id:id,to:.revoking,now:now) }
            // Own load/compute is not mistaken for source loss. Admission
            // checks loading/conflicts; an in-flight call only checks coverage,
            // exact epoch/profile/scope and freshness, plus its owner lease.
            result[id,default:[]]+=try entry.worker.poll(now:uptime,authorized:lease && coherent)
            if entry.worker.reaped {
                if let proof=entry.worker.zeroPostEvidence {try nonDispatch?.enqueue(.reaped(proof))}
                admission.releaseWorkerAfterReap(key:entry.key)
                entries.removeValue(forKey:id)
                preparationObservations.removeValue(forKey:id)
            }
        }
        let retained=Set(try journal.jobs().filter {$0.state != .removed}.map(\.id)).union(entries.keys)
        scopes=scopes.filter {retained.contains($0.key)}
        // Every parser enforces64000 UTF-16/request; durable ordinals<=4 imply
        // <=256000/job even across crashes. Terminal history is never refunded.
        return result
    }
    func canonicalModel(forJob id:String)->String? {entries[id]?.binding.canonicalModel ?? starting[id]?.binding.canonicalModel ?? preparing[id]?.binding.canonicalModel ?? leasePreparing[id]?.binding.canonicalModel}
    func active(job:String)->Bool { entries[job] != nil || starting[job] != nil || preparing[job] != nil || leasePreparing[job] != nil }
    var activeWorkers:Int { entries.count+starting.count+preparing.count+leasePreparing.count }
    var nativeNonDispatchPending:Bool {nonDispatch?.pending ?? false}
    var hasUnresolvedLaunch:Bool { !launchHolds.isEmpty }
}
