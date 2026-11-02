import Foundation
import Darwin

// Owns only prior-manager private-child grants, never native serving/VM PIDs.
// Missing PID launch intents stay reserved/degraded without a separately
// reviewed complete historical-image absence census. Neither age nor an idle
// native snapshot is local child-absence proof.
final class WorkerReconciler {
    private struct Entry {
        let job:String
        let attempt:Int
        let grant:WorkerGrant
        var began:Int64?
        var killed=false
    }
    private let journal:Journal
    private var entries:[Entry]
    private let unknownLaunches:Int
    private var lateUnbound:Set<WorkerLaunchKey>=[]
    private(set) var overdue=false
    init(journal:Journal,admission:inout AdmissionPolicy,census:WorkerCensusPolicy? = nil) throws {
        self.journal=journal
        let grants=try journal.workerGrants()
        entries=grants.map { Entry(job:$0.job,attempt:$0.attempt,grant:$0.grant) }
        let known=Set(grants.map {"\($0.job):\($0.attempt)"})
        let unknown=try journal.activeLaunches().filter {!known.contains("\($0.job):\($0.attempt)")}
        var retained=unknown.count
        // Startup only, before accepting/spawning new work. Failure or a
        // foreign same-image sentinel retains every affected reservation.
        if !unknown.isEmpty,let census,let proof=try? census.absence() {
            for launch in unknown where launch.boot==proof.boot {
                do {try journal.recordUnboundWorkerGone(job:launch.job,attempt:launch.attempt,nonce:launch.nonce,proof:proof);retained-=1}
                catch {} // No guessed release; no native inference completion.
            }
        }
        unknownLaunches=retained
        try ModelBroker.restoreReservations(journal:journal,admission:&admission)
    }
    func poll(now:Int64,admission:inout AdmissionPolicy,failedLaunches:Set<WorkerLaunchKey>=[]) throws {
        guard (0...ActivityPolicy.maximumTimestamp-2000).contains(now) else { throw WorkerResourceError.invalid }
        guard failedLaunches.count<=2 else {throw JournalError.trackingLimit}
        // Only the broker's explicit failed-start set may be adopted here.
        // Healthy current workers remain under their original PrivateWorker.
        let grants=try journal.workerGrants()
        var unbound=Set<WorkerLaunchKey>()
        for key in failedLaunches where try !journal.workerLaunchReaped(job:key.job,attempt:key.attempt) {
            try admission.restoreWorker(key:key.reservationKey)
            if let owned=grants.first(where:{$0.job==key.job && $0.attempt==key.attempt}) {
                if !entries.contains(where:{$0.job==key.job && $0.attempt==key.attempt}) {
                    entries.append(Entry(job:key.job,attempt:key.attempt,grant:owned.grant))
                }
            }else {unbound.insert(key)}
        }
        lateUnbound=unbound
        var pending:[Entry]=[]
        for var entry in entries {
            if try entry.grant.provenGone() {
                try journal.recordWorkerGone(job:entry.job,attempt:entry.attempt,grant:entry.grant)
                admission.releaseWorkerAfterReap(key:"model:\(entry.job):\(entry.attempt)")
                continue
            }
            // Inaccessible/mismatched identity never authorizes signalling.
            guard try HostBoot.identity()==entry.grant.boot,
                  (try? WorkerResources.startIdentifier(pid:entry.grant.pid))==entry.grant.start else {
                overdue=true;pending.append(entry);continue
            }
            if let began=entry.began {
                if now<began || now-began>=1000 {
                    if !entry.killed { kill(entry.grant.pid,SIGKILL);entry.killed=true }
                }
                if now>=began && now-began>=2000 { overdue=true }
            } else {
                entry.began=now
                kill(entry.grant.pid,SIGTERM)
            }
            pending.append(entry)
        }
        entries=pending
        // No journal.complete here: process death is never inference proof.
    }
    var degraded:Bool { overdue || unknownLaunches>0 || !lateUnbound.isEmpty }
    var pending:Int { entries.count+unknownLaunches+lateUnbound.count }
}
