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
    let sandboxID=UUID().uuidString.lowercased()
    let sandbox=try SandboxConfiguration(job:sandboxID,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
    _=try journal!.reserveSandbox(job:DurableJob(id:sandboxID,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"c",count:64),requestHash:String(repeating:"d",count:64),created:9000),configuration:sandbox)
    try journal!.commitSandboxCreate(sandbox,now:9000)
    journal=nil;journal=try Journal(directory:directory)
    var restored=AdmissionPolicy()
    _=try WorkerReconciler(journal:journal!,admission:&restored)
    let sensors=ResourceSample(sampledAt:10_000,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:10_000,cpuSampledAt:10_000)
    let unavailable=ResourceSample(sampledAt:10_000,physical:128<<30,available:nil,vmAvailable:nil,diskFree:nil,cpu:nil,pressure:.normal,thermal:.nominal)
    do {try restored.reserveWorker(key:"second",sample:unavailable,now:10_000);fatalError("Missing sensors admitted a worker")} catch AdmissionError.capacity {}
    let nextSandbox=UUID().uuidString.lowercased()
    do {try restored.reserve(job:nextSandbox,memory:512<<20,cpus:1,sample:unavailable,now:10_000);fatalError("Missing sensors admitted a sandbox")} catch AdmissionError.capacity {}
    let native=HostRAMBudget.nativeHeadroom(physicalBytes:128<<30)
    let tight=ResourceSample(sampledAt:10_000,physical:128<<30,available:native+(1536<<20)-1,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:10_000,cpuSampledAt:10_000)
    do {try restored.reserveWorker(key:"second",sample:tight,now:10_000);fatalError("A restored charge was omitted from combined memory headroom")} catch AdmissionError.capacity {}
    let exact=ResourceSample(sampledAt:10_000,physical:128<<30,available:native+(1536<<20),vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:10_000,cpuSampledAt:10_000)
    for (vmAt,accepted) in [(4999,false),(5000,true),(11000,true),(11001,false)] {
        let mixed=ResourceSample(sampledAt:10_000,physical:128<<30,available:native+(1536<<20),vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:Int64(vmAt),cpuSampledAt:10_000)
        var sandboxProbe=restored,workerProbe=restored
        do {
            try sandboxProbe.reserve(job:nextSandbox,memory:512<<20,cpus:1,sample:mixed,now:10_000)
            guard accepted else {fatalError("Fresh host sample extended independent VM freshness")}
        } catch AdmissionError.stale {guard !accepted else {throw AdmissionError.stale}}
        try workerProbe.reserveWorker(key:"second",sample:mixed,now:10_000)
        let mixedCPU=ResourceSample(sampledAt:10_000,physical:128<<30,available:native+(1536<<20),vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:10_000,cpuSampledAt:Int64(vmAt))
        for sandboxRequest in [false,true] {
            var probe=restored
            do {
                if sandboxRequest {try probe.reserve(job:nextSandbox,memory:512<<20,cpus:1,sample:mixedCPU,now:10_000)}
                else {try probe.reserveWorker(key:"second",sample:mixedCPU,now:10_000)}
                guard accepted else {fatalError("Fresh host sample extended independent CPU freshness")}
            } catch AdmissionError.stale {guard !accepted else {throw AdmissionError.stale}}
        }
    }
    var exactWorker=restored,exactSandbox=restored
    try exactWorker.reserveWorker(key:"second",sample:exact,now:10_000)
    try exactSandbox.reserve(job:nextSandbox,memory:512<<20,cpus:1,sample:exact,now:10_000)
    try restored.reserve(job:nextSandbox,memory:512<<20,cpus:1,sample:sensors,now:10_000)
    do {try restored.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:sensors,now:10_000);fatalError("Issued sandbox lost its slot alongside worker recovery")} catch AdmissionError.capacity {}
    try restored.reserveWorker(key:"second",sample:sensors,now:10_000)
    do { try restored.reserveWorker(key:"third",sample:sensors,now:10_000);fatalError("Unbound launch lost its memory slot on restart") } catch AdmissionError.capacity {}
    print("PASS: durable job/request/launch idempotency, pre-spawn slot recovery and uncertainty-safe terminal retention")
}
