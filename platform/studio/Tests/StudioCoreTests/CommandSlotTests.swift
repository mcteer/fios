import Foundation

func runCommandSlotTests() throws {
    let slots=CommandSlots()
    try slots.acquire();try slots.acquire()
    do {try slots.acquire();fatalError("Third native command slot accepted")}catch RuntimeError.capacity {}
    let child=Process();child.executableURL=URL(fileURLWithPath:"/bin/sleep");child.arguments=["5"]
    child.environment=["PATH":"/usr/bin:/bin"];child.standardInput=FileHandle.nullDevice;child.standardOutput=FileHandle.nullDevice;child.standardError=FileHandle.nullDevice
    try child.run()
    defer {if child.isRunning {child.terminate()};child.waitUntilExit()}
    slots.release(child) // Still alive: retain, not a freed command slot.
    do {try slots.acquire();fatalError("Unreaped child lost its native command reservation")}catch RuntimeError.capacity {}
    child.terminate();child.waitUntilExit()
    try slots.acquire() // Exact retained Process now has exit/reap proof.
    slots.release(nil);slots.release(nil)
    try slots.acquire();try slots.acquire();slots.release(nil);slots.release(nil)
    final class ExitedProcess:Process,@unchecked Sendable {
        var joined=0
        override var isRunning:Bool {false}
        override var processIdentifier:Int32 {123}
        override func waitUntilExit() {joined+=1}
    }
    let exited=ExitedProcess(),joinedSlots=CommandSlots()
    try joinedSlots.acquire();joinedSlots.release(exited)
    guard exited.joined==1 else {fatalError("Exited native child reservation released without an explicit join")}
    // An unlaunched Foundation Process must never be waited on.
    try joinedSlots.acquire();joinedSlots.release(Process())
    print("PASS: process-wide two-command bound retains unreaped owned child until exact exit proof; no PID-only signal or native-effect clearance")
}
