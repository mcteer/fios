import Foundation
import Darwin

enum WorkerResourceError:Error { case unavailable, invalid }
enum WorkerMemoryAction { case continueRunning, terminate, kill, cleanupOverdue }

enum WorkerResources {
    private static func usage(pid:Int32) throws -> rusage_info_v2 {
        guard pid>1 else { throw WorkerResourceError.invalid }
        var usage=rusage_info_v2()
        let code=withUnsafeMutablePointer(to:&usage) { value in
            value.withMemoryRebound(to:rusage_info_t?.self,capacity:1) { proc_pid_rusage(pid,RUSAGE_INFO_V2,$0) }
        }
        guard code==0 else { throw WorkerResourceError.unavailable }
        return usage
    }
    static func residentBytes(pid:Int32) throws -> UInt64 {
        let value=try usage(pid:pid).ri_resident_size
        guard value>0 else { throw WorkerResourceError.unavailable };return value
    }
    static func startIdentifier(pid:Int32) throws -> UInt64 {
        let value=try usage(pid:pid).ri_proc_start_abstime
        guard value>0 else { throw WorkerResourceError.unavailable };return value
    }
}

// Driven at least once per second by the serialized worker supervisor. A
// missing sensor is a revocation, not a zero-memory sample. Reaping is a
// separate fact: no action here releases inference ownership/reservations.
struct WorkerMemoryGuard {
    private var previous:Int64
    private var revokedAt:Int64?
    init(started:Int64) throws {
        guard started>=0,started<=ActivityPolicy.maximumTimestamp-2000 else { throw WorkerResourceError.invalid }
        previous=started
    }
    mutating func observe(resident:UInt64?,now:Int64) throws -> WorkerMemoryAction {
        guard now>=0,now<=ActivityPolicy.maximumTimestamp else { throw WorkerResourceError.invalid }
        if now<previous {
            revokedAt=now;previous=now
            return .kill
        }
        if now-previous>2000 || resident==nil || resident!>512<<20 {
            revokedAt=revokedAt ?? max(now,previous)
        }
        previous=max(previous,now)
        guard let revokedAt else { return .continueRunning }
        if now>=revokedAt+2000 { return .cleanupOverdue }
        if now>=revokedAt+1000 { return .kill }
        return .terminate
    }
}
