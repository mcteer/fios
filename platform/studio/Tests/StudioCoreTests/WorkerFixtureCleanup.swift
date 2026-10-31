import Foundation
import Darwin

// Test-only fallback for finite children that never issue a native request.
// No unbounded second Foundation wait, no unknown-PID signal, no inference
// claim release. Callers retain their private fixture journal on uncertainty.
func finishOwnedWorkerFixture(_ process:Process,grant:WorkerGrant?)->Bool {
    guard let grant else {return false}
    if process.isRunning,((try? grant.provenGone()) ?? false)==false,
       (try? HostBoot.identity())==grant.boot,
       (try? WorkerResources.startIdentifier(pid:grant.pid))==grant.start {
        kill(grant.pid,SIGKILL)
    }
    let deadline=ProcessInfo.processInfo.systemUptime+2
    while process.isRunning && ProcessInfo.processInfo.systemUptime<deadline {Thread.sleep(forTimeInterval:0.005)}
    return !process.isRunning && ((try? grant.provenGone()) ?? false)
}
