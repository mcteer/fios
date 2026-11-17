import Foundation

// A normal cancelled worker-start result is terminal output, even when the
// surrounding owner job has not separately received a cancellation command.
func runTaskCompletionTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),owner=String(repeating:"a",count:64)
    func runningJob()throws->String {
        let id=UUID().uuidString.lowercased()
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:5000))
        try journal.transitionJob(id:id,to:.running,now:5000)
        return id
    }
    let id=try runningJob(),stillRunning=try runningJob()
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest("http://127.0.0.1:1/v1"),nativeEpoch:"fixture-native",sequence:1,sampledAt:5000,allClientLifecycleCoverage:true,residentModel:"fixture/model",outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/unused.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    guard try NativeAdmission.permitsDispatch(binding,now:5000) else {throw JournalError.invalid}
    try journal.claim(job:id,attempt:0,model:binding.canonicalModel,scope:binding.inferenceScope())
    let plan=try journal.planWorkerStart(job:id,attempt:0)
    let broker=ModelBroker(journal:journal)
    try broker.retainStart(operation:PendingPythonWorker {_ in .failure(.cancelled)},plan:plan,binding:binding,packet:Data(),started:5000)
    let controller=TaskController(journal:journal,broker:broker)
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:5000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    try admission.reserveWorker(key:"model:\(id):0",sample:sample,now:5000)
    var interrupted=false
    let deadline=ProcessInfo.processInfo.systemUptime+2
    repeat {
        let events=try controller.tick(now:5000,uptime:5000,admission:&admission,source:{_ in binding})
        interrupted = interrupted || (events[id] ?? []).contains {if case .interrupted=$0 {return true};return false}
        if !interrupted {Thread.sleep(forTimeInterval:0.005)}
    }while !interrupted && ProcessInfo.processInfo.systemUptime<deadline
    guard interrupted else {throw NSError(domain:"TaskCompletion",code:1,userInfo:[NSLocalizedDescriptionKey:"Normal interrupted completion was not delivered"])}
    guard let completed=try journal.jobs().first(where:{$0.id==id}),completed.state == .removed,completed.lease.revoked else {
        throw NSError(domain:"TaskCompletion",code:2,userInfo:[NSLocalizedDescriptionKey:"Interrupted model job remains running after its worker finishes"])
    }
    guard try journal.jobs().first(where:{$0.id==stillRunning})?.state == .running,
          try journal.unresolvedCount()==1,try journal.requestCount(job:id)==1 else {throw JournalError.invalid}
    print("PASS: normal interrupted worker completion closes its local job and lease; nonterminal job remains running")
}
