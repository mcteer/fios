import Foundation
import Darwin

func runWorkerResourceTests() throws {
    let resident=try WorkerResources.residentBytes(pid:getpid())
    guard resident>0 else { fatalError("RSS sampler returned empty observation") }
    var guardState=try WorkerMemoryGuard(started:1000)
    guard try guardState.observe(resident:512<<20,now:1000) == .continueRunning else { fatalError("Exact bound rejected") }
    guard try guardState.observe(resident:(512<<20)+1,now:2000) == .terminate else { fatalError("Memory breach not revoked") }
    guard try guardState.observe(resident:1,now:2500) == .terminate else { fatalError("Memory recovery revived revoked child") }
    guard try guardState.observe(resident:1,now:3000) == .kill else { fatalError("Unreaped child not escalated") }
    guard try guardState.observe(resident:1,now:4000) == .cleanupOverdue else { fatalError("Cleanup overrun hidden") }
    var unavailable=try WorkerMemoryGuard(started:1000)
    guard try unavailable.observe(resident:nil,now:1000) == .terminate else { fatalError("Unknown worker memory allowed") }
    print("PASS: native child RSS sampling and irreversible bounded memory-loss TERM/KILL/reap policy")
}
