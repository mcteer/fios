import Foundation

public struct PlatformSandboxReservations:Sendable {
    public let memoryBytes:UInt64
    public let cpus:Int
    public let workspaceBytes:UInt64
}

// Aggregate diagnostic metadata only: no job/model/owner identity or content.
public struct PlatformWorkloadSample:Sendable {
    public let sampledAt:Int64
    public let jobs:[JobState:Int]
    public let unresolvedRecords:Int
    public let uncertainRecords:Int
    public let workerReservations:Int
    public let artifactBytes:Int64
    public let artifactJobs:Int
    public let cleanupPending:Int?
    public let cleanupWaitMilliseconds:Int64?
    public let sandboxReservations:PlatformSandboxReservations?
    public init(sampledAt:Int64,jobs:[JobState:Int],unresolvedRecords:Int,uncertainRecords:Int,
                workerReservations:Int,artifactBytes:Int64,artifactJobs:Int,cleanupPending:Int?=nil,cleanupWaitMilliseconds:Int64?=nil,
                sandboxReservations:PlatformSandboxReservations?=nil) {
        self.sampledAt=sampledAt;self.jobs=jobs;self.unresolvedRecords=unresolvedRecords
        self.uncertainRecords=uncertainRecords;self.workerReservations=workerReservations
        self.artifactBytes=artifactBytes;self.artifactJobs=artifactJobs
        self.cleanupPending=cleanupPending;self.cleanupWaitMilliseconds=cleanupWaitMilliseconds
        self.sandboxReservations=sandboxReservations
    }
}

enum WorkloadTelemetry {
    // Called only on the existing serialized manager loop/journal owner.
    // Failure omits the whole sample; telemetry cannot change control flow or
    // substitute zero for a failed query. No additional SQLite instance opens.
    static func sample(journal:Journal,artifactBytes:Int64,artifactJobs:Int,now:Int64,cleanupPending:Int?=nil,cleanupWaitMilliseconds:Int64?=nil)->PlatformWorkloadSample? {
        do {
            var counts=Dictionary(uniqueKeysWithValues:JobState.allCases.map{($0,0)})
            for job in try journal.jobs() {counts[job.state,default:0]+=1}
            // Cancellation/state labels do not release declared resources.
            // Keep every record until its own runtime absence is confirmed.
            let sandboxes=try journal.sandboxRecords().filter{!$0.removalProven}
            let reservations=PlatformSandboxReservations(memoryBytes:sandboxes.reduce(0){$0+$1.configuration.memory},
                cpus:sandboxes.reduce(0){$0+$1.configuration.cpus},
                workspaceBytes:sandboxes.reduce(0){$0+$1.configuration.workspace})
            return try PlatformWorkloadSample(sampledAt:now,jobs:counts,unresolvedRecords:journal.unresolvedCount(),
                uncertainRecords:journal.uncertainCount(),workerReservations:journal.activeLaunchCount(),
                artifactBytes:artifactBytes,artifactJobs:artifactJobs,
                cleanupPending:cleanupPending,cleanupWaitMilliseconds:cleanupWaitMilliseconds,sandboxReservations:reservations)
        }catch {return nil}
    }
}
