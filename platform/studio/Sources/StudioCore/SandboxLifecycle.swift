import Foundation

enum SandboxCommand:Sendable {
    case create(SandboxConfiguration), inspect(SandboxConfiguration,String?), start(String)
    case stop(String), remove(SandboxConfiguration,String)
}
enum SandboxPresence:Sendable {
    case absent
    case present(id:String,name:String,image:String,nonce:String,running:Bool)
}

// Serialized command/result controller. It never performs a blocking runtime
// call on the manager heartbeat loop. The external executor has a fixed argv
// adapter; every side-effect intent is durable before returning a command.
final class SandboxLifecycle {
    private let journal:Journal
    private var previous:Int64 = -1
    private func clockSafe(_ now:Int64) throws -> Bool {
        guard now>=0,now<=ActivityPolicy.maximumTimestamp else { throw JournalError.invalid }
        let valid=now>=previous;previous=max(previous,now);return valid
    }
    init(journal:Journal) { self.journal=journal }
    private func current(_ id:String) throws -> (DurableJob,SandboxRecord) {
        guard let job=try journal.jobs().first(where:{$0.id==id}),
              let record=try journal.sandboxRecords().first(where:{$0.configuration.job==id}) else { throw JournalError.invalid }
        return (job,record)
    }
    func next(job id:String,now:Int64,resourcesSafe:Bool) throws -> SandboxCommand? {
        let safe=try clockSafe(now) && resourcesSafe
        var (job,record)=try current(id)
        guard job.state != .removed else { return nil }
        if [.reserved,.creating,.running].contains(job.state) && (!safe || !job.lease.valid(now:now)) {
            try journal.transitionJob(id:id,to:.revoking,now:now)
            job=try current(id).0
        }
        if job.state == .reconciling { try journal.transitionJob(id:id,to:.revoking,now:now);job=try current(id).0 }
        if job.state == .reserved && !record.createIssued {
            try journal.transitionJob(id:id,to:.creating,now:now)
            record.createIssued=true;try journal.saveSandbox(record)
            return .create(record.configuration)
        }
        return .inspect(record.configuration,record.runtimeID)
    }
    func created(job id:String,runtimeID:String) throws {
        var (_,record)=try current(id)
        guard record.createIssued else { throw JournalError.conflict }
        record.runtimeID=runtimeID;try journal.saveSandbox(record)
        // A late create result records identity, not permission to start.
    }
    func observed(job id:String,presence:SandboxPresence,now:Int64,resourcesSafe:Bool) throws -> SandboxCommand? {
        let safe=try clockSafe(now) && resourcesSafe
        var (job,record)=try current(id)
        guard job.state != .removed else { return nil }
        switch presence {
        case .absent:
            // An unresolved create may still materialize after this snapshot.
            guard !record.createIssued || record.runtimeID != nil else { return nil }
            try journal.confirmSandboxAbsent(job:id)
            if [.reserved,.creating,.running,.reconciling].contains(job.state) { try journal.transitionJob(id:id,to:.revoking,now:now) }
            if job.state == .stopping { try journal.transitionJob(id:id,to:.removing,now:now) }
            try journal.transitionJob(id:id,to:.removed,now:now)
            return nil
        case .present(let runtimeID,let name,let image,let nonce,let running):
            let c=record.configuration
            guard name=="/"+c.name,image==c.image,nonce==c.nonce,
                  record.runtimeID==nil || record.runtimeID==runtimeID else { throw RuntimeError.identity }
            // A precommitted single create/name/nonce/image binds recovery;
            // never discover/adopt objects from a label or prefix scan.
            guard record.createIssued else { throw RuntimeError.identity }
            if record.runtimeID==nil { record.runtimeID=runtimeID;try journal.saveSandbox(record) }
            if [.reserved,.creating,.running].contains(job.state) && (!safe || !job.lease.valid(now:now)) {
                try journal.transitionJob(id:id,to:.revoking,now:now);job=try current(id).0
            }
            if job.state == .reconciling { try journal.transitionJob(id:id,to:.revoking,now:now);job=try current(id).0 }
            if job.state == .revoking {
                if running { try journal.transitionJob(id:id,to:.stopping,now:now);return .stop(runtimeID) }
                try journal.transitionJob(id:id,to:.stopping,now:now)
                try journal.transitionJob(id:id,to:.removing,now:now)
                return .remove(c,runtimeID)
            }
            if job.state == .stopping {
                // A lost/failed stop reply does not establish daemon grace or
                // exit. Retry the idempotent exact-owned stop (10s grace in
                // the adapter), never turn a running snapshot into rm --force.
                if running { return .stop(runtimeID) }
                try journal.transitionJob(id:id,to:.removing,now:now)
                return .remove(c,runtimeID)
            }
            if job.state == .removing {
                // Durable removal intent cannot bypass grace after a restart.
                if running { return .stop(runtimeID) }
                return .remove(c,runtimeID)
            }
            if running {
                guard record.startIssued else { throw RuntimeError.identity }
                if job.state == .creating { try journal.transitionJob(id:id,to:.running,now:now) }
                return nil
            }
            if record.startIssued {
                // Never replay a lost start. It may have completed and exited.
                try journal.transitionJob(id:id,to:.revoking,now:now)
                return nil
            }
            guard job.state == .creating else { throw JournalError.conflict }
            record.startIssued=true;try journal.saveSandbox(record)
            return .start(runtimeID)
        }
    }
    func cancelled(job id:String,now:Int64) throws {
        let (job,_)=try current(id)
        if [.reserved,.creating,.running,.reconciling].contains(job.state) { try journal.transitionJob(id:id,to:.revoking,now:now) }
    }
}
