import Foundation

func runJournalViewTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory)
    guard try journal.jobs().isEmpty,try journal.sandboxRecords().isEmpty else {throw JournalError.invalid}
    let job=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:10000)
    let config=try SandboxConfiguration(job:job.id,nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1)
    var record=try journal.reserveSandbox(job:job,configuration:config)
    guard try journal.jobs().count==1,try journal.sandboxRecords().count==1 else {throw JournalError.storage}
    var copy=try journal.jobs();copy[0].lease.revoke()
    guard try !journal.jobs()[0].lease.revoked else {fatalError("Decoded journal view escaped value isolation")}
    record.createIssued=true;try journal.saveSandbox(record)
    guard try journal.sandboxRecords()[0].createIssued else {fatalError("Sandbox mutation left stale decoded view")}
    var invalid=record;invalid.runtimeID="not-a-full-id"
    do {try journal.saveSandbox(invalid);fatalError("Invalid transaction accepted")}catch JournalError.invalid {}
    guard try journal.sandboxRecords()[0].runtimeID==nil else {fatalError("Rollback left uncommitted cached sandbox")}
    record.runtimeID=String(repeating:"e",count:64);try journal.saveSandbox(record)
    try journal.confirmSandboxAbsent(job:job.id) // Synthetic metadata-only absence proof in test.
    try journal.transitionJob(id:job.id,to:.revoking,now:11000)
    try journal.transitionJob(id:job.id,to:.removed,now:12000)
    guard try journal.jobs()[0].state == .removed,try journal.sandboxRecords()[0].removalProven else {fatalError("Terminal mutation left stale decoded views")}
    try journal.expireTerminalJobs(now:12000+24*60*60*1000+1)
    guard try journal.jobs().isEmpty,try journal.sandboxRecords().isEmpty else {fatalError("Expiration left cached tombstones")}
    print("PASS: bounded decoded journal views invalidate on insertion/update/rollback/expiration and retain value isolation; single exclusive writer only")
}
