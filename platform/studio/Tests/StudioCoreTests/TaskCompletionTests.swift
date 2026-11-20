import Foundation
import CSQLite

// A normal cancelled worker-start result is terminal output, even when the
// surrounding owner job has not separately received a cancellation command.
private enum CompletionClock {case ordinary,leaseExpiry,watchdog,uptimeRollback,acknowledgementBlocked,unknownResult}

private func exerciseCompletion(in directory:URL,token:String,clock:CompletionClock = .ordinary)throws -> (String,String) {
    let journal=try Journal(directory:directory),owner=try TaskOwner(token:token,peerUID:geteuid()).hash
    func runningJob(lifetime:Int64=900_000)throws->String {
        let id=UUID().uuidString.lowercased()
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:5000,lifetime:lifetime))
        try journal.transitionJob(id:id,to:.running,now:5000)
        return id
    }
    let id=try runningJob(lifetime:clock == .leaseExpiry || clock == .acknowledgementBlocked ? 1:900_000),stillRunning=try runningJob()
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest("http://127.0.0.1:1/v1"),nativeEpoch:"fixture-native",sequence:1,sampledAt:5000,allClientLifecycleCoverage:true,residentModel:"fixture/model",outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/unused.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    guard try NativeAdmission.permitsDispatch(binding,now:5000) else {throw JournalError.invalid}
    try journal.claim(job:id,attempt:0,model:binding.canonicalModel,scope:binding.inferenceScope())
    let plan=try journal.planWorkerStart(job:id,attempt:0)
    let broker=ModelBroker(journal:journal)
    let held=clock != .ordinary && clock != .unknownResult
    let release=DispatchSemaphore(value:0)
    defer {release.signal()}
    try broker.retainStart(operation:PendingPythonWorker {cancelled in
        if clock == .unknownResult {return .failure(.unavailable)}
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
    let tick:Int64=clock == .watchdog ? 15000:clock == .uptimeRollback ? 4999:pollTime
    if clock == .watchdog {
        _=try controller.tick(now:pollTime,uptime:tick-1,admission:&admission,source:{_ in binding})
        guard broker.active(job:id),try journal.uncertainCount()==0,
              try journal.jobs().first(where:{$0.id==id})?.state == .running else {fatalError("Worker start was cancelled before its watchdog")}
    }
    if held {
        let result=try controller.tick(now:pollTime,uptime:tick,admission:&admission,source:{_ in binding})
        guard result[id]?.isEmpty ?? true,broker.active(job:id),
              try journal.jobs().first(where:{$0.id==id})?.state == .revoking,
              try journal.uncertainCount()==1 else {fatalError("Expired lease or watchdog lost pending worker custody")}
        var heldCapacity=admission
        try heldCapacity.reserveWorker(key:"unrelated",sample:sample,now:pollTime)
        do {
            try heldCapacity.reserveWorker(key:"third",sample:sample,now:pollTime)
            fatalError("Revoked pending worker returned capacity before the result drained")
        } catch AdmissionError.capacity {}
        if clock == .acknowledgementBlocked {
            // Private same-process writer contention only, after the
            // revocation commit and before the no-process acknowledgement.
            var blocker:OpaquePointer?
            let opened=sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path,&blocker,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)
            defer {if let blocker {sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil);sqlite3_close(blocker)}}
            guard opened==SQLITE_OK,sqlite3_exec(blocker,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
            release.signal()
            var attempted=false
            let watchdog=ProcessInfo.processInfo.systemUptime+3
            while !attempted && ProcessInfo.processInfo.systemUptime<watchdog {
                let began=ProcessInfo.processInfo.systemUptime
                let events=try controller.tick(now:pollTime,uptime:tick,admission:&admission,source:{_ in binding})
                attempted=ProcessInfo.processInfo.systemUptime-began>=0.8
                guard events[id]?.isEmpty ?? true else {fatalError("Worker result published before acknowledgement commit")}
                if !attempted {Thread.sleep(forTimeInterval:0.005)}
            }
            guard attempted,broker.active(job:id),try journal.activeLaunchCount()==1,
                  try journal.uncertainCount()==1 else {fatalError("Contended acknowledgement lost pending worker custody")}
            var blockedCapacity=admission
            try blockedCapacity.reserveWorker(key:"unrelated",sample:sample,now:pollTime)
            do {
                try blockedCapacity.reserveWorker(key:"third",sample:sample,now:pollTime)
                fatalError("Contended acknowledgement returned capacity before commit")
            } catch AdmissionError.capacity {}
        } else {release.signal()}
    }
    if clock == .unknownResult {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        var failed=false
        while !failed && ProcessInfo.processInfo.systemUptime<deadline {
            let events=try controller.tick(now:pollTime,uptime:tick,admission:&admission,source:{_ in binding})
            failed=(events[id] ?? []).contains {if case .failed(code:"internal_error")=$0 {return true};return false}
            if !failed {Thread.sleep(forTimeInterval:0.005)}
        }
        let followUp=try controller.tick(now:pollTime+1,uptime:tick+1,admission:&admission,source:{_ in binding})
        guard failed,followUp[id]?.isEmpty ?? true,!broker.active(job:id),broker.hasUnresolvedLaunch,
              try journal.jobs().first(where:{$0.id==id})?.state == .revoking,
              try journal.activeLaunchCount()==1,try journal.uncertainCount()==1,
              try journal.requestCount(job:id)==1,try journal.workerGrants().isEmpty else {
            fatalError("Unknown worker result became proof of absence or replayed output")
        }
        try admission.reserveWorker(key:"unrelated",sample:sample,now:pollTime)
        do {
            try admission.reserveWorker(key:"third",sample:sample,now:pollTime)
            fatalError("Unknown worker result returned capacity")
        } catch AdmissionError.capacity {}
        let routes=try completionRoutes(journal:journal,directory:directory)
        let status=try completionStatus(routes,id:id,token:token)
        guard status["state"] as? String=="revoking",status["unresolved_managed_requests"] as? Int==1,
              status["event"]==nil,status["exit_verified"]==nil else {
            fatalError("Unknown worker result status claimed closure or exposed old output")
        }
        return (id,stillRunning)
    }
    var interrupted=0
    let deadline=ProcessInfo.processInfo.systemUptime+2
    repeat {
        let events=try controller.tick(now:pollTime,uptime:max(pollTime,tick),admission:&admission,source:{_ in binding})
        interrupted += (events[id] ?? []).filter {if case .interrupted=$0 {return true};return false}.count
        if interrupted==0 {Thread.sleep(forTimeInterval:0.005)}
    }while interrupted==0 && ProcessInfo.processInfo.systemUptime<deadline
    guard interrupted==1 else {throw NSError(domain:"TaskCompletion",code:1,userInfo:[NSLocalizedDescriptionKey:"Normal interrupted completion was not delivered"])}
    guard let completed=try journal.jobs().first(where:{$0.id==id}),completed.state == .removed,completed.lease.revoked else {
        throw NSError(domain:"TaskCompletion",code:2,userInfo:[NSLocalizedDescriptionKey:"Interrupted model job remains running after its worker finishes"])
    }
    guard !broker.active(job:id),try journal.activeLaunchCount()==0,try journal.workerGrants().isEmpty else {
        fatalError("Cancelled no-process start left local worker state")
    }
    for offset:Int64 in [1,2] {
        let events=try controller.tick(now:pollTime+offset,uptime:max(pollTime,tick)+offset,admission:&admission,source:{_ in binding})
        guard events[id]?.isEmpty ?? true else {fatalError("Completed worker acknowledgement replayed an owner event")}
    }
    var releasedCapacity=admission
    try releasedCapacity.reserveWorker(key:"model:\(id):0",sample:sample,now:pollTime)
    try releasedCapacity.reserveWorker(key:"unrelated",sample:sample,now:pollTime)
    let routes=try completionRoutes(journal:journal,directory:directory)
    if held {
        let status=try completionStatus(routes,id:id,token:token)
        guard status["state"] as? String=="removed",status["unresolved_managed_requests"] as? Int==1,
              status["event"]==nil,status["exit_verified"]==nil,status["code_complete"]==nil else {
            fatalError("Worker timeout status confused local closure with native completion")
        }
    }
    try routes.tick(now:5000,uptime:5000,artifactResults:[],finished:[SandboxTaskFinished(job:stillRunning,codeComplete:true,exitVerified:true)])
    let observed=try completionStatus(routes,id:stillRunning,token:token)
    guard observed["code_complete"] as? Bool==true,observed["exit_verified"] as? Bool==true else {throw JournalError.invalid}
    guard try journal.jobs().first(where:{$0.id==stillRunning})?.state == .running,
          try journal.unresolvedCount()==1,try journal.requestCount(job:id)==1 else {throw JournalError.invalid}
    return (id,stillRunning)
}

private func verifyDeferredTerminalWrite()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),id=UUID().uuidString.lowercased()
    let controller=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let hash=String(repeating:"a",count:64)
    _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:hash,requestHash:hash,created:1000))
    try journal.transitionJob(id:id,to:.running,now:1000)
    try journal.claim(job:id,attempt:0,model:"fixture/model",requestID:id)
    try journal.markUncertain(job:id,attempt:0)
    var writer:OpaquePointer?
    guard sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path,&writer,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {throw JournalError.storage}
    defer {sqlite3_close(writer)}
    guard sqlite3_exec(writer,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    try controller.settleModelJobs(journal.jobs(),events:[id:[.interrupted]],now:1001)
    guard try journal.jobs().first?.state == .running,try journal.uncertainCount()==1 else {fatalError("Fenced terminal write changed durable state")}
    guard sqlite3_exec(writer,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
    try controller.settleModelJobs(journal.jobs(),events:[:],now:1002)
    guard try journal.jobs().first?.state == .removed,try journal.uncertainCount()==1 else {
        fatalError("Deferred terminal transition required event replay or settled native uncertainty")
    }
}

func runTaskCompletionTests()throws {
    try verifyDeferredTerminalWrite()
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let token=TaskOwner.newToken()
    for (name,clock):(String,CompletionClock) in [("expiry",.leaseExpiry),("watchdog",.watchdog),("rollback",.uptimeRollback),("blocked-ack",.acknowledgementBlocked)] {
        let privateState=directory.appendingPathComponent(name)
        let (job,_)=try exerciseCompletion(in:privateState,token:token,clock:clock)
        let reopened=try Journal(directory:privateState)
        let routes=try completionRoutes(journal:reopened,directory:privateState)
        let status=try completionStatus(routes,id:job,token:token)
        guard status["state"] as? String=="removed",status["unresolved_managed_requests"] as? Int==1,
              status["event"]==nil,try reopened.requestCount(job:job)==1 else {
            fatalError("Reopen dropped worker timeout custody or replayed output")
        }
        var restored=AdmissionPolicy()
        _=try WorkerReconciler(journal:reopened,admission:&restored)
        let sample=ResourceSample(sampledAt:5000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:0,pressure:.normal,thermal:.nominal,cpuSampledAt:5000)
        for key in ["first","second"] {try restored.reserveWorker(key:key,sample:sample,now:5000)}
        guard try reopened.uncertainCount()==1 else {fatalError("Local no-process completion settled native uncertainty on reopen") }
    }
    guard ModelBroker.startWatchdogExpired(uptime:.max,started:.min),
          ModelBroker.startWatchdogExpired(uptime:.min,started:.max),
          ModelBroker.startWatchdogExpired(uptime:0,started:-1),
          !ModelBroker.startWatchdogExpired(uptime:.max,started:Int64.max-9999),
          ModelBroker.startWatchdogExpired(uptime:.max,started:Int64.max-10000) else {
        fatalError("Worker startup watchdog did not fail closed at clock boundaries")
    }
    let unknownState=directory.appendingPathComponent("unknown-result")
    let (unknownID,_)=try exerciseCompletion(in:unknownState,token:token,clock:.unknownResult)
    do {
        let reopened=try Journal(directory:unknownState)
        let routes=try completionRoutes(journal:reopened,directory:unknownState)
        let status=try completionStatus(routes,id:unknownID,token:token)
        guard status["state"] as? String=="reconciling",status["unresolved_managed_requests"] as? Int==1,
              status["event"]==nil,try reopened.activeLaunchCount()==1,try reopened.unresolvedCount(job:unknownID)==1 else {
            fatalError("Reopen discarded unknown launch custody")
        }
        var admission=AdmissionPolicy()
        _=try WorkerReconciler(journal:reopened,admission:&admission)
        let sample=ResourceSample(sampledAt:5000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:0,pressure:.normal,thermal:.nominal,cpuSampledAt:5000)
        try admission.reserveWorker(key:"unrelated",sample:sample,now:5000)
        do {
            try admission.reserveWorker(key:"third",sample:sample,now:5000)
            fatalError("Unknown completion returned worker capacity on reopen")
        } catch AdmissionError.capacity {}
        let foreignOwner=TaskOwner.newToken()
        do {
            _=try completionStatus(routes,id:unknownID,token:foreignOwner)
            fatalError("Foreign owner received unknown completion status")
        } catch TaskCommandError.unauthorized {}
        for _ in 0..<2 {
            let repeated=try completionStatus(routes,id:unknownID,token:token)
            guard repeated["state"] as? String=="reconciling",repeated["unresolved_managed_requests"] as? Int==1,
                  repeated["event"]==nil,repeated["exit_verified"]==nil,repeated["code_complete"]==nil else {
                fatalError("Reading unknown completion replayed output or invented proof")
            }
        }
        guard try reopened.uncertainCount()==1,try reopened.activeLaunchCount()==1,try reopened.requestCount(job:unknownID)==1 else {
            fatalError("Startup recovery or status polling changed independent custody")
        }
    }
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
