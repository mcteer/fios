import Foundation
import Darwin

func runCommandSlotTests() throws {
    let slots=CommandSlots()
    try slots.acquire();try slots.acquire()
    do {try slots.acquire();fatalError("Third native command slot accepted")}catch RuntimeError.capacity {}
    let child=Process();child.executableURL=URL(fileURLWithPath:"/bin/sleep");child.arguments=["5"]
    child.environment=["PATH":"/usr/bin:/bin"];child.standardInput=FileHandle.nullDevice;child.standardOutput=FileHandle.nullDevice;child.standardError=FileHandle.nullDevice
    try child.run()
    let grant=try WorkerGrant.capture(pid:child.processIdentifier)
    defer {precondition(finishOwnedWorkerFixture(child,grant:grant),"Owned finite command fixture exit remains unproven")}
    slots.release(child,start:grant.start) // Still alive: retain, not a freed command slot.
    do {try slots.acquire();fatalError("Unreaped child lost its native command reservation")}catch RuntimeError.capacity {}
    guard finishOwnedWorkerFixture(child,grant:grant) else {throw RuntimeError.deadline}
    try slots.acquire() // Exact retained Process now has exit/reap proof.
    slots.release(nil);slots.release(nil)
    try slots.acquire();try slots.acquire();slots.release(nil);slots.release(nil)
    // Foundation exit notification alone cannot free a reservation while
    // kernel absence is unresolved. This metadata-only double uses our own
    // live PID, is never signalled, and records any forbidden blocking join.
    final class UnprovenProcess:Process,@unchecked Sendable {
        var joined=0
        override var isRunning:Bool {false}
        override var processIdentifier:Int32 {getpid()}
        override func waitUntilExit() {joined+=1}
    }
    let unproven=UnprovenProcess(),heldSlots=CommandSlots()
    try heldSlots.acquire();try heldSlots.acquire();heldSlots.release(unproven)
    do {
        try heldSlots.acquire()
        FileHandle.standardError.write(Data("COMMAND_SLOT_RELEASED_UNPROVEN_CHILD\n".utf8));throw RuntimeError.identity
    } catch RuntimeError.capacity {}
    guard unproven.joined==0 else {
        FileHandle.standardError.write(Data("COMMAND_SLOT_WAITED_ON_NOTIFICATION\n".utf8));throw RuntimeError.identity
    }
    // An unlaunched Foundation Process must never be waited on.
    try slots.acquire();slots.release(Process())
    print("PASS: process-wide two-command bound retains unresolved child identity without a blocking join; no PID-only signal or native-effect clearance")
}
