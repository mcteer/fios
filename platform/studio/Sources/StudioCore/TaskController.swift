import Foundation

// Model-only lifecycle and verified sandbox model-channel coordination.
// Runtime/stream execution is supplied by the trusted host controller, never
// container frames. No generic host tool or generated-text dispatcher.
final class TaskController {
    private let journal:Journal
    private let broker:ModelBroker
    private struct SandboxScope { let owner:String;let binding:WorkerDispatchBinding;var channel:SandboxModelChannel }
    private var sandboxScopes:[String:SandboxScope]=[:]
    init(journal:Journal,broker:ModelBroker) { self.journal=journal;self.broker=broker }

    var failedLaunches:Set<WorkerLaunchKey> {broker.failedLaunches}

    func createModelJob(owner:String,idempotency:String,context:[ModelText],binding:WorkerDispatchBinding,
                        nativeCapacityProven:Bool,lifetime:Int64=900_000,sample:ResourceSample,
                        admission:inout AdmissionPolicy,now:Int64) throws -> DurableJob {
        try broker.validate(context:context)
        let request=try JSONSerialization.data(withJSONObject:["kind":"model_only","host":binding.host,
            "profile":binding.profileHash,"model":binding.canonicalModel,"native_model":binding.nativeModel,
            "endpoint_hash":binding.nativeSnapshot.endpointHash,"lifetime":lifetime,
            "context":context.map {["role":$0.role,"content":$0.content]}],options:[.sortedKeys])
        let hash=PythonWorkerFactory.digest(String(decoding:request,as:UTF8.self))
        let proposed=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:idempotency,ownerHash:owner,requestHash:hash,created:now,lifetime:lifetime)
        if let old=try journal.jobs().first(where:{$0.idempotency==idempotency}) {
            guard old.ownerHash==owner,old.requestHash==hash else { throw JournalError.conflict }
            return old // No replay, including reserved/reconciling/terminal jobs.
        }
        guard nativeCapacityProven,binding.nativeCompatibilityAccepted,
              try ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now) else { throw AdmissionError.capacity }
        let owned=try journal.reserveJob(proposed)
        do {
            try journal.transitionJob(id:owned.id,to:.running,now:now)
            try broker.submit(job:owned.id,owner:owner,requestID:UUID().uuidString.lowercased(),context:context,binding:binding,
                nativeCapacityProven:nativeCapacityProven,sample:sample,admission:&admission,now:now)
        } catch {
            try journal.transitionJob(id:owned.id,to:.revoking,now:now)
            try finishIfLocallyGone(id:owned.id,now:now)
            throw error
        }
        guard let saved=try journal.jobs().first(where:{$0.id==owned.id}) else { throw JournalError.storage }
        return saved
    }
    func reserveModelUpload(owner:String,idempotency:String,requestHash:String,binding:WorkerDispatchBinding,
                            nativeCapacityProven:Bool,lifetime:Int64=900000,sample:ResourceSample,
                            admission:inout AdmissionPolicy,now:Int64) throws -> DurableJob {
        if let old=try journal.jobs().first(where:{$0.idempotency==idempotency}) {
            guard old.ownerHash==owner,old.requestHash==requestHash else {throw JournalError.conflict};return old
        }
        try ModelBroker.restoreReservations(journal:journal,admission:&admission)
        guard nativeCapacityProven,binding.nativeCompatibilityAccepted,admission.resourcesSafe(sample,now:now,needsVM:false),
              try ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now) else {throw AdmissionError.capacity}
        return try journal.reserveJob(DurableJob(id:UUID().uuidString.lowercased(),idempotency:idempotency,ownerHash:owner,requestHash:requestHash,created:now,lifetime:lifetime))
    }
    func startModelUpload(id:String,owner:String,requestHash:String,requestID:String,context:[ModelText],binding:WorkerDispatchBinding,
                          nativeCapacityProven:Bool,sample:ResourceSample,admission:inout AdmissionPolicy,now:Int64) throws -> DurableJob {
        guard let saved=try journal.jobs().first(where:{$0.id==id}),saved.ownerHash==owner,saved.requestHash==requestHash,
              try !journal.sandboxRecords().contains(where:{$0.configuration.job==id}) else {throw ControlError.unauthorized}
        guard saved.state == .reserved else {return saved} // Never replay a consumed/terminal upload.
        try broker.validate(context:context)
        var lease=saved.lease
        guard lease.valid(now:now),nativeCapacityProven,binding.nativeCompatibilityAccepted,
              try ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now) else {throw AdmissionError.expired}
        do {
            try journal.transitionJob(id:id,to:.running,now:now)
            try broker.submit(job:id,owner:owner,requestID:requestID,context:context,binding:binding,nativeCapacityProven:nativeCapacityProven,sample:sample,admission:&admission,now:now)
        } catch {
            try journal.transitionJob(id:id,to:.revoking,now:now)
            try finishIfLocallyGone(id:id,now:now)
            throw error
        }
        guard let running=try journal.jobs().first(where:{$0.id==id}) else {throw JournalError.storage};return running
    }
    func registerSandbox(id:String,owner:String,runtimeID:String,binding:WorkerDispatchBinding) throws {
        guard sandboxScopes[id]==nil,sandboxScopes.count<2,binding.nativeCompatibilityAccepted,
              let job=try journal.jobs().first(where:{$0.id==id}),job.ownerHash==owner,job.state == .running,
              let record=try journal.sandboxRecords().first(where:{$0.configuration.job==id}),
              record.runtimeID==runtimeID,record.startIssued,!record.removalProven else { throw ControlError.unauthorized }
        sandboxScopes[id]=SandboxScope(owner:owner,binding:binding,channel:try SandboxModelChannel(job:id,runtimeID:runtimeID))
    }
    private func sameScope(_ a:WorkerDispatchBinding,_ b:WorkerDispatchBinding)->Bool {
        a.host==b.host && a.profileHash==b.profileHash && a.managerEpoch==b.managerEpoch
            && WireScalar.exactModel(a.canonicalModel,b.canonicalModel) && WireScalar.exactModel(a.nativeModel,b.nativeModel)
            && a.nativeSnapshot.endpointHash==b.nativeSnapshot.endpointHash
            && a.nativeSnapshot.nativeEpoch==b.nativeSnapshot.nativeEpoch
    }
    func sandboxModelFrame(id:String,runtimeID:String,data:Data,binding:WorkerDispatchBinding,nativeCapacityProven:Bool,
                           sample:ResourceSample,admission:inout AdmissionPolicy,now:Int64,uptime:Int64) throws {
        guard var scope=sandboxScopes[id] else { throw ControlError.unauthorized }
        do {
            guard sameScope(scope.binding,binding) else { throw ControlError.unauthorized }
            switch try scope.channel.accept(data,runtimeID:runtimeID) {
            case .request(let request,let prompt):
                try broker.submit(job:id,owner:scope.owner,requestID:request,context:[ModelText(role:"user",content:prompt)],
                    binding:binding,nativeCapacityProven:nativeCapacityProven,sample:sample,admission:&admission,now:now)
            case .cancel:
                try broker.cancel(job:id,uptime:uptime)
            }
            sandboxScopes[id]=scope
        } catch {
            scope.channel.revoke();sandboxScopes[id]=scope
            if let state=try journal.jobs().first(where:{$0.id==id})?.state,[.reserved,.creating,.running,.reconciling].contains(state) {
                try journal.transitionJob(id:id,to:.revoking,now:now)
            }
            try broker.cancel(job:id,uptime:uptime)
            throw error
        }
    }
    func sandboxModelData(_ events:[String:[ModelWorkerEvent]]) throws -> [String:[Data]] {
        var result:[String:[Data]]=[:]
        for (id,values) in events {
            guard var scope=sandboxScopes[id] else { continue }
            var frames:[Data]=[]
            for value in values { frames+=try scope.channel.forward(value) }
            sandboxScopes[id]=scope;result[id]=frames
        }
        return result
    }
    private func finishIfLocallyGone(id:String,now:Int64) throws {
        guard !broker.active(job:id),try !journal.activeLaunches().contains(where:{$0.job==id}) else { return }
        // Removal is only job/local-worker state. Native uncertainty survives.
        try journal.transitionJob(id:id,to:.removed,now:now)
    }
    func cancel(id:String,owner:String,now:Int64,uptime:Int64) throws {
        guard let job=try journal.jobs().first(where:{$0.id==id}),job.ownerHash==owner else { throw ControlError.unauthorized }
        guard job.state != .removed else { return }
        if ![.revoking,.stopping,.removing].contains(job.state) { try journal.transitionJob(id:id,to:.revoking,now:now) }
        try broker.cancel(job:id,uptime:uptime)
        if try !journal.sandboxRecords().contains(where:{$0.configuration.job==id}) {
            try finishIfLocallyGone(id:id,now:now)
        }
    }
    // Polling and sandbox frames are job-keyed. Resolve the immutable owned
    // scope before consulting a model-keyed current source; never ask a source
    // to interpret an opaque job UUID as a model or choose a substitute.
    func canonicalModel(forJob id:String)->String? {
        sandboxScopes[id]?.binding.canonicalModel ?? broker.canonicalModel(forJob:id)
    }
    func tick(now:Int64,uptime:Int64,admission:inout AdmissionPolicy,
              source:(String)throws->WorkerDispatchBinding?) throws -> [String:[ModelWorkerEvent]] {
        let data=try broker.poll(now:now,uptime:uptime,admission:&admission,source:source)
        let sandboxIDs=Set(try journal.sandboxRecords().map {$0.configuration.job})
        let running=Set(try journal.jobs().filter {$0.state == .running}.map(\.id))
        for id in sandboxScopes.keys where !running.contains(id) {
            sandboxScopes[id]?.channel.revoke()
            if !broker.active(job:id) { sandboxScopes.removeValue(forKey:id) }
        }
        for job in try journal.jobs() where !sandboxIDs.contains(job.id) {
            let terminal=(data[job.id] ?? []).contains { event in
                switch event { case .complete,.failed: return true;default:return false }
            }
            var state=job.state
            if terminal && state == .running {
                try journal.transitionJob(id:job.id,to:.revoking,now:now);state = .revoking
            }
            if [.revoking,.reconciling].contains(state) { try finishIfLocallyGone(id:job.id,now:now) }
        }
        // Typed model text stays data. No management operation is derived
        // from it, and no result is automatically persisted as an artifact.
        return data
    }
}
