import Foundation

func runJobJournalTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let job=UUID().uuidString.lowercased(), key=UUID().uuidString.lowercased()
    let record=try DurableJob(id:job,idempotency:key,ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:1000)
    var journal:Journal?=try Journal(directory:directory)
    let first=try journal!.reserveJob(record)
    guard first.id==job, try journal!.reserveJob(record).id==job else { fatalError("Idempotency failed") }
    let collision=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:key,ownerHash:String(repeating:"c",count:64),requestHash:String(repeating:"b",count:64),created:1000)
    do { _=try journal!.reserveJob(collision);fatalError("Cross-owner idempotency accepted") } catch JournalError.conflict {}
    let changedInput=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:key,ownerHash:record.ownerHash,requestHash:String(repeating:"c",count:64),created:1000)
    do {_ = try journal!.reserveJob(changedInput);fatalError("Input hash changed under the same idempotency identity")}catch JournalError.conflict{}
    try journal!.transitionJob(id:job,to:.creating)
    do { try journal!.transitionJob(id:job,to:.removed);fatalError("Unsafe removal transition accepted") } catch JournalError.conflict {}
    journal=nil
    journal=try Journal(directory:directory)
    guard try journal!.jobs().first?.state == .reconciling else { fatalError("Restart did not fence active job") }
    do { try journal!.renewJob(id:job,ownerHash:String(repeating:"c",count:64),now:2000);fatalError("Wrong owner renewed") } catch JournalError.conflict {}
    // A reconciled job cannot regain its execution lease.
    do { try journal!.renewJob(id:job,ownerHash:record.ownerHash,now:2000);fatalError("Restart revived lease") } catch JournalError.conflict {}
    try journal!.transitionJob(id:job,to:.revoking)
    try journal!.transitionJob(id:job,to:.removed,now:3000)
    guard try journal!.jobs().first?.state == .removed else { fatalError("Cleanup state missing") }
    guard try journal!.reserveJob(record).state == .removed else { fatalError("Idempotent request replayed execution") }
    try journal!.expireTerminalJobs(now:3000+86_400_000-1)
    guard try journal!.jobs().count==1 else { fatalError("Tombstone removed early") }
    try journal!.expireTerminalJobs(now:3000+86_400_000)
    guard try journal!.jobs().isEmpty else { fatalError("Expired terminal job retained") }
    let held=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),ownerHash:record.ownerHash,requestHash:record.requestHash,created:1000)
    _=try journal!.reserveJob(held)
    try journal!.claim(job:held.id,attempt:0,model:"exact-model")
    try journal!.markUncertain(job:held.id,attempt:0)
    try journal!.transitionJob(id:held.id,to:.revoking)
    try journal!.transitionJob(id:held.id,to:.removed,now:3000)
    try journal!.expireTerminalJobs(now:3000+86_400_000)
    guard try journal!.jobs().count==1,try journal!.unresolvedCount()==1 else { fatalError("Age removed unresolved ownership") }
    try journal!.complete(job:held.id,attempt:0)
    try journal!.expireTerminalJobs(now:3000+86_400_000)
    guard try journal!.jobs().isEmpty else { fatalError("Proven terminal record not pruned") }
    let scoped=UUID().uuidString.lowercased(),request=UUID().uuidString.lowercased()
    try journal!.claim(job:scoped,attempt:0,model:"exact-model",requestID:request)
    try journal!.complete(job:scoped,attempt:0)
    do { try journal!.claim(job:scoped,attempt:1,model:"exact-model",requestID:request);fatalError("Duplicate scoped request replayed") } catch JournalError.conflict {}
    guard try journal!.requestCount(job:scoped)==1 else { fatalError("Rejected replay consumed another request") }
    try journal!.claim(job:scoped,attempt:1,model:"exact-model",requestID:UUID().uuidString.lowercased())
    try journal!.complete(job:scoped,attempt:1)
    journal=nil;journal=try Journal(directory:directory)
    do { try journal!.claim(job:scoped,attempt:2,model:"exact-model",requestID:request);fatalError("Restart forgot scoped request tombstone") } catch JournalError.conflict {}
    guard try journal!.requestCount(job:scoped)==2 else { fatalError("Restart lost finite request budget") }
    let unbound=UUID().uuidString.lowercased()
    try journal!.claim(job:unbound,attempt:0,model:"exact-model")
    _=try journal!.planWorkerLaunch(job:unbound,attempt:0)
    do { _=try journal!.planWorkerLaunch(job:unbound,attempt:0);fatalError("Launch intent replayed") } catch JournalError.conflict {}
    journal=nil;journal=try Journal(directory:directory)
    try journal!.recoverWorkerMetadata()
    guard try journal!.activeLaunchCount()==1,try journal!.workerGrants().isEmpty,try journal!.unresolvedCount()==1 else { fatalError("Restart cleared unbound launch/memory/native uncertainty") }
    var restored=AdmissionPolicy()
    try ModelBroker.restoreReservations(journal:journal!,admission:&restored)
    let sensors=ResourceSample(sampledAt:10_000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    try restored.reserveWorker(key:"second",sample:sensors,now:10_000)
    do { try restored.reserveWorker(key:"third",sample:sensors,now:10_000);fatalError("Unbound launch lost its memory slot on restart") } catch AdmissionError.capacity {}
    print("PASS: durable job/request/launch idempotency, pre-spawn slot recovery and uncertainty-safe terminal retention")
}
