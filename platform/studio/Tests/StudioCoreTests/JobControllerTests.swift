import Foundation
import CSQLite

private class FakeSandboxExecutor:SandboxExecuting {
    var values:[SandboxExecution]=[]
    var commands:[SandboxCommand]=[]
    var present:[String:(SandboxConfiguration,String,Bool)]=[:]
    var active:Int { 0 }
    var reportExitCodes=false
    var holdResponses=false
    var denyStartCapacity=false
    var denyCreateCapacity=false
    var loseCreateReply=false
    var acknowledgeInspection=false
    var storageContinuityUnknown=false
    var resourceNow:Int64=0
    var resourceFailure=false
    var resourceRequests:[Int64]=[]
    var resourceValues:[VMReadResult]=[]
    var holdResourceResults=false
    var resourceLeases:[Int64]=[]
    func submitResources(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws {
        resourceLeases.append(leaseUntil)
        resourceRequests.append(resourceNow)
        let envelope=VMResourceObservation(runtimeHash:String(repeating:"a",count:64),sampledAt:resourceNow,configuredCap:12<<30,total:16<<30,free:8<<30,allVMConsumersCovered:true)
        let sample=VMKernelSample(sampledAt:resourceNow,total:16<<30,free:8<<30,bootHash:String(repeating:"b",count:64),envelope:envelope)
        resourceValues.append(VMReadResult(job:configuration.job,runtimeID:id,result:resourceFailure ? .failure(.unavailable) : .success(sample)))
    }
    func drainResources()->[VMReadResult] {
        guard !holdResourceResults else {return []}
        let values=resourceValues;resourceValues=[];return values
    }
    func submit(job:String,command:SandboxCommand) throws {
        if denyStartCapacity,case .start=command {throw AdmissionError.capacity}
        if denyCreateCapacity,case .create=command {throw AdmissionError.capacity}
        commands.append(command)
        let result:SandboxExecutionValue
        switch command {
        case .create(let config):
            if loseCreateReply {
                values.append(SandboxExecution(job:job,result:.failure(.unavailable)))
                return
            }
            let id=String(repeating:job.first=="a" ? "a" : "b",count:64)
            present[job]=(config,id,false);result = .created(id)
        case .inspect:
            if storageContinuityUnknown {
                values.append(SandboxExecution(job:job,result:.failure(.storageContinuityUnknown)))
                return
            }
            if acknowledgeInspection {
                result = .acknowledged
                break
            }
            if let (config,id,running)=present[job] { result = .observed(.present(id:id,name:"/"+config.name,image:config.image,nonce:config.nonce,running:running),exitCode:reportExitCodes ? 0:nil) }
            else { result = .observed(.absent) }
        case .start:
            if let (config,id,_)=present[job] { present[job]=(config,id,true) };result = .acknowledged
        case .stop:
            if let (config,id,_)=present[job] { present[job]=(config,id,false) };result = .acknowledged
        case .remove:present.removeValue(forKey:job);result = .acknowledged
        }
        values.append(SandboxExecution(job:job,result:.success(result)))
    }
    func drain()->[SandboxExecution] { if holdResponses {return []};let result=values;values=[];return result }
}

private final class SlotFakeSandboxExecutor:FakeSandboxExecutor,SandboxCreateSlotExecuting {
    var commits=0
    func submitCreate(configuration:SandboxConfiguration,beforePublish:()throws->Void)throws {
        guard !denyCreateCapacity else {throw AdmissionError.capacity}
        try beforePublish()
        commits += 1
        try submit(job:configuration.job,command:.create(configuration))
    }
}

func runJobControllerTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    let controller=JobController(journal:journal,executor:runtime)
    var admission=AdmissionPolicy()
    func sample(_ now:Int64,cpu:Double=10)->ResourceSample { ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:cpu,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now) }
    let ids=[UUID().uuidString.lowercased(),UUID().uuidString.lowercased()]
    for (index,id) in ids.enumerated() {
        let stamp:Int64=10000+Int64(index)
        let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:stamp)
        let config=try SandboxConfiguration(job:id,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
        try admission.reserve(job:id,memory:config.memory,cpus:1,sample:sample(stamp),now:stamp)
        _=try journal.reserveSandbox(job:job,configuration:config)
    }
    try controller.tick(now:10900,sample:sample(10900),admission:&admission,inputReady:{_ in false},transportReady:{_ in false},cancelModel:{_ in})
    guard runtime.commands.isEmpty,try journal.sandboxRecords().allSatisfy({!$0.createIssued}) else {
        fatalError("Sandbox create issued before input registration")
    }
    runtime.denyCreateCapacity=true
    try controller.tick(now:10925,sample:sample(10925),admission:&admission,transportReady:{_ in false},cancelModel:{_ in})
    guard runtime.commands.isEmpty,try journal.sandboxRecords().allSatisfy({$0.createIssued}) else {
        fatalError("Fixture did not defer precommitted create on executor capacity")
    }
    runtime.denyCreateCapacity=false
    try controller.tick(now:10950,sample:sample(10950),admission:&admission,inputReady:{_ in false},transportReady:{_ in false},cancelModel:{_ in})
    guard runtime.commands.isEmpty else {fatalError("Deferred sandbox create bypassed input readiness")}
    try controller.tick(now:11000,sample:sample(11000),admission:&admission,transportReady:{_ in false},cancelModel:{_ in})
    guard runtime.values.count==2 else {fatalError("Expected two already-drained create results in fixture")}
    runtime.values.insert(SandboxExecution(job:UUID().uuidString.lowercased(),result:.success(.acknowledged)),at:0)
    do {
        try controller.tick(now:11000,sample:sample(11000),admission:&admission,transportReady:{_ in false},cancelModel:{_ in})
        fatalError("Unexpected sandbox completion did not fail the tick")
    } catch JournalError.conflict {}
    guard try journal.sandboxRecords().allSatisfy({$0.runtimeID != nil && !$0.startIssued}) else {
        fatalError("Malformed sandbox completion stranded trailing create results")
    }
    for tick in 0..<5 {
        try controller.tick(now:11000+Int64(tick*100),sample:sample(11000+Int64(tick*100)),admission:&admission,transportReady:{_ in false},cancelModel:{_ in})
    }
    guard runtime.commands.allSatisfy({if case .start=$0 {return false};return true}) else { fatalError("Container started before trusted transport readiness") }
    runtime.denyStartCapacity=true
    for now:Int64 in [13000,13500,14000] {
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard try journal.sandboxRecords().allSatisfy({$0.startIssued}) else {fatalError("Fixture did not defer both precommitted starts")}
    runtime.denyStartCapacity=false
    try controller.tick(now:14500,sample:sample(14500),admission:&admission,transportReady:{_ in false},cancelModel:{_ in})
    guard runtime.commands.allSatisfy({if case .start=$0 {return false};return true}) else {fatalError("Deferred sandbox start bypassed transport readiness")}
    for now:Int64 in [15000,15500,16000,16500,17000] {
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard try journal.jobs().allSatisfy({$0.state == .running}) else { fatalError("Sandbox coordinator did not reach running") }
    var cancelled:[String]=[]
    try controller.tick(now:19000,sample:sample(19000,cpu:90),admission:&admission,transportReady:{_ in true},cancelModel:{cancelled.append($0)})
    guard cancelled==[ids[1]],try journal.jobs().first(where:{$0.id==ids[0]})?.state == .running else { fatalError("Pressure did not select durable newest-owned job only") }
    for tick in 0..<24 {
        try controller.tick(now:19100+Int64(tick*500),sample:sample(19100+Int64(tick*500)),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard try journal.jobs().first(where:{$0.id==ids[1]})?.state == .removed else { fatalError("Owned sandbox cleanup did not finish") }
    try checkModelSandboxSourceTurnover()
    try checkDeferredCreateRestart()
    try checkReservedCreateSlot()
    print("PASS: asynchronous sandbox coordinator, transport-before-start fencing, newest-owned pressure revocation and proof-gated cleanup")
}

private func checkReservedCreateSlot()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),runtime=SlotFakeSandboxExecutor()
    let controller=JobController(journal:journal,executor:runtime)
    let id=UUID().uuidString.lowercased(),hash=String(repeating:"a",count:64)
    let config=try SandboxConfiguration(job:id,nonce:hash,image:"sha256:"+hash,memory:512<<20,cpus:1)
    _=try journal.reserveSandbox(job:DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:hash,requestHash:hash,created:10000),configuration:config)
    var admission=AdmissionPolicy()
    func tick(_ now:Int64,ready:Bool)throws {
        let sample=ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now)
        try controller.tick(now:now,sample:sample,admission:&admission,inputReady:{_ in ready},transportReady:{_ in false},cancelModel:{_ in})
    }
    let disabled=UnavailableSandboxRuntime()
    do {
        try disabled.submitCreate(configuration:config,beforePublish:{fatalError("Disabled runtime ran create commit")})
        fatalError("Disabled runtime reserved a create slot")
    } catch AdmissionError.capacity {}
    guard disabled.drain().isEmpty else {fatalError("Disabled runtime queued create work")}
    runtime.denyCreateCapacity=true
    try tick(10000,ready:true)
    guard try journal.jobs()[0].state == .reserved,try !journal.sandboxRecords()[0].createIssued,
          runtime.commands.isEmpty,runtime.commits==0 else {fatalError("Capacity refusal wrote a create intent")}
    runtime.denyCreateCapacity=false
    try tick(10500,ready:false)
    guard runtime.commands.isEmpty,runtime.commits==0 else {fatalError("Slot-backed create bypassed input readiness")}
    do {
        var blocker:OpaquePointer?
        guard sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path,&blocker,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {throw JournalError.storage}
        defer {sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil);sqlite3_close(blocker)}
        guard sqlite3_exec(blocker,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        do {
            try tick(10750,ready:true)
            fatalError("Create escaped while its journal intent was blocked")
        } catch JournalError.storage {}
        guard try journal.jobs()[0].state == .reserved,try !journal.sandboxRecords()[0].createIssued,
              runtime.commands.isEmpty,runtime.commits==0 else {fatalError("Create commit failure changed intent or submitted work")}
    }
    try tick(11000,ready:true)
    guard try journal.jobs()[0].state == .creating,try journal.sandboxRecords()[0].createIssued,
          runtime.commits==1,runtime.commands.count==1,case .create=runtime.commands[0] else {fatalError("Slot-backed create did not commit before dispatch")}
}

private func checkDeferredCreateRestart()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let id=UUID().uuidString.lowercased(),hash=String(repeating:"a",count:64)
    func sample(_ now:Int64)->ResourceSample {
        ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now)
    }
    do {
        let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
        runtime.denyCreateCapacity=true
        let controller=JobController(journal:journal,executor:runtime)
        let config=try SandboxConfiguration(job:id,nonce:hash,image:"sha256:"+hash,memory:512<<20,cpus:1)
        let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:hash,requestHash:hash,created:10000)
        _=try journal.reserveSandbox(job:job,configuration:config)
        var admission=AdmissionPolicy()
        try controller.tick(now:10000,sample:sample(10000),admission:&admission,transportReady:{_ in false},cancelModel:{_ in})
        guard try journal.sandboxRecords()[0].createIssued,runtime.commands.isEmpty else {fatalError("Create was not durably precommitted and capacity-deferred")}
    }
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    let controller=JobController(journal:journal,executor:runtime)
    var admission=AdmissionPolicy()
    for now:Int64 in [11000,11500,13000,13500] {
        try controller.tick(now:now,sample:sample(now),admission:&admission,inputReady:{_ in false},transportReady:{_ in false},cancelModel:{_ in})
    }
    let retained=try journal.sandboxRecords()[0]
    guard !runtime.commands.isEmpty,runtime.commands.allSatisfy({if case .inspect=$0 {return true};return false}),
          retained.createIssued,retained.runtimeID==nil,!retained.removalProven,
          controller.cleanupStatus(now:13500)["pending_sandboxes"] as? Int==1 else {
        fatalError("Restart replayed precommitted create or inferred absence after losing local refusal history")
    }
    var recoveredCapacity=admission
    try recoveredCapacity.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:sample(13500),now:13500)
    do {
        try recoveredCapacity.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:sample(13500),now:13500)
        fatalError("Reopen did not charge capacity for unresolved create custody")
    } catch AdmissionError.capacity {}
    let unissuedDirectory=directory.appendingPathComponent("disabled-reopen"),unissued=UUID().uuidString.lowercased()
    do {
        let seed=try Journal(directory:unissuedDirectory)
        let configuration=try SandboxConfiguration(job:unissued,nonce:hash,image:"sha256:"+hash,memory:512<<20,cpus:1)
        _=try seed.reserveSandbox(job:DurableJob(id:unissued,idempotency:UUID().uuidString.lowercased(),ownerHash:hash,requestHash:hash,created:10000),configuration:configuration)
    }
    let recovered=try Journal(directory:unissuedDirectory),disabled=UnavailableSandboxRuntime()
    let disabledController=JobController(journal:recovered,executor:disabled)
    var disabledAdmission=AdmissionPolicy()
    for now:Int64 in [11000,11500] {
        try disabledController.tick(now:now,sample:sample(now),admission:&disabledAdmission,inputReady:{_ in false},transportReady:{_ in false},cancelModel:{_ in})
    }
    let neverIssued=try recovered.sandboxRecords()[0]
    guard try recovered.jobs()[0].state == .removed,!neverIssued.createIssued,neverIssued.removalProven,
          neverIssued.runtimeID==nil,disabled.drain().isEmpty else {fatalError("Disabled-runtime restart queried daemon for never-issued create")}
    try disabledAdmission.reserve(job:unissued,memory:neverIssued.configuration.memory,cpus:1,sample:sample(11500),now:11500)
}

private func checkModelSandboxSourceTurnover() throws {
    for (createBeforeTurnover,regress) in [(false,false),(true,false),(true,true)] {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
        let jobs=JobController(journal:journal,executor:runtime)
        let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
        let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("artifacts")))
        let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,socket:"/fixture/never.sock",peerUID:geteuid())
        let id=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64),epoch=UUID().uuidString.lowercased()
        let base="http://127.0.0.1:11234/v1"
        func binding(_ nativeEpoch:String,now:Int64,sequence:UInt64=1)->WorkerDispatchBinding {
            let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:nativeEpoch,sequence:sequence,sampledAt:now,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
            return WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/never.sock",host:"fixture-host",profileHash:owner,managerEpoch:epoch,canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
        }
        let config=try SandboxConfiguration(job:id,nonce:owner,image:"sha256:"+owner,memory:512<<20,cpus:1)
        let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:owner,created:10000)
        _=try journal.reserveSandbox(job:job,configuration:config)
        try sandbox.register(id:id,owner:owner,source:Data(),inputSHA256:"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",binding:binding("original",now:10000),now:10000)
        var admission=AdmissionPolicy()
        func tick(_ now:Int64,_ nativeEpoch:String,sequence:UInt64=1)throws {
            let sample=ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now)
            _=try sandbox.tick(now:now,uptime:Double(now)/1000,sample:sample,admission:&admission,source:{_ in binding(nativeEpoch,now:now,sequence:sequence)},nativeCapacityProven:false)
        }
        if createBeforeTurnover {
            try tick(10000,"original",sequence:regress ? 3:1)
            guard runtime.commands.count==1,case .create=runtime.commands[0] else {fatalError("Fixture did not issue create before turnover")}
        }
        try tick(10500,regress ? "original":"replacement",sequence:regress ? 2:1)
        if createBeforeTurnover {
            guard try journal.jobs()[0].state == .revoking else {fatalError("Pending sandbox accepted a regressed source before attach")}
        }
        for now:Int64 in [11000,11500,13000,13500,14000] {
            try tick(now,regress ? "original":"replacement",sequence:regress ? 2:1)
        }
        let record=try journal.sandboxRecords()[0],terminal=try journal.jobs()[0]
        guard terminal.state == .removed,record.createIssued==createBeforeTurnover,record.removalProven,
              !runtime.commands.contains(where:{if case .start=$0 {return true};return false}),
              try journal.requestCount(job:id)==0 else {fatalError("Model sandbox turnover crossed create/start or inference custody")}
        if !createBeforeTurnover, !runtime.commands.isEmpty {fatalError("Source turnover before create dispatched an effect")}
    }
}

func runVMProbePermissionTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    let jobs=JobController(journal:journal,executor:runtime,collectVM:true)
    let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("artifacts")))
    let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:TaskController(journal:journal,broker:ModelBroker(journal:journal)),artifacts:artifacts,socket:"/var/empty/unenrolled-probe.sock",peerUID:geteuid())
    let coordinator=VMProbeCoordinator(journal:journal,jobs:jobs,sandbox:sandbox)
    let permission=try VMProbePermission(reviewedImage:"sha256:"+String(repeating:"b",count:64),reviewDigest:String(repeating:"c",count:64),managerEpoch:UUID().uuidString.lowercased(),issued:10000)
    var admission=AdmissionPolicy()
    func sample(_ now:Int64)->ResourceSample {ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:now)}
    func refuse(_ body:()throws->Void) {do {try body();fatalError("Unreviewed/reused probe authority accepted")}catch {}}
    refuse {try admission.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:sample(10000),now:10000)}
    let clockPermission=try VMProbePermission(reviewedImage:permission.image,reviewDigest:String(repeating:"c",count:64),managerEpoch:UUID().uuidString.lowercased(),issued:10000)
    try clockPermission.validate(now:11000)
    refuse {try clockPermission.validate(now:10500)}
    refuse {try clockPermission.validate(now:12000)}
    let foreign=try SandboxConfiguration(job:permission.id,nonce:permission.nonce,image:"sha256:"+String(repeating:"f",count:64),memory:512<<20,cpus:1)
    refuse {try admission.reserveVMProbe(foreign,permission:permission,sample:sample(10000),now:10000)}
    let id=try coordinator.begin(permission:permission,sample:sample(10000),admission:&admission,now:10000)
    refuse {_=try coordinator.begin(permission:permission,sample:sample(10000),admission:&admission,now:10000)}
    guard permission.job==id,try journal.jobs().count==1,try journal.unresolvedCount()==0 else {throw JournalError.storage}
    let spoof=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"f",count:64),requestHash:VMProbePermission.sourceHash,created:10000,lifetime:30000)
    refuse {try permission.authorize(journal.sandboxRecords()[0].configuration,job:spoof,now:10000)}
    for tick in 0..<14 {
        let now:Int64=10000+Int64(tick)*500;runtime.resourceNow=now
        try jobs.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard try journal.jobs()[0].state == .running,jobs.vmAvailable(now:16500)==4<<30 else {fatalError("Reviewed finite probe could not collect while ordinary VM admission remained unknown")}
    refuse {try permission.validate(now:40000)}
    // New controller generation does not inherit/mint the in-memory exception.
    runtime.values=[];runtime.resourceValues=[]
    let recovered=JobController(journal:journal,executor:runtime,collectVM:true)
    try recovered.tick(now:18000,sample:sample(18000),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    guard try journal.jobs()[0].state == .revoking else {fatalError("Restart replayed finite bootstrap authority")}
    print("PASS: trusted one-use image/owner/boot/UID/30s finite VM bootstrap authority is separate from task admission, expires/rejects reuse and is not replayed after controller recovery (fake runtime only)")
}

func runGlobalHostPressureTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    let controller=JobController(journal:journal,executor:runtime)
    var admission=AdmissionPolicy(),cancelled:[String]=[]
    func sample(_ now:Int64,cpu:Double=10,vm:UInt64?=8<<30)->ResourceSample {
        ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:vm,diskFree:100<<30,cpu:cpu,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now)
    }
    let sandbox=UUID().uuidString.lowercased()
    let job=try DurableJob(id:sandbox,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:10000)
    let config=try SandboxConfiguration(job:sandbox,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
    try admission.reserve(job:sandbox,memory:config.memory,cpus:1,sample:sample(10000),now:10000)
    _=try journal.reserveSandbox(job:job,configuration:config)
    for tick in 0..<14 {
        let now:Int64=10000+Int64(tick)*500
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{cancelled.append($0)})
    }
    guard try journal.jobs().first(where:{$0.id==sandbox})?.state == .running else {fatalError("Pressure fixture sandbox did not start")}
    var models:[String]=[]
    for index in 0..<2 {
        let id=UUID().uuidString.lowercased();models.append(id)
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:job.ownerHash,requestHash:job.requestHash,created:20000+Int64(index)))
        try journal.transitionJob(id:id,to:.running)
    }
    try journal.claim(job:models[1],attempt:0,model:"fixture-model")
    try journal.markUncertain(job:models[1],attempt:0)
    try controller.tick(now:23000,sample:sample(23000,cpu:90),admission:&admission,transportReady:{_ in true},cancelModel:{cancelled.append($0)})
    guard cancelled==[models[1]],try journal.jobs().first(where:{$0.id==sandbox})?.state == .running else {fatalError("Host pressure skipped newer model-only job for older sandbox")}
    try controller.tick(now:23500,sample:sample(23500,cpu:90),admission:&admission,transportReady:{_ in true},cancelModel:{cancelled.append($0)})
    guard cancelled==[models[1]] else {fatalError("Host pressure ignored the2s revocation cadence")}
    try controller.tick(now:25000,sample:sample(25000,cpu:90),admission:&admission,transportReady:{_ in true},cancelModel:{cancelled.append($0)})
    guard cancelled==[models[1],models[0]],try journal.jobs().first(where:{$0.id==sandbox})?.state == .running else {fatalError("Global newest-first model-only ordering changed")}
    try controller.tick(now:27000,sample:sample(27000,vm:nil),admission:&admission,transportReady:{_ in true},cancelModel:{cancelled.append($0)})
    guard cancelled==[models[1],models[0],sandbox],try journal.unresolvedCount()==1 else {fatalError("VM loss crossed model scope or pressure cleared native uncertainty")}
    print("PASS: host pressure revokes globally newest model-only/sandbox jobs at2s cadence; VM-only loss stays scoped and native uncertainty survives")
}

func runModelOnlyVMIsolationTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),controller=JobController(journal:journal,executor:FakeSandboxExecutor())
    let id=UUID().uuidString.lowercased(),job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:10000)
    _=try journal.reserveJob(job)
    var admission=AdmissionPolicy(),cancelled:[String]=[]
    let sample=ResourceSample(sampledAt:11000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:11000)
    try controller.tick(now:11000,sample:sample,admission:&admission,transportReady:{_ in false},cancelModel:{cancelled.append($0)})
    guard cancelled.isEmpty,try journal.jobs().first(where:{$0.id==id})?.state == .reserved else {fatalError("Missing VM telemetry revoked unrelated native-only job")}
    print("PASS: sandbox VM uncertainty cannot revoke unrelated native model-only jobs; subsystem ownership remains separate")
}

func runVMControllerTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    let controller=JobController(journal:journal,executor:runtime,collectVM:true)
    var admission=AdmissionPolicy()
    func sample(_ now:Int64)->ResourceSample {ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now)}
    let id=UUID().uuidString.lowercased(),job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:10000)
    let config=try SandboxConfiguration(job:id,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
    try admission.reserve(job:id,memory:config.memory,cpus:1,sample:sample(10000),now:10000)
    _=try journal.reserveSandbox(job:job,configuration:config)
    for tick in 0..<14 {
        let now:Int64=10000+Int64(tick)*500;runtime.resourceNow=now
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard !runtime.resourceLeases.isEmpty,runtime.resourceLeases.allSatisfy({$0==job.lease.expires}),
          !runtime.resourceRequests.isEmpty,controller.vmAvailable(now:16500)==4<<30,controller.vmEpoch(now:16500)?.count==64,
          controller.vmAvailable(now:16499)==nil,controller.vmSampledAt(now:16499)==nil,controller.vmEpoch(now:16499)==nil,
          controller.applyingVM(to:sample(16499),now:16499).vmAvailable==nil,
          controller.vmAvailable(now:30000)==nil else {fatalError("VM controller failed fresh/stale/rewound capacity publication")}
    let smaller=ResourceSample(sampledAt:16500,physical:8<<30,available:6<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:16500)
    let overlay=controller.applyingVM(to:smaller,now:16500)
    let frame=try ResourceObservationExport.encode(sample:overlay,gpu:nil,gpuSampledAt:nil,now:16500,epoch:UUID().uuidString.lowercased(),sequence:1,vmEpoch:controller.vmEpoch(now:16500))
    guard overlay.vmAvailable==nil,overlay.vmSampledAt==nil,frame.observation["vm_epoch"] is NSNull,
          frame.observation["vm_coverage"] as? String == "unknown" else {fatalError("VM envelope incompatible with current host crossed the telemetry boundary")}
    for pair in zip(runtime.resourceRequests,runtime.resourceRequests.dropFirst()) {guard pair.1-pair.0>=2000 else {fatalError("Unbounded VM polling")}}
    runtime.resourceFailure=true
    for tick in 0..<8 {
        let now:Int64=17000+Int64(tick)*500;runtime.resourceNow=now
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard controller.vmAvailable(now:20500)==nil,controller.vmEpoch(now:20500)==nil else {fatalError("Failed source retained verified VM capacity")}
    runtime.resourceFailure=false
    for now:Int64 in [21000,21500,22000,22500,23000] {
        runtime.resourceNow=now
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard controller.vmAvailable(now:23000)==4<<30 else {fatalError("Expected fresh VM capacity before revocation")}
    runtime.holdResourceResults=true
    var revocationAt:Int64=23001
    for now:Int64 in [23500,24000,24500,25000] where runtime.resourceValues.isEmpty {
        runtime.resourceNow=now
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
        revocationAt=now+1
    }
    guard runtime.resourceValues.count==1 else {fatalError("No in-flight VM fixture result before revocation")}
    try journal.transitionJob(id:id,to:.revoking,now:revocationAt)
    try controller.tick(now:revocationAt,sample:sample(revocationAt),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    guard controller.vmAvailable(now:revocationAt)==nil else {fatalError("VM cache survived original target revocation")}
    runtime.holdResourceResults=false
    try controller.tick(now:revocationAt+1,sample:sample(revocationAt+1),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    guard runtime.resourceValues.isEmpty,controller.vmAvailable(now:revocationAt+1)==nil else {fatalError("Late VM result revived revoked capacity")}
    let replacement=UUID().uuidString.lowercased(),created=revocationAt+2
    let replacementJob=try DurableJob(id:replacement,idempotency:UUID().uuidString.lowercased(),ownerHash:job.ownerHash,requestHash:job.requestHash,created:created)
    let replacementConfig=try SandboxConfiguration(job:replacement,nonce:config.nonce,image:config.image,memory:config.memory,cpus:config.cpus)
    let replacementID=String(repeating:"e",count:64)
    _=try journal.reserveSandbox(job:replacementJob,configuration:replacementConfig)
    try journal.commitSandboxCreate(replacementConfig,now:created)
    try journal.saveSandbox(SandboxRecord(configuration:replacementConfig,runtimeID:replacementID,createIssued:true,startIssued:true))
    try journal.transitionJob(id:replacement,to:.running,now:created)
    runtime.present[replacement]=(replacementConfig,replacementID,true)
    for now in [created+2000,created+2001] {
        runtime.resourceNow=now
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard runtime.resourceLeases.last==replacementJob.lease.expires,
          controller.vmSampledAt(now:created+2001)==created+2000 else {fatalError("Replacement target did not supply its own fresh VM observation")}
    print("PASS: serialized VM coordinator polls owned running targets at2s, publishes only fresh envelopes and immediately invalidates failed/stale resource authority (fake runtime telemetry)")
}

func runSandboxExitProofTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    runtime.reportExitCodes=true
    let controller=JobController(journal:journal,executor:runtime)
    var admission=AdmissionPolicy()
    func sample(_ now:Int64)->ResourceSample {ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now)}
    let id=UUID().uuidString.lowercased()
    let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:10000)
    let config=try SandboxConfiguration(job:id,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
    try admission.reserve(job:id,memory:config.memory,cpus:1,sample:sample(10000),now:10000)
    _=try journal.reserveSandbox(job:job,configuration:config)
    func tick(_ now:Int64)throws {try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})}
    for index in 0..<14 {
        try tick(10000+Int64(index)*500)
        if try journal.jobs().first(where:{$0.id==id})?.state == .creating,
           try journal.sandboxRecords().first(where:{$0.configuration.job==id})?.startIssued == true,
           controller.exitProof[id] != nil {fatalError("FIO_SANDBOX_CREATED_STATE_BECAME_EXIT_PROOF")}
    }
    guard try journal.jobs().first(where:{$0.id==id})?.state == .running,controller.exitProof[id]==nil,
          let (_,runtimeID,_)=runtime.present[id] else {fatalError("Running sandbox retained birth exit status")}
    runtime.present[id]=(config,runtimeID,false)
    try tick(19000);try tick(20000)
    guard controller.exitProof[id]==true else {fatalError("Verified post-start mock exit status was lost")}
    runtime.present[id]=(config,runtimeID,true)
    try tick(21000);try tick(21001)
    guard controller.exitProof[id]==nil else {fatalError("FIO_SANDBOX_RUNNING_RESTART_REUSED_PRIOR_EXIT_PROOF")}
    guard try journal.sandboxRecords().first(where:{$0.configuration.job==id})?.removalProven == false else {fatalError("Restart observation released sandbox reservation")}
    print("PASS: synthetic created/running snapshots cannot certify exit; observed restart clears old local exit proof without releasing cleanup custody")
}

func runCleanupStatusRecoveryTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    let controller=JobController(journal:journal,executor:runtime)
    var admission=AdmissionPolicy()
    func sample(_ now:Int64)->ResourceSample {
        ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,
            diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:now,cpuSampledAt:now)
    }
    let id=UUID().uuidString.lowercased()
    let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:10000)
    let configuration=try SandboxConfiguration(job:id,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
    try admission.reserve(job:id,memory:configuration.memory,cpus:1,sample:sample(10000),now:10000)
    _=try journal.reserveSandbox(job:job,configuration:configuration)
    for index in 0..<14 {
        let now:Int64=10000+Int64(index)*500
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    let running=try journal.jobs()[0];precondition(running.state == .running)
    // Independent local model metadata has no dispatched worker/request here.
    let modelID=UUID().uuidString.lowercased()
    _=try journal.reserveJob(DurableJob(id:modelID,idempotency:UUID().uuidString.lowercased(),
        ownerHash:job.ownerHash,requestHash:job.requestHash,created:18000))
    try journal.transitionJob(id:modelID,to:.running,now:18000)
    try journal.claim(job:modelID,attempt:0,model:"fixture/model")
    try journal.markUncertain(job:modelID,attempt:0)
    try journal.transitionJob(id:id,to:.revoking,now:20000)
    runtime.holdResponses=true
    try controller.tick(now:20000,sample:sample(20000),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    let first=controller.cleanupStatus(now:20000)
    precondition(first["pending_sandboxes"] as? Int == 1 && first["waiting_over_60s"] as? Bool == false)
    precondition(first["observed_at"] as? Int64 == 20000 && first["manager_observation_age_ms"] as? Int64 == 0)
    try controller.tick(now:81000,sample:sample(81000),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    let waiting=controller.cleanupStatus(now:81000)
    precondition(waiting["observed_wait_ms"] as? Int64 == 61000 && waiting["waiting_over_60s"] as? Bool == true)
    precondition(waiting["manager_observation_age_ms"] as? Int64 == 0)
    precondition(controller.cleanupStatus(now:81500)["manager_observation_age_ms"] as? Int64 == 500)
    precondition(controller.cleanupStatus(now:80999)["manager_observation_age_ms"] is NSNull)
    runtime.holdResponses=false
    for index in 0..<20 {
        let now:Int64=82000+Int64(index)*500
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    let removed=try journal.jobs().first{$0.id==id};precondition(removed?.state == .removed)
    let completed=controller.cleanupStatus(now:92000)
    precondition(completed["pending_sandboxes"] as? Int == 0 && completed["waiting_over_60s"] as? Bool == false)
    let unresolved=try journal.unresolvedCount(),uncertain=try journal.uncertainCount()
    precondition(unresolved==1 && uncertain==1)
    let lateID=UUID().uuidString.lowercased()
    let late=try DurableJob(id:lateID,idempotency:UUID().uuidString.lowercased(),ownerHash:job.ownerHash,requestHash:job.requestHash,created:93000)
    let lateConfig=try SandboxConfiguration(job:lateID,nonce:String(repeating:"c",count:64),image:configuration.image,memory:configuration.memory,cpus:1)
    _=try journal.reserveSandbox(job:late,configuration:lateConfig)
    runtime.commands.removeAll()
    runtime.loseCreateReply=true
    func tick(_ now:Int64)throws {
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    try tick(93000)
    try tick(93500)
    try journal.transitionJob(id:lateID,to:.revoking,now:94000)
    for now:Int64 in [94000,95500,96000] {try tick(now)}
    runtime.acknowledgeInspection=true
    try tick(97500)
    do {
        try tick(98000)
        fatalError("Inspection accepted an untyped effect acknowledgement")
    } catch JournalError.conflict {}
    runtime.acknowledgeInspection=false
    let pending=try journal.sandboxRecords().first{$0.configuration.job==lateID}
    guard pending?.createIssued==true,pending?.runtimeID==nil,pending?.removalProven==false,
          controller.cleanupStatus(now:98000)["pending_sandboxes"] as? Int==1,
          controller.cleanupStatus(now:98000)["observed_at"] as? Int64==97500,
          controller.cleanupStatus(now:98000)["manager_observation_age_ms"] as? Int64==500 else {
        fatalError("Failed cleanup tick redated observation or lost create custody")
    }
    runtime.storageContinuityUnknown=true
    try tick(99500)
    try tick(100000)
    guard controller.cleanupStatus(now:100000)["storage_continuity_unknown"] as? Int==1,
          try journal.sandboxRecords().first(where:{$0.configuration.job==lateID})?.removalProven==false else {
        fatalError("Storage continuity refusal was hidden or released custody")
    }
    var unresolvedCapacity=admission
    try unresolvedCapacity.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:sample(100000),now:100000)
    do {
        try unresolvedCapacity.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:sample(100000),now:100000)
        fatalError("Storage continuity refusal returned an occupied reservation")
    } catch AdmissionError.capacity {}
    do {
        try journal.transitionJob(id:lateID,to:.removed,now:100000)
        fatalError("Unproven sandbox cleanup allowed terminal transition")
    } catch JournalError.conflict {}
    try journal.expireTerminalJobs(now:86_500_000)
    guard try journal.sandboxRecords().contains(where:{$0.configuration.job==lateID && !$0.removalProven}) else {
        fatalError("Terminal metadata retention discarded unresolved sandbox custody")
    }
    runtime.storageContinuityUnknown=false
    let lateRuntimeID=String(repeating:"d",count:64)
    runtime.present[lateID]=(lateConfig,lateRuntimeID,false)
    for now:Int64 in [101500,102000,102500,103500,104000] {try tick(now)}
    let final=try journal.sandboxRecords().first{$0.configuration.job==lateID}
    let commands=runtime.commands
    guard final?.runtimeID==lateRuntimeID,final?.removalProven==true,
          controller.cleanupStatus(now:104000)["storage_continuity_unknown"] as? Int==0,
          commands.filter({if case .create=$0 {return true};return false}).count==1,
          !commands.contains(where:{if case .start=$0 {return true};return false}),
          try journal.unresolvedCount()==1,try journal.uncertainCount()==1 else {fatalError("Late sandbox was replayed, started, or released independent model uncertainty")}
    var releasedCapacity=admission
    for _ in 0..<2 {try releasedCapacity.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:sample(104000),now:104000)}
    let unissuedID=UUID().uuidString.lowercased()
    let unissued=try DurableJob(id:unissuedID,idempotency:UUID().uuidString.lowercased(),ownerHash:job.ownerHash,requestHash:job.requestHash,created:105000)
    let unissuedConfig=try SandboxConfiguration(job:unissuedID,nonce:lateConfig.nonce,image:configuration.image,memory:configuration.memory,cpus:1)
    _=try journal.reserveSandbox(job:unissued,configuration:unissuedConfig)
    try admission.reserve(job:unissuedID,memory:unissuedConfig.memory,cpus:1,sample:sample(105000),now:105000)
    try journal.transitionJob(id:unissuedID,to:.revoking,now:105000)
    let beforeLocal=runtime.commands.count
    try tick(105000)
    try tick(105500)
    guard runtime.commands.count==beforeLocal else {fatalError("Unissued reservation dispatched a cleanup command")}
    // The ordinary manager tick released the local reservation, so a new
    // in-memory reservation for the same key no longer conflicts.
    try admission.reserve(job:unissuedID,memory:unissuedConfig.memory,cpus:1,sample:sample(105500),now:105500)
    print("PASS: delayed and never-issued runtime cleanup preserve exact custody and reservation release")
}
