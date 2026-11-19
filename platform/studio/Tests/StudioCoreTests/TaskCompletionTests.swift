import Foundation

// A normal cancelled worker-start result is terminal output, even when the
// surrounding owner job has not separately received a cancellation command.
private func exerciseCompletion(in directory:URL,token:String,expireDuringStart:Bool=false,expireStartWatchdog:Bool=false)throws -> (String,String) {
    let journal=try Journal(directory:directory),owner=try TaskOwner(token:token,peerUID:geteuid()).hash
    func runningJob(lifetime:Int64=900_000)throws->String {
        let id=UUID().uuidString.lowercased()
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:5000,lifetime:lifetime))
        try journal.transitionJob(id:id,to:.running,now:5000)
        return id
    }
    let id=try runningJob(lifetime:expireDuringStart ? 1:900_000),stillRunning=try runningJob()
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest("http://127.0.0.1:1/v1"),nativeEpoch:"fixture-native",sequence:1,sampledAt:5000,allClientLifecycleCoverage:true,residentModel:"fixture/model",outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/unused.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    guard try NativeAdmission.permitsDispatch(binding,now:5000) else {throw JournalError.invalid}
    try journal.claim(job:id,attempt:0,model:binding.canonicalModel,scope:binding.inferenceScope())
    let plan=try journal.planWorkerStart(job:id,attempt:0)
    let broker=ModelBroker(journal:journal)
    let held=expireDuringStart || expireStartWatchdog
    let release=DispatchSemaphore(value:0)
    defer {release.signal()}
    try broker.retainStart(operation:PendingPythonWorker {cancelled in
        if held {
            guard release.wait(timeout:.now()+3) == .success,cancelled() else {return .failure(.unavailable)}
        }
        return .failure(.cancelled)
    },plan:plan,binding:binding,packet:Data(),started:5000)
    let controller=TaskController(journal:journal,broker:broker)
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:5000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:5000)
    try admission.reserveWorker(key:"model:\(id):0",sample:sample,now:5000)
    let pollTime:Int64=held ? 5001:5000
    let tick:Int64=expireStartWatchdog ? 15000:pollTime
    if expireStartWatchdog {
        _=try controller.tick(now:pollTime,uptime:tick-1,admission:&admission,source:{_ in binding})
        guard broker.active(job:id),try journal.uncertainCount()==0,
              try journal.jobs().first(where:{$0.id==id})?.state == .running else {fatalError("Worker start was cancelled before its watchdog")}
    }
    if held {
        let result=try controller.tick(now:pollTime,uptime:tick,admission:&admission,source:{_ in binding})
        guard result[id]?.isEmpty ?? true,broker.active(job:id),
              try journal.jobs().first(where:{$0.id==id})?.state == .revoking,
              try journal.uncertainCount()==1 else {fatalError("Expired lease or watchdog lost pending worker custody")}
        release.signal()
    }
    var interrupted=false
    let deadline=ProcessInfo.processInfo.systemUptime+2
    repeat {
        let events=try controller.tick(now:pollTime,uptime:tick,admission:&admission,source:{_ in binding})
        interrupted = interrupted || (events[id] ?? []).contains {if case .interrupted=$0 {return true};return false}
        if !interrupted {Thread.sleep(forTimeInterval:0.005)}
    }while !interrupted && ProcessInfo.processInfo.systemUptime<deadline
    guard interrupted else {throw NSError(domain:"TaskCompletion",code:1,userInfo:[NSLocalizedDescriptionKey:"Normal interrupted completion was not delivered"])}
    guard let completed=try journal.jobs().first(where:{$0.id==id}),completed.state == .removed,completed.lease.revoked else {
        throw NSError(domain:"TaskCompletion",code:2,userInfo:[NSLocalizedDescriptionKey:"Interrupted model job remains running after its worker finishes"])
    }
    guard !broker.active(job:id),try journal.activeLaunchCount()==0,try journal.workerGrants().isEmpty else {
        fatalError("Cancelled no-process start left local worker state")
    }
    let routes=try completionRoutes(journal:journal,directory:directory)
    try routes.tick(now:5000,uptime:5000,artifactResults:[],finished:[SandboxTaskFinished(job:stillRunning,codeComplete:true,exitVerified:true)])
    let observed=try completionStatus(routes,id:stillRunning,token:token)
    guard observed["code_complete"] as? Bool==true,observed["exit_verified"] as? Bool==true else {throw JournalError.invalid}
    guard try journal.jobs().first(where:{$0.id==stillRunning})?.state == .running,
          try journal.unresolvedCount()==1,try journal.requestCount(job:id)==1 else {throw JournalError.invalid}
    return (id,stillRunning)
}

func runTaskCompletionTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let token=TaskOwner.newToken()
    _=try exerciseCompletion(in:directory.appendingPathComponent("expiry"),token:token,expireDuringStart:true)
    _=try exerciseCompletion(in:directory.appendingPathComponent("watchdog"),token:token,expireStartWatchdog:true)
    let (id,stillRunning)=try exerciseCompletion(in:directory,token:token)
    let reopened=try Journal(directory:directory)
    let otherToken=TaskOwner.newToken(),otherID=UUID().uuidString.lowercased()
    let otherOwner=try TaskOwner(token:otherToken,peerUID:geteuid()).hash
    _=try reopened.reserveJob(DurableJob(id:otherID,idempotency:UUID().uuidString.lowercased(),ownerHash:otherOwner,requestHash:String(repeating:"c",count:64),created:5000))
    try reopened.transitionJob(id:otherID,to:.revoking,now:5000)
    try reopened.transitionJob(id:otherID,to:.removed,now:5000)
    try reopened.expireTerminalJobs(now:86_404_999)
    guard try reopened.jobs().contains(where:{$0.id==otherID}) else {throw JournalError.invalid}
    try reopened.expireTerminalJobs(now:86_405_000)
    let jobs=try reopened.jobs()
    guard let completed=jobs.first(where:{$0.id==id}),completed.state == .removed,completed.lease.revoked,
          let recovered=jobs.first(where:{$0.id==stillRunning}),recovered.state == .reconciling,recovered.lease.revoked,
          try reopened.unresolvedCount()==1,try reopened.requestCount(job:id)==1 else {throw JournalError.invalid}
    print("PASS: normal interrupted worker completion closes its local job and lease; nonterminal job remains running")
    let commands=try completionRoutes(journal:reopened,directory:directory)
    guard !jobs.contains(where:{$0.id==otherID}) else {throw JournalError.invalid}
    do {
        _=try completionStatus(commands,id:otherID,token:otherToken)
        throw JournalError.invalid
    } catch TaskCommandError.unauthorized {}
    for (job,expected,unresolved) in [(id,"removed",1),(stillRunning,"reconciling",0)] {
        do {
            _=try completionStatus(commands,id:job,token:otherToken)
            throw JournalError.invalid
        } catch TaskCommandError.unauthorized {}
        let state=try completionStatus(commands,id:job,token:token)
        guard state["state"] as? String==expected,state["unresolved_managed_requests"] as? Int==unresolved,
              state["event"]==nil,state["code_complete"]==nil,state["exit_verified"]==nil else {throw JournalError.invalid}
    }
    print("PASS: restart preserves local completion and native uncertainty without replaying output or runner proof")
}

private func completionRoutes(journal:Journal,directory:URL)throws->TaskCommands {
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("artifacts")))
    let sandbox=SandboxTaskController(journal:journal,jobs:JobController(journal:journal,executor:UnavailableSandboxRuntime()),tasks:tasks,artifacts:artifacts,socket:"/fixture/unused.sock",peerUID:geteuid())
    return TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[],peerUID:geteuid())
}

private func completionStatus(_ commands:TaskCommands,id:String,token:String)throws->[String:Any] {
    let status=try ControlRequest.decode(JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":"job.status","payload":["owner":token,"job":id]]))
    let sample=ResourceSample(sampledAt:5500,physical:0,available:nil,vmAvailable:nil,diskFree:nil,cpu:nil,pressure:.unknown,thermal:.unknown)
    var admission=AdmissionPolicy()
    return try commands.handle(status,role:.task,sample:sample,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:5500,uptime:5500)
}
