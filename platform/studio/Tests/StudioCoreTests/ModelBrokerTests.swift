import Foundation
import CryptoKit
import CSQLite

func runModelBrokerTests() throws {
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let python=root.appendingPathComponent(".venv/bin/python")
    let sha=SHA256.hash(data:try Data(contentsOf:python.resolvingSymlinksInPath())).map {String(format:"%02x",$0)}.joined()
    let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("tests/fixtures/platform/model.json"))) as! [String:Any]
    let factory=try PythonWorkerFactory(invocation:python.path,executableSHA256:sha,policySHA256:fixture["policy_sha256"] as! String)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try Journal(directory:directory),owner=String(repeating:"a",count:64),id=UUID().uuidString.lowercased()
    _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:10_000))
    try journal.transitionJob(id:id,to:.running,now:10_000)
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest("http://127.0.0.1:1/v1"),nativeEpoch:"native-fixture-one",sequence:1,sampledAt:10_000,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let sample=ResourceSample(sampledAt:10_000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:10_000)
    let broker=ModelBroker(journal:journal,factory:factory)
    var admission=AdmissionPolicy()
    do {
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,nativeCapacityProven:false,sample:sample,admission:&admission,now:10_000)
        fatalError("Unknown native capacity dispatched")
    } catch AdmissionError.capacity {}
    guard try journal.requestCount(job:id)==0,broker.activeWorkers==0 else { fatalError("Rejected capacity spent permission") }
    do {
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,nativeCapacityProven:false,sample:sample,admission:&admission,now:9999)
        fatalError("Clock rollback accepted")
    } catch AdmissionError.expired {}
    guard try journal.jobs().first?.state == .revoking else { fatalError("Broker clock rollback did not durably revoke job") }
    // Exercise the real factory's opaque pre-spawn cancellation through the
    // broker while SQLite temporarily refuses its local acknowledgement.
    let recovery=try Journal(directory:directory.appendingPathComponent("recovery"))
    let recoveryID=UUID().uuidString.lowercased()
    _=try recovery.reserveJob(DurableJob(id:recoveryID,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:10_000))
    try recovery.transitionJob(id:recoveryID,to:.running,now:10_000)
    try recovery.claim(job:recoveryID,attempt:0,model:binding.canonicalModel,scope:binding.inferenceScope())
    let plan=try recovery.planWorkerStart(job:recoveryID,attempt:0)
    let operation=try factory.beginStart(binding:binding,plan:plan,started:0,now:10_000,initiallyCancelled:true)
    let recovering=ModelBroker(journal:recovery,factory:factory)
    try recovering.retainStart(operation:operation,plan:plan,binding:binding,packet:Data(),started:0)
    var held=AdmissionPolicy()
    let key="model:\(recoveryID):0"
    try held.reserveWorker(key:key,sample:sample,now:10_000)
    // Mark revocation before locking so only completion acknowledgement fails.
    try recovering.cancel(job:recoveryID,uptime:0)
    usleep(10_000)
    var writer:OpaquePointer?
    guard sqlite3_open_v2(directory.appendingPathComponent("recovery/state.sqlite").path,&writer,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let writer else {throw JournalError.storage}
    defer {sqlite3_close(writer)}
    guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    for _ in 0..<3 {_=try recovering.poll(now:10_000,uptime:0,admission:&held,source:{_ in binding})}
    guard recovering.active(job:recoveryID),try recovery.activeLaunchCount()==1,try recovery.workerGrants().isEmpty else {fatalError("Storage failure lost once-only completion")}
    guard sqlite3_exec(writer,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    _=try recovering.poll(now:10_000,uptime:0,admission:&held,source:{_ in binding})
    guard !recovering.active(job:recoveryID),try recovery.activeLaunchCount()==0,
          try recovery.inferenceScope(job:recoveryID,attempt:0)?.state == .not_sent,
          try recovery.requestCount(job:recoveryID)==1 else {fatalError("Retained completion did not recover exactly once")}
    _=try recovering.poll(now:10_000,uptime:0,admission:&held,source:{_ in binding})
    print("PASS: broker retains opaque no-spawn completion across repeated SQLite writer failures without respawn or budget refund")
    let childID=UUID().uuidString.lowercased(),childStarted=Int64(ProcessInfo.processInfo.systemUptime*1000)
    _=try recovery.reserveJob(DurableJob(id:childID,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:10_000))
    try recovery.transitionJob(id:childID,to:.running,now:10_000)
    try recovery.claim(job:childID,attempt:0,model:binding.canonicalModel,scope:binding.inferenceScope())
    let childPlan=try recovery.planWorkerStart(job:childID,attempt:0)
    let childOperation=try factory.beginStart(binding:binding,plan:childPlan,started:childStarted,now:10_000)
    var childResult:Result<StartedPythonWorker,WorkerStartFailure>?
    let childDeadline=ProcessInfo.processInfo.systemUptime+2
    while childResult==nil && ProcessInfo.processInfo.systemUptime<childDeadline {childResult=childOperation.take();if childResult==nil {usleep(1000)}}
    guard let childResult,case .success=childResult else {throw RuntimeError.launch}
    let retainedChild=PendingPythonWorker {_ in childResult}
    try recovering.retainStart(operation:retainedChild,plan:childPlan,binding:binding,packet:Data(),started:childStarted)
    try held.reserveWorker(key:"model:\(childID):0",sample:sample,now:10_000)
    usleep(5000)
    guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    for _ in 0..<3 {_=try recovering.poll(now:10_000,uptime:childStarted,admission:&held,source:{_ in binding})}
    guard recovering.active(job:childID),try recovery.activeLaunchCount()==1,try recovery.workerGrants().isEmpty else {fatalError("Binding failure lost original started child")}
    guard sqlite3_exec(writer,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    let reapedBy=ProcessInfo.processInfo.systemUptime+3
    while recovering.active(job:childID) && ProcessInfo.processInfo.systemUptime<reapedBy {
        _=try recovering.poll(now:10_000,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&held,source:{_ in binding})
        usleep(5000)
    }
    guard !recovering.active(job:childID),try recovery.activeLaunchCount()==0,try recovery.workerGrants().isEmpty,
          try recovery.inferenceScope(job:childID,attempt:0)?.state == .uncertain,
          try recovery.unresolvedCount()==1,try recovery.requestCount(job:childID)==1 else {fatalError("Started-child recovery lost uncertainty or durable local reap")}
    print("PASS: original started child survives binding storage failure for exact local kill/bind/reap, no permission bytes or respawn, native uncertainty retained")
    func exerciseSourceContinuity(_ scenario:String)throws {
        let continuityJournal=try Journal(directory:directory.appendingPathComponent("source-continuity-"+scenario))
        let continuityBroker=ModelBroker(journal:continuityJournal,factory:factory)
        var continuityAdmission=AdmissionPolicy()
        let olderID=UUID().uuidString.lowercased()
        _=try continuityJournal.reserveJob(DurableJob(id:olderID,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:10_000))
        try continuityJournal.transitionJob(id:olderID,to:.running,now:10_000)
        try continuityJournal.claim(job:olderID,attempt:0,model:binding.canonicalModel,scope:binding.inferenceScope())
        try continuityJournal.markUncertain(job:olderID,attempt:0)
        let continuityID=UUID().uuidString.lowercased()
        _=try continuityJournal.reserveJob(DurableJob(id:continuityID,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:10_000))
        try continuityJournal.transitionJob(id:continuityID,to:.running,now:10_000)
        try continuityJournal.claim(job:continuityID,attempt:0,model:binding.canonicalModel,scope:binding.inferenceScope())
        let continuityPlan=try continuityJournal.planWorkerStart(job:continuityID,attempt:0)
        let gate=DispatchSemaphore(value:0)
        let blocked=PendingPythonWorker {_ in
            _=gate.wait(timeout:.now()+5)
            return .failure(.cancelled) // This fixture never creates a process/RPC.
        }
        defer {gate.signal()}
        try continuityBroker.retainStart(operation:blocked,plan:continuityPlan,binding:binding,packet:Data(),started:0)
        try continuityAdmission.reserveWorker(key:"model:\(continuityID):0",sample:sample,now:10_000)
        func observed(_ sequence:UInt64,sampledAt:Int64=10_000)->WorkerDispatchBinding {
            let value=NativeSnapshot(host:binding.host,endpointHash:snapshot.endpointHash,nativeEpoch:snapshot.nativeEpoch,
                sequence:sequence,sampledAt:sampledAt,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
            return WorkerDispatchBinding(baseURL:binding.baseURL,guardPath:binding.guardPath,host:binding.host,profileHash:binding.profileHash,
                managerEpoch:binding.managerEpoch,canonicalModel:binding.canonicalModel,nativeModel:binding.nativeModel,nativeSnapshot:value,
                nativeCompatibilityAccepted:true,apiKey:nil)
        }
        _=try continuityBroker.poll(now:10_000,uptime:0,admission:&continuityAdmission,source:{_ in observed(3)})
        guard try continuityJournal.jobs().first(where:{$0.id==continuityID})?.state == .running else {fatalError("Advancing source revoked launch")}
        var continuityWriter:OpaquePointer?
        guard sqlite3_open_v2(directory.appendingPathComponent("source-continuity-"+scenario+"/state.sqlite").path,&continuityWriter,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,
              let continuityWriter else {throw JournalError.storage}
        defer {sqlite3_close(continuityWriter)}
        guard sqlite3_exec(continuityWriter,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        do {
            _=try continuityBroker.poll(now:scenario=="lease_clock" ? 9999:10_000,uptime:0,admission:&continuityAdmission,
                source:{_ in scenario=="missing" ? nil:observed(scenario=="clock" || scenario=="lease_clock" ? 4:2,sampledAt:scenario=="clock" ? 9999:10_000)})
        }catch JournalError.storage {}
        guard sqlite3_exec(continuityWriter,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        _=try continuityBroker.poll(now:10_000,uptime:0,admission:&continuityAdmission,source:{_ in observed(4)})
        guard try continuityJournal.jobs().first(where:{$0.id==continuityID})?.state == .revoking,
              try continuityJournal.inferenceScope(job:continuityID,attempt:0)?.state == .uncertain else {
            fatalError("BROKER_SOURCE_REGRESSION_ABOVE_ORIGINAL_MINIMUM_ACCEPTED \(scenario)")
        }
        gate.signal()
        let continuityDeadline=ProcessInfo.processInfo.systemUptime+3
        while continuityBroker.active(job:continuityID) && ProcessInfo.processInfo.systemUptime<continuityDeadline {
            _=try continuityBroker.poll(now:10_000,uptime:0,admission:&continuityAdmission,source:{_ in observed(4)});usleep(1000)
        }
        guard !continuityBroker.active(job:continuityID),try continuityJournal.unresolvedCount()==2,
              try continuityJournal.inferenceScope(job:continuityID,attempt:0)?.state == .uncertain,
              try continuityJournal.inferenceScope(job:olderID,attempt:0)?.state == .uncertain else {fatalError("Source regression lost independent uncertainty")}
        print("PASS: \(scenario) source regression survives failed durable revocation, retains both native uncertainties and never invokes a model")
    }
    for scenario in ["sequence","clock","missing","lease_clock"] {try exerciseSourceContinuity(scenario)}
    print("PASS: broker owner lease/native-capacity fail-closed and irreversible clock fencing")
}
