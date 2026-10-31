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
        var revoked=false
    }
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
    init(journal:Journal,factory:PythonWorkerFactory?=nil) {
        self.journal=journal;self.factory=factory
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
        guard binding.modelPlacementAccepted,nativeCapacityProven,binding.nativeCompatibilityAccepted,entries[id]==nil,starting[id]==nil,launchHolds.isEmpty,
              try ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now)
        else { throw AdmissionError.capacity }
        let scope=Self.scopeIdentity(binding)
        guard scopes[id]==nil || scopes[id]==scope else { throw JournalError.conflict }
        let ownedGrants=Set(entries.map { "\($0.key):\($0.value.attempt)" })
        guard try journal.activeLaunchCount()==entries.count+starting.count,
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
            let nonce=try journal.planWorkerLaunch(job:id,attempt:ordinal)
            let started=Int64(ProcessInfo.processInfo.systemUptime*1000)
            let operation=try factory.beginStart(binding:binding,launchID:nonce,started:started,now:now)
            starting[id]=Starting(operation:operation,attempt:ordinal,key:key,nonce:nonce,started:started,packet:packet,binding:binding)
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
        if var pending=starting[job],!pending.revoked {
            pending.revoked=true;pending.operation.cancel();starting[job]=pending
            try journal.markUncertain(job:job,attempt:pending.attempt)
            launchHolds.insert(WorkerLaunchKey(job:job,attempt:pending.attempt))
        }
    }
    func poll(now:Int64,uptime:Int64,admission:inout AdmissionPolicy,
              source:(String)throws->WorkerDispatchBinding?) throws -> [String:[ModelWorkerEvent]] {
        launchHolds=try Self.reconcileFailedLaunches(launchHolds,journal:journal,admission:&admission)
        var result:[String:[ModelWorkerEvent]]=[:]
        for (id,var pending) in starting {
            let lease=(try? job(id,now:now)) != nil
            let current=try? source(id)
            let eligible=current.map { binding in
                Self.scopeIdentity(binding)==Self.scopeIdentity(pending.binding) && binding.modelPlacementAccepted && binding.nativeCompatibilityAccepted
                    && binding.nativeSnapshot.sequence>=pending.binding.nativeSnapshot.sequence
                    && ((try? ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now)) ?? false)
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
                let activity=try? ActivityPolicy.evaluate(binding.nativeSnapshot,now:now)
                return binding.nativeCompatibilityAccepted && Self.scopeIdentity(binding)==Self.scopeIdentity(entry.binding)
                    && binding.nativeSnapshot.sequence>=entry.binding.nativeSnapshot.sequence
                    && activity != nil && activity != .unknown
            } ?? false
            if lease && !coherent { try journal.transitionJob(id:id,to:.revoking,now:now) }
            // Own load/compute is not mistaken for source loss. Admission
            // checks loading/conflicts; an in-flight call only checks coverage,
            // exact epoch/profile/scope and freshness, plus its owner lease.
            result[id,default:[]]+=try entry.worker.poll(now:uptime,authorized:lease && coherent)
            if entry.worker.reaped {
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
    func canonicalModel(forJob id:String)->String? {entries[id]?.binding.canonicalModel ?? starting[id]?.binding.canonicalModel}
    func active(job:String)->Bool { entries[job] != nil || starting[job] != nil }
    var activeWorkers:Int { entries.count+starting.count }
    var hasUnresolvedLaunch:Bool { !launchHolds.isEmpty }
}
