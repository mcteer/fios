import Foundation

// Process-wide native command bound, including queries inside resource reads.
// A timeout does not release a still-running local child. Retain its exact
// Process handle until exit/reap proof; never signal a recycled numeric PID.
final class CommandSlots:@unchecked Sendable {
    static let shared=CommandSlots()
    private let lock=NSLock()
    private var occupied=0
    private var retained:[Process]=[]
    func acquire()throws {
        lock.lock();defer {lock.unlock()}
        var alive:[Process]=[]
        for process in retained {
            if process.isRunning {alive.append(process)}
            else {process.waitUntilExit();occupied-=1}
        }
        retained=alive
        guard occupied<2 else {throw RuntimeError.capacity}
        occupied+=1
    }
    func release(_ process:Process?) {
        lock.lock();defer {lock.unlock()}
        if let process,process.isRunning {retained.append(process)}
        else {
            // Even an already-exited child requires explicit join proof.
            // Never wait on a Process whose spawn failed before a PID existed.
            if let process,process.processIdentifier>1 {process.waitUntilExit()}
            occupied-=1
        }
    }
}
