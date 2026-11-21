import Foundation
import Darwin
import CSQLite

func runWorkerReapDurabilityTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var cleanupProven=true
    defer {
        if cleanupProven {try? FileManager.default.removeItem(at:directory)}
        else {FileHandle.standardError.write(Data("OWNED_WORKER_FIXTURE_RETAINED\n".utf8))}
    }
    let journal=try Journal(directory:directory),id=UUID().uuidString.lowercased()
    try journal.claim(job:id,attempt:0,model:"fixture/model")
    let nonce=try journal.planWorkerLaunch(job:id,attempt:0)
    let process=Process(),input=Pipe(),output=Pipe()
    process.executableURL=URL(fileURLWithPath:"/bin/sleep");process.arguments=["0.1"]
    process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
    var cleanupGrant:WorkerGrant?
    cleanupProven=false
    defer {cleanupProven=finishOwnedWorkerFixture(process,grant:cleanupGrant)}
    try process.run()
    let grant=try WorkerGrant.capture(pid:process.processIdentifier);cleanupGrant=grant
    let clock=Int64(ProcessInfo.processInfo.systemUptime*1000)
    let worker=try PrivateWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,journal:journal,job:id,attempt:0,started:clock,capturedGrant:grant,launchNonce:nonce)
    let end=ProcessInfo.processInfo.systemUptime+2
    while process.isRunning && ProcessInfo.processInfo.systemUptime<end {Thread.sleep(forTimeInterval:0.005)}
    guard !process.isRunning,try grant.provenGone() else {throw RuntimeError.deadline}
    // Same test process only: inject finite SQLite writer contention against
    // this disposable platform journal. No second app/manager, Fios DB or
    // native model request; rollback/close before retrying its original writer.
    var blocker:OpaquePointer?
    guard sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path,&blocker,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {throw JournalError.storage}
    defer {sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil);sqlite3_close(blocker)}
    guard sqlite3_exec(blocker,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    do {_=try worker.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:true);throw RuntimeError.identity}
    catch JournalError.storage {}
    guard !worker.reaped,try !journal.workerLaunchReaped(job:id,attempt:0),try journal.unresolvedCount()==1 else {
        FileHandle.standardError.write(Data("WORKER_REAP_PUBLISHED_BEFORE_DURABLE_MARKER\n".utf8));throw JournalError.conflict
    }
    guard sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    _=try worker.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:true)
    guard worker.reaped,try journal.workerLaunchReaped(job:id,attempt:0),try journal.uncertainCount()==1,
          try journal.requestCount(job:id)==1 else {throw JournalError.conflict}
    print("PASS: actual exited worker remains unreaped to broker on finite journal contention, retries durable local marker after rollback and preserves inference uncertainty/history; no native request")
}
