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
    }
    private struct Starting {
        let operation:PendingPythonWorker
        let attempt:Int
        let key:String
        let nonce:String
        let started:Int64
        let packet:Data
        let binding:WorkerDispatchBinding
        var hasNativeHandoff=false
        var revoked=false
    }
    private struct Preparing {
        let operation:PendingNativeHandoff
        let plan:PlannedWorkerStart
        let key:String
        let started:Int64
        let packet:Data
        let binding:WorkerDispatchBinding
        var completion:Result<PreparedNativeHandoff,NativeControlError>?
        var revoked=false
        var revokeJob=false
    }
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
    init(journal:Journal,factory:PythonWorkerFactory?=nil,handoffSource:(any NativeHandoffPreparing)?=nil) {
        self.journal=journal;self.factory=factory;self.handoffSource=handoffSource
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
    func submit(job id:String,owner:String,requestID:String,context:[ModelText],binding:WorkerDispatchBinding,
                nativeCapacityProven:Bool,sample:ResourceSample,admission:inout AdmissionPolicy,now:Int64) throws {
        guard try ServiceAdmissionPolicy.permits(journal:journal,model:true,sandbox:false) else {throw AdmissionError.capacity}
        guard let factory else {throw PolicyError.invalidObservation}
        try validate(context:context)
        let owned=try job(id,owner:owner,now:now)
        guard nativeCapacityProven,entries[id]==nil,starting[id]==nil,preparing[id]==nil,launchHolds.isEmpty,
              try NativeAdmission.permitsDispatch(binding,now:now)
        else { throw AdmissionError.capacity }
        let scope=Self.scopeIdentity(binding)
        guard scopes[id]==nil || scopes[id]==scope else { throw JournalError.conflict }
        let ownedGrants=Set(entries.map { "\($0.key):\($0.value.attempt)" })
        guard try journal.activeLaunchCount()==entries.count+starting.count+preparing.count,
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
            if let handoffSource {
                _=try NativeControlWire.instanceBytes(plan.scope.nativeEpoch)
                let correlation=try plan.scope.nativeRequestCorrelationID(job:id,attempt:ordinal)
                try journal.markDispatched(job:id,attempt:ordinal)
                let operation=PendingNativeHandoff(source:handoffSource,instance:plan.scope.nativeEpoch,correlationID:correlation)
                preparing[id]=Preparing(operation:operation,plan:plan,key:key,started:started,packet:packet,binding:binding)
                return
            }
            let operation=try factory.beginStart(binding:binding,plan:plan,started:started,now:now)
            starting[id]=Starting(operation:operation,attempt:ordinal,key:key,nonce:plan.nonce,started:started,packet:packet,binding:binding)
        } catch {
            try journal.markUncertain(job:id,attempt:ordinal)
            // Do not guess away a possibly spawned child or free its512MiB.
            // Known bound failures reach the serialized reaper; unbound
            // failures stay held until reviewed historical absence proof.
            launchHolds.insert(WorkerLaunchKey(job:id,attempt:ordinal))
            throw error
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
                // Release its local slot only; registration may have succeeded.
                do {
                    try journal.markUncertain(job:id,attempt:pending.plan.attempt)
                    try journal.recordWorkerNotStarted(job:id,attempt:pending.plan.attempt,nonce:pending.plan.nonce)
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
                    && ((try? pending.hasNativeHandoff ? NativeAdmission.retainsSource(binding,now:now):NativeAdmission.permitsDispatch(binding,now:now)) ?? false)
            } ?? false
            if !pending.revoked && (!lease || !eligible || uptime<pending.started || uptime-pending.started>=10000) {
                pending.revoked=true;pending.operation.cancel()
                if lease {try journal.transitionJob(id:id,to:.revoking,now:now)}
                try journal.markUncertain(job:id,attempt:pending.attempt)
                launchHolds.insert(WorkerLaunchKey(job:id,attempt:pending.attempt))
            }
            starting[id]=pending
            guard let finished=pending.operation.take() else {continue}
            starting.removeValue(forKey:id)
            do {
                switch finished {
                case .success(let transport):
                    let worker=try transport.bind(journal:journal,key:WorkerLaunchKey(job:id,attempt:pending.attempt),nonce:pending.nonce,started:pending.started,readyAt:uptime)
                    if pending.revoked {try worker.cancel(now:uptime);result[id]=[.interrupted]}
                    else {try worker.enqueue(pending.packet,expectedModel:pending.binding.nativeModel,endpointHash:pending.binding.nativeSnapshot.endpointHash,epoch:pending.binding.managerEpoch,now:now)}
                    entries[id]=Entry(worker:worker,attempt:pending.attempt,key:pending.key,binding:pending.binding)
                    launchHolds.remove(WorkerLaunchKey(job:id,attempt:pending.attempt))
                case .failure(.cancelled):
                    try journal.recordWorkerNotStarted(job:id,attempt:pending.attempt,nonce:pending.nonce)
                    admission.releaseWorkerAfterReap(key:pending.key)
                    launchHolds.remove(WorkerLaunchKey(job:id,attempt:pending.attempt))
                    result[id]=[.interrupted]
                case .failure(.neverSpawned(let evidence)):
                    try journal.recordWorkerNeverSpawned(job:id,attempt:pending.attempt,evidence:evidence)
                    if evidence.handoff != nil {try nonDispatch?.enqueue(.neverSpawned(evidence))}
                    admission.releaseWorkerAfterReap(key:pending.key)
                    launchHolds.remove(WorkerLaunchKey(job:id,attempt:pending.attempt))
                    result[id]=[.interrupted]
                case .failure(.unavailable):throw RuntimeError.launch
                }
            }catch {
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
                    && ((try? NativeAdmission.retainsSource(binding,now:now)) ?? false)
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
            }
        }
        let retained=Set(try journal.jobs().filter {$0.state != .removed}.map(\.id)).union(entries.keys)
        scopes=scopes.filter {retained.contains($0.key)}
        // Every parser enforces64000 UTF-16/request; durable ordinals<=4 imply
        // <=256000/job even across crashes. Terminal history is never refunded.
        return result
    }
    func canonicalModel(forJob id:String)->String? {entries[id]?.binding.canonicalModel ?? starting[id]?.binding.canonicalModel ?? preparing[id]?.binding.canonicalModel}
    func active(job:String)->Bool { entries[job] != nil || starting[job] != nil || preparing[job] != nil }
    var activeWorkers:Int { entries.count+starting.count+preparing.count }
    var nativeNonDispatchPending:Bool {nonDispatch?.pending ?? false}
    var hasUnresolvedLaunch:Bool { !launchHolds.isEmpty }
}
