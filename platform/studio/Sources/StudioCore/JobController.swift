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
    private let collectVM:Bool
    private var resourcePending:(job:String,id:String)?
    private var lastResource:Int64 = -2000
    private var latestVM:VMKernelSample?
    private var vmProbes=Set<String>()
    init(journal:Journal,executor:any SandboxExecuting,collectVM:Bool=false) {
        self.journal=journal;self.executor=executor;self.collectVM=collectVM;lifecycle=SandboxLifecycle(journal:journal)
    }
    // Current owned-runtime cleanup only; this does not describe native
    // inference completion. Wait age starts when this manager observes it.
    func cleanupObservation(now:Int64)->(pending:Int,wait:Int64?,observedAt:Int64?) {
        let clockKnown=(0...ActivityPolicy.maximumTimestamp).contains(now) && now>=previous &&
            revokingSince.values.allSatisfy{$0>=0 && $0<=now}
        let wait=clockKnown ? revokingSince.values.map{now-$0}.max() ?? 0:nil
        return (revokingSince.count,wait,previous>0 ? previous:nil)
    }
    func cleanupStatus(now:Int64)->[String:Any] {
        let sample=cleanupObservation(now:now)
        return ["scope":"owned_runtime_cleanup","pending_sandboxes":sample.pending,
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
        guard collectVM,let envelope=latestVM?.envelope else {return nil}
        return VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:now)
    }
    func applyingVM(to host:ResourceSample,now:Int64)->ResourceSample {
        guard collectVM,let envelope=latestVM?.envelope,
              let available=VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:now) else {return host.replacingVM(nil)}
        return host.replacingVM(available,sampledAt:envelope.sampledAt)
    }
    func vmSampledAt(now:Int64)->Int64? {vmAvailable(now:now)==nil ? nil : latestVM?.envelope?.sampledAt}
    func vmEpoch(now:Int64)->String? {vmAvailable(now:now)==nil ? nil : latestVM?.envelope?.runtimeHash}
    private func dispatch(_ command:SandboxCommand,job:String) throws {
        if case .inspect=command,let last=lastInspect[job],previous>=last,previous-last<2000 {return}
        do {
            try executor.submit(job:job,command:command);inFlight[job]=command;deferred.removeValue(forKey:job)
            if case .inspect=command {lastInspect[job]=previous}
        }
        catch AdmissionError.capacity { deferred[job]=command }
    }
    func tick(now:Int64,sample:ResourceSample,admission:inout AdmissionPolicy,
              transportReady:(String)->Bool,cancelModel:(String)throws->Void) throws {
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else { throw JournalError.invalid }
        let managedSandboxes=try journal.sandboxRecords()
        let sandboxIDs=Set(managedSandboxes.filter {!$0.removalProven}.map { $0.configuration.job })
        for sandbox in managedSandboxes where !sandbox.removalProven {try admission.restoreSandbox(sandbox.configuration)}
        let rollback=now<previous;previous=max(previous,now)
        if rollback {latestVM=nil}
        for result in executor.drainResources() {
            guard let pending=resourcePending,pending.job==result.job,pending.id==result.runtimeID else {throw JournalError.conflict}
            resourcePending=nil
            if !rollback,case .success(let value)=result.result,let envelope=value.envelope,
               VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:now) != nil {latestVM=value}
            else {latestVM=nil}
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
        for completed in executor.drain() {
            guard let command=inFlight.removeValue(forKey:completed.job) else { throw JournalError.conflict }
            switch completed.result {
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
                    continue
                }
                // Validate ownership/causality before publishing exit status.
                let next=try lifecycle.observed(job:completed.job,presence:presence,now:now,resourcesSafe:!rollback && (safeFor(completed.job) || completed.job != victim))
                if case .present(_,_,_,_,let running)=presence {
                    if running || !startIssued || exitCode==nil {exitProof.removeValue(forKey:completed.job)}
                    else if let exitCode {exitProof[completed.job]=exitCode==0 && !oom}
                }
                if let next {try dispatch(next,job:completed.job)}
            case .success(.acknowledged):break
            }
        }
        let records=try journal.sandboxRecords()
        let jobIndex=Dictionary(uniqueKeysWithValues:try journal.jobs().map {($0.id,$0)})
        let retained=Set(records.map(\.configuration.job))
        released.formIntersection(retained)
        exitProof=exitProof.filter {retained.contains($0.key)}
        lastInspect=lastInspect.filter {retained.contains($0.key)}
        if collectVM,!rollback,resourcePending==nil,now>=lastResource+2000 {
            lastResource=now
            if let target=records.first(where:{record in
                guard let job=jobIndex[record.configuration.job] else {return false}
                return job.state == .running && !record.removalProven && record.runtimeID != nil && job.lease.deadline-now>=10000 && inFlight[job.id]==nil && deferred[job.id]==nil
            }),let id=target.runtimeID,let job=jobIndex[target.configuration.job] {
                do {
                    try executor.submitResources(configuration:target.configuration,id:id,leaseUntil:job.lease.deadline)
                    resourcePending=(job.id,id)
                } catch AdmissionError.capacity {} // No operation was enqueued.
                catch {latestVM=nil}
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
                default:break
                }
                try dispatch(command,job:id);continue
            }
            if !safeFor(id) && job.state == .reserved { continue }
            if let command=try lifecycle.next(job:id,now:now,resourcesSafe:!rollback && (safeFor(id) || id != victim)) { try dispatch(command,job:id) }
        }
        revokingSince=revokingSince.filter{pendingCleanup.contains($0.key)}
        if now>=lastCycle+2000 { lastCycle=now }
    }
}
