import Foundation

// Serialized heartbeat coordinator. Runtime effects execute off-loop; input
// and attach transport must be prepared before any create→start transition.
final class JobController {
    private let journal:Journal
    private let lifecycle:SandboxLifecycle
    private let executor:any SandboxExecuting
    private var inFlight:[String:SandboxCommand]=[:]
    private var deferred:[String:SandboxCommand]=[:]
    private var lastInspect:[String:Int64]=[:]
    private var released=Set<String>()
    private var previous:Int64=0
    private var lastCycle:Int64 = -2000
    private(set) var exitProof:[String:Bool]=[:]
    private var revokingSince:[String:Int64]=[:]
    private var storageContinuityUnknown=Set<String>()
    private let collectVM:Bool
    private var resourcePending:(job:String,id:String,leaseUntil:Int64,submittedAt:Int64,invalidated:Bool)?
    private var lastResource:Int64 = -2000
    private var latestVM:(sample:VMKernelSample,job:String,id:String,leaseUntil:Int64)?
    private var vmProbes=Set<String>()
    init(journal:Journal,executor:any SandboxExecuting,collectVM:Bool=false) {
        self.journal=journal;self.executor=executor;self.collectVM=collectVM;lifecycle=SandboxLifecycle(journal:journal)
    }
    private var cleanupSnapshot:(since:[String:Int64],storageUnknown:Int,at:Int64)?
    // Current owned-runtime cleanup only; this does not describe native
    // inference completion. Wait age starts when this manager observes it.
    func cleanupObservation(now:Int64)->(pending:Int,wait:Int64?,observedAt:Int64?) {
        guard let snapshot=cleanupSnapshot else {return (0,nil,nil)}
        let clockKnown=(0...ActivityPolicy.maximumTimestamp).contains(now) && now>=previous &&
            snapshot.since.values.allSatisfy{$0>=0 && $0<=now}
        let wait=clockKnown ? snapshot.since.values.map{now-$0}.max() ?? 0:nil
        return (snapshot.since.count,wait,snapshot.at)
    }
    func cleanupStatus(now:Int64)->[String:Any] {
        let sample=cleanupObservation(now:now)
        // This timestamps the manager tick, not a runtime listing or proof.
        let observationAge=sample.wait.flatMap { _ in sample.observedAt.map { now-$0 } }
        return ["scope":"owned_runtime_cleanup","pending_sandboxes":sample.pending,
            "manager_observation_age_ms":observationAge.map{$0 as Any} ?? NSNull(),
            "storage_continuity_unknown":cleanupSnapshot?.storageUnknown ?? 0,
            "observed_at":sample.observedAt.map{$0 as Any} ?? NSNull(),
            "observed_wait_ms":sample.wait.map{$0 as Any} ?? NSNull(),
            "waiting_over_60s":sample.wait.map{($0>=60000) as Any} ?? NSNull()]
    }
    func authorizeVMProbe(id:String,permission:VMProbePermission,now:Int64)throws {
        guard collectVM,vmProbes.isEmpty,
              let job=try journal.jobs().first(where:{$0.id==id}),
              let record=try journal.sandboxRecords().first(where:{$0.configuration.job==id}),!record.createIssued,!record.removalProven else {throw AdmissionError.invalid}
        try permission.authorize(record.configuration,job:job,now:now)
        vmProbes.insert(id)
    }
    func vmAvailable(now:Int64)->UInt64? {
        guard collectVM,now>=previous,let latestVM,now<latestVM.leaseUntil,
              let envelope=latestVM.sample.envelope else {return nil}
        return VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:now)
    }
    func applyingVM(to host:ResourceSample,now:Int64)->ResourceSample {
        guard let available=vmAvailable(now:now),let envelope=latestVM?.sample.envelope,
              envelope.total<=host.physical,envelope.configuredCap<=host.physical else {return host.replacingVM(nil)}
        return host.replacingVM(available,sampledAt:envelope.sampledAt)
    }
    func vmSampledAt(now:Int64)->Int64? {vmAvailable(now:now)==nil ? nil : latestVM?.sample.envelope?.sampledAt}
    func vmEpoch(now:Int64)->String? {vmAvailable(now:now)==nil ? nil : latestVM?.sample.envelope?.runtimeHash}
    private func dispatch(_ command:SandboxCommand,job:String) throws {
        if case .inspect=command,let last=lastInspect[job],previous>=last,previous-last<2000 {return}
        do {
            try executor.submit(job:job,command:command);inFlight[job]=command;deferred.removeValue(forKey:job)
            if case .inspect=command {lastInspect[job]=previous}
        }
        catch AdmissionError.capacity { deferred[job]=command }
    }
    func tick(now:Int64,sample:ResourceSample,admission:inout AdmissionPolicy,
              inputReady:(String)->Bool={_ in true},transportReady:(String)->Bool,cancelModel:(String)throws->Void) throws {
        var candidateVM=latestVM
        latestVM=nil // Publish only after a successful tick and durable target recheck.
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else { throw JournalError.invalid }
        let managedSandboxes=try journal.sandboxRecords()
        let sandboxIDs=Set(managedSandboxes.filter {!$0.removalProven}.map { $0.configuration.job })
        for sandbox in managedSandboxes where !sandbox.removalProven {try admission.restoreSandbox(sandbox.configuration)}
        let rollback=now<previous;previous=max(previous,now)
        if rollback {candidateVM=nil}
        if let pending=resourcePending,!pending.invalidated {
            let ownsRuntime=managedSandboxes.contains {
                $0.configuration.job==pending.job && $0.createIssued && $0.startIssued && !$0.removalProven && $0.runtimeID==pending.id
            }
            let validLease = try !rollback && ownsRuntime && now<pending.leaseUntil && journal.jobs().contains { job in
                var lease=job.lease
                return job.id==pending.job && job.state == .running && lease.expires>=pending.leaseUntil && lease.valid(now:now)
            }
            if !validLease {
                // Keep the slot until the original result drains; a later
                // matching snapshot cannot repair the intervening gap.
                resourcePending?.invalidated=true
            }
        }
        for result in executor.drainResources() {
            guard let pending=resourcePending,pending.job==result.job,pending.id==result.runtimeID else {throw JournalError.conflict}
            resourcePending=nil
            if !pending.invalidated,case .success(let value)=result.result,
               value.sampledAt>=pending.submittedAt,value.validatedEnvelope(physical:sample.physical,now:now) != nil {
                candidateVM=(value,pending.job,pending.id,pending.leaseUntil)
            }
            else {candidateVM=nil}
        }
        let safe = !rollback && admission.resourcesSafe(sample,now:now,needsVM:true)
        let probeSafe = !rollback && admission.resourcesSafe(sample,now:now,needsVM:false)
        // Host pressure applies to every owned job, including model-only
        // workers. Missing VM telemetry applies only to sandbox consumers.
        func safeFor(_ id:String)->Bool {(!sandboxIDs.contains(id) || vmProbes.contains(id)) ? probeSafe : safe}
        var victim:String?
        if !safe && (rollback || now-lastCycle>=2000) {
            let jobs=try journal.jobs()
            let candidates=Set(jobs.filter {!safeFor($0.id) && [.reserved,.creating,.running].contains($0.state)}.map(\.id))
            let newest=try journal.newestJobIDs().first(where:{candidates.contains($0)})
            if let newest {
                victim=newest
                try journal.transitionJob(id:newest,to:.revoking,now:now)
                try cancelModel(newest)
            }
        }
        var completionError:Error?
        for completed in executor.drain() {
            do {try apply(completed)} catch {if completionError==nil {completionError=error}}
        }
        if let completionError {throw completionError}
        func apply(_ completed:SandboxExecution)throws {
            guard let command=inFlight.removeValue(forKey:completed.job) else { throw JournalError.conflict }
            switch completed.result {
            case .failure(.storageContinuityUnknown):
                guard case .inspect=command else {throw JournalError.conflict}
                storageContinuityUnknown.insert(completed.job)
            case .failure:
                // Timeout/error is neither daemon absence nor permission to
                // replay create/start. Next cycle reconciles by exact identity.
                break
            case .success(.created(let id)):
                guard case .create=command else { throw JournalError.conflict }
                try lifecycle.created(job:completed.job,runtimeID:id)
            case .success(.observed(let presence,let exitCode,let oom)):
                guard case .inspect=command else { throw JournalError.conflict }
                let startIssued=try journal.sandboxRecords().first(where:{$0.configuration.job==completed.job})?.startIssued == true
                if case .present(_,_,_,_,false)=presence,
                   let job=try journal.jobs().first(where:{$0.id==completed.job}),job.state == .creating,
                   !startIssued,(!safeFor(job.id) || !transportReady(job.id)) {
                    exitProof.removeValue(forKey:completed.job)
                    return
                }
                // Validate ownership/causality before publishing exit status.
                let next=try lifecycle.observed(job:completed.job,presence:presence,now:now,resourcesSafe:!rollback && (safeFor(completed.job) || completed.job != victim))
                storageContinuityUnknown.remove(completed.job)
                if case .present(_,_,_,_,let running)=presence {
                    if running || !startIssued || exitCode==nil {exitProof.removeValue(forKey:completed.job)}
                    else if let exitCode {exitProof[completed.job]=exitCode==0 && !oom}
                }
                if let next {try dispatch(next,job:completed.job)}
            case .success(.acknowledged):
                switch command {
                case .start,.stop,.remove:break // Receipt only, not a daemon state observation.
                case .create,.inspect:throw JournalError.conflict
                }
            }
        }
        let records=try journal.sandboxRecords()
        let jobIndex=Dictionary(uniqueKeysWithValues:try journal.jobs().map {($0.id,$0)})
        let retained=Set(records.map(\.configuration.job))
        released.formIntersection(retained)
        storageContinuityUnknown.formIntersection(retained)
        exitProof=exitProof.filter {retained.contains($0.key)}
        lastInspect=lastInspect.filter {retained.contains($0.key)}
        if collectVM,!rollback,resourcePending==nil,now>=lastResource+2000 {
            lastResource=now
            if let target=records.first(where:{record in
                guard let job=jobIndex[record.configuration.job] else {return false}
                var lease=job.lease
                return job.state == .running && record.createIssued && record.startIssued && !record.removalProven && record.runtimeID != nil && lease.valid(now:now) && lease.expires-now>=10000 && inFlight[job.id]==nil && deferred[job.id]==nil
            }),let id=target.runtimeID,let job=jobIndex[target.configuration.job] {
                do {
                    try executor.submitResources(configuration:target.configuration,id:id,leaseUntil:job.lease.expires)
                    resourcePending=(job.id,id,job.lease.expires,now,false)
                } catch AdmissionError.capacity {} // No operation was enqueued.
                catch {candidateVM=nil}
            }
        }
        var pendingCleanup=Set<String>()
        for record in records {
            let id=record.configuration.job
            guard var job=jobIndex[id] else { throw JournalError.storage }
            if [.reserved,.creating,.running].contains(job.state) && !job.lease.valid(now:now) {
                try lifecycle.cancelled(job:id,now:now)
                try cancelModel(id)
                guard let updated=try journal.jobs().first(where:{$0.id==id}) else { throw JournalError.storage }
                job=updated
            }
            if job.state == .removed {
                revokingSince.removeValue(forKey:id);deferred.removeValue(forKey:id)
                if record.removalProven && !released.contains(id) { admission.releaseProvenAbsent(job:id);released.insert(id);vmProbes.remove(id) }
                continue
            }
            if !record.removalProven && [.revoking,.stopping,.removing,.reconciling].contains(job.state) {
                pendingCleanup.insert(id)
                revokingSince[id]=revokingSince[id] ?? now
            }
            guard inFlight[id]==nil else { continue }
            if let command=deferred[id] {
                switch command {
                case .create,.start:
                    var lease=job.lease
                    guard safeFor(id),[.reserved,.creating,.running].contains(job.state),lease.valid(now:now) else {
                        deferred.removeValue(forKey:id)
                        try lifecycle.cancelled(job:id,now:now)
                        continue
                    }
                    // Capacity refusal means this start was never submitted.
                    // Its durable intent does not preserve transport readiness.
                    if case .create=command,!inputReady(id) {continue}
                    if case .start=command,!transportReady(id) {continue}
                default:break
                }
                try dispatch(command,job:id);continue
            }
            if job.state == .reserved {
                guard safeFor(id),inputReady(id) else {continue}
                if !record.createIssued,let slotExecutor=executor as? any SandboxCreateSlotExecuting {
                    // Reserve capacity before writing intent, then publish
                    // exactly once after the atomic journal transaction.
                    do {
                        try slotExecutor.submitCreate(configuration:record.configuration,beforePublish:{
                            try journal.commitSandboxCreate(record.configuration,now:now)
                        })
                        inFlight[id] = .create(record.configuration)
                    } catch AdmissionError.capacity { /* No intent was written. */ }
                    continue
                }
            }
            if let command=try lifecycle.next(job:id,now:now,resourcesSafe:!rollback && (safeFor(id) || id != victim)) { try dispatch(command,job:id) }
        }
        if let observed=candidateVM {
            if now<observed.leaseUntil,
               try journal.jobs().contains(where:{job in
                   var lease=job.lease
                   return job.id==observed.job && job.state == .running && lease.expires>=observed.leaseUntil && lease.valid(now:now)
               }),
               try journal.sandboxRecords().contains(where:{$0.configuration.job==observed.job && !$0.removalProven && $0.runtimeID==observed.id}) {
                latestVM=observed
            }
        }
        revokingSince=revokingSince.filter{pendingCleanup.contains($0.key)}
        if !rollback {cleanupSnapshot=(revokingSince,storageContinuityUnknown.intersection(revokingSince.keys).count,now)}
        if now>=lastCycle+2000 { lastCycle=now }
    }
}
