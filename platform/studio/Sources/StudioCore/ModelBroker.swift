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
    private let journal:Journal
    private let factory:PythonWorkerFactory?
    private var entries:[String:Entry]=[:]
    private var launchHolds:Set<String>=[]
    private var scopes:[String:[String]]=[:]
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
    private func identity(_ binding:WorkerDispatchBinding)->[String] {
        [binding.host,binding.profileHash,binding.managerEpoch,binding.nativeSnapshot.nativeEpoch,
         binding.nativeSnapshot.endpointHash,binding.canonicalModel,binding.nativeModel]
    }
    func validate(context:[ModelText]) throws {
        guard let factory else {throw PolicyError.invalidObservation}
        guard !context.isEmpty,context.count<=1024,context.last?.role=="user",
              context.allSatisfy({["user","assistant"].contains($0.role)}),
              context.reduce(factory.metadata.policy_input_units,{$0+$1.content.utf16.count})<=128000 else { throw ControlError.invalid_request }
    }
    func submit(job id:String,owner:String,requestID:String,context:[ModelText],binding:WorkerDispatchBinding,
                nativeCapacityProven:Bool,sample:ResourceSample,admission:inout AdmissionPolicy,now:Int64) throws {
        guard let factory else {throw PolicyError.invalidObservation}
        try validate(context:context)
        let owned=try job(id,owner:owner,now:now)
        guard nativeCapacityProven,binding.nativeCompatibilityAccepted,entries[id]==nil,launchHolds.isEmpty,
              try ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now)
        else { throw AdmissionError.capacity }
        let scope=identity(binding)
        guard scopes[id]==nil || scopes[id]==scope else { throw JournalError.conflict }
        let ownedGrants=Set(entries.map { "\($0.key):\($0.value.attempt)" })
        guard try journal.activeLaunchCount()==entries.count,
              try journal.workerGrants().allSatisfy({ownedGrants.contains("\($0.job):\($0.attempt)")}) else { throw AdmissionError.capacity }
        let ordinal=try journal.requestCount(job:id)
        guard ordinal<4 else { throw JournalError.trackingLimit }
        let key="model:\(id):\(ordinal)"
        // Reservation precedes both durable permission and actual process spawn.
        try admission.reserveWorker(key:key,sample:sample,now:now)
        do { try journal.claim(job:id,attempt:ordinal,model:binding.canonicalModel,requestID:requestID) }
        catch { admission.releaseWorkerAfterReap(key:key);throw error } // No process was spawned.
        scopes[id]=scope
        let packet=try JSONSerialization.data(withJSONObject:["v":1,"type":"run","job_id":id,"attempt":ordinal,
            "model":binding.nativeModel,"epoch":binding.managerEpoch,"endpoint_hash":binding.nativeSnapshot.endpointHash,
            "expires_at":min(now+5000,owned.lease.expires),"context":context.map {["role":$0.role,"content":$0.content]}])
        do {
            let worker=try factory.start(journal:journal,job:id,attempt:ordinal,binding:binding,command:packet,now:now)
            entries[id]=Entry(worker:worker,attempt:ordinal,key:key,binding:binding)
        } catch {
            try journal.markUncertain(job:id,attempt:ordinal)
            // Do not guess away a possibly spawned child or free its512MiB.
            // Full persisted launch-intent/orphan recovery remains integration work.
            launchHolds.insert(key)
            throw error
        }
    }
    func cancel(job:String,uptime:Int64) throws {
        if let entry=entries[job] { try entry.worker.cancel(now:uptime) }
    }
    func poll(now:Int64,uptime:Int64,admission:inout AdmissionPolicy,
              source:(String)throws->WorkerDispatchBinding?) throws -> [String:[ModelWorkerEvent]] {
        var result:[String:[ModelWorkerEvent]]=[:]
        for (id,entry) in entries {
            let lease=(try? job(id,now:now)) != nil
            let current=try? source(id)
            let coherent=current.map { binding in
                let activity=try? ActivityPolicy.evaluate(binding.nativeSnapshot,now:now)
                return binding.nativeCompatibilityAccepted && identity(binding)==identity(entry.binding)
                    && binding.nativeSnapshot.sequence>=entry.binding.nativeSnapshot.sequence
                    && activity != nil && activity != .unknown
            } ?? false
            if lease && !coherent { try journal.transitionJob(id:id,to:.revoking,now:now) }
            // Own load/compute is not mistaken for source loss. Admission
            // checks loading/conflicts; an in-flight call only checks coverage,
            // exact epoch/profile/scope and freshness, plus its owner lease.
            result[id]=try entry.worker.poll(now:uptime,authorized:lease && coherent)
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
    func active(job:String)->Bool { entries[job] != nil }
    var activeWorkers:Int { entries.count }
    var hasUnresolvedLaunch:Bool { !launchHolds.isEmpty }
}
