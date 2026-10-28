import Foundation

func runSandboxJournalTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    var journal:Journal?=try Journal(directory:directory)
    let job=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:1000)
    let config=try SandboxConfiguration(job:job.id,nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1)
    let reserved=try journal!.reserveSandbox(job:job,configuration:config)
    guard !reserved.createIssued,reserved.runtimeID==nil else { fatalError("Reservation claimed external side effect") }
    var issued=reserved;issued.createIssued=true
    try journal!.saveSandbox(issued)
    journal=nil
    journal=try Journal(directory:directory)
    let restored=try journal!.sandboxRecords().first!
    guard restored.createIssued,restored.runtimeID==nil,try journal!.jobs().first?.state == .reconciling else { fatalError("Lost-create intent replayable after restart") }
    do { try journal!.saveSandbox(reserved);fatalError("Create intent reset accepted") } catch JournalError.conflict {}
    do { try journal!.confirmSandboxAbsent(job:job.id);fatalError("Unknown create released from sampled absence") } catch JournalError.conflict {}
    var known=restored;known.runtimeID=String(repeating:"e",count:64)
    try journal!.saveSandbox(known)
    var changed=known;changed.runtimeID=String(repeating:"f",count:64)
    do { try journal!.saveSandbox(changed);fatalError("Saved daemon identity overwritten") } catch JournalError.conflict {}
    try journal!.transitionJob(id:job.id,to:.revoking)
    do { try journal!.transitionJob(id:job.id,to:.removed);fatalError("Reservation released before absence proof") } catch JournalError.conflict {}
    try journal!.confirmSandboxAbsent(job:job.id) // Fake adapter's authoritative known-ID absence.
    try journal!.transitionJob(id:job.id,to:.removed)
    print("PASS: atomic sandbox reservation, immutable policy/nonce, lost-create/identity fencing and proof-gated reservation release")
}
