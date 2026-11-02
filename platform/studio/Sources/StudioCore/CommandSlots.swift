import Foundation
import Darwin

// Process-wide native command bound, including queries inside resource reads.
// A timeout does not release a still-running local child. Retain its exact
// Process handle until exit/reap proof; never signal a recycled numeric PID.
final class CommandSlots:@unchecked Sendable {
    static let shared=CommandSlots()
    private let lock=NSLock()
    private var occupied=0
    private struct Child {
        let process:Process
        let start:UInt64?
        var gone:Bool {
            guard !process.isRunning else {return false}
            let pid=process.processIdentifier
            guard pid>1 else {return true} // Spawn never produced a child.
            if let start,let current=try? WorkerResources.startIdentifier(pid:pid) {return current != start}
            return kill(pid,0)<0 && errno==ESRCH
        }
    }
    private var retained:[Child]=[]
    func acquire()throws {
        lock.lock();defer {lock.unlock()}
        var alive:[Child]=[]
        for child in retained {
            if child.gone {occupied-=1}
            else {alive.append(child)}
        }
        retained=alive
        guard occupied<2 else {throw RuntimeError.capacity}
        occupied+=1
    }
    func release(_ process:Process?,start:UInt64?=nil) {
        lock.lock();defer {lock.unlock()}
        if let process {
            let child=Child(process:process,start:start)
            if !child.gone {retained.append(child);return}
        }
        // Foundation has already observed exit, and kernel absence (or a
        // different captured start) proves the original local child gone.
        // Never perform an unbounded notification join while holding the lock.
        occupied-=1
    }
}
