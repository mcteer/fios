import Foundation

private final class FakeSandboxExecutor:SandboxExecuting {
    var values:[SandboxExecution]=[]
    var commands:[SandboxCommand]=[]
    var present:[String:(SandboxConfiguration,String,Bool)]=[:]
    var active:Int { 0 }
    var resourceNow:Int64=0
    var resourceFailure=false
    var resourceRequests:[Int64]=[]
    var resourceValues:[VMReadResult]=[]
    func submitResources(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws {
        resourceRequests.append(resourceNow)
        let envelope=VMResourceObservation(runtimeHash:String(repeating:"a",count:64),sampledAt:resourceNow,configuredCap:12<<30,total:16<<30,free:8<<30,allVMConsumersCovered:true)
        let sample=VMKernelSample(sampledAt:resourceNow,total:16<<30,free:8<<30,bootHash:String(repeating:"b",count:64),envelope:envelope)
        resourceValues.append(VMReadResult(job:configuration.job,runtimeID:id,result:resourceFailure ? .failure(.unavailable) : .success(sample)))
    }
    func drainResources()->[VMReadResult] {let values=resourceValues;resourceValues=[];return values}
    func submit(job:String,command:SandboxCommand) throws {
        commands.append(command)
        let result:SandboxExecutionValue
        switch command {
        case .create(let config):
            let id=String(repeating:job.first=="a" ? "a" : "b",count:64)
            present[job]=(config,id,false);result = .created(id)
        case .inspect:
            if let (config,id,running)=present[job] { result = .observed(.present(id:id,name:"/"+config.name,image:config.image,nonce:config.nonce,running:running)) }
            else { result = .observed(.absent) }
        case .start:
            if let (config,id,_)=present[job] { present[job]=(config,id,true) };result = .acknowledged
        case .stop:
            if let (config,id,_)=present[job] { present[job]=(config,id,false) };result = .acknowledged
        case .remove:present.removeValue(forKey:job);result = .acknowledged
        }
        values.append(SandboxExecution(job:job,result:.success(result)))
    }
    func drain()->[SandboxExecution] { let result=values;values=[];return result }
}

func runJobControllerTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try Journal(directory:directory),runtime=FakeSandboxExecutor()
    let controller=JobController(journal:journal,executor:runtime)
    var admission=AdmissionPolicy()
    func sample(_ now:Int64,cpu:Double=10)->ResourceSample { ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:cpu,pressure:.normal,thermal:.nominal,vmSampledAt:now) }
    let ids=[UUID().uuidString.lowercased(),UUID().uuidString.lowercased()]
    for (index,id) in ids.enumerated() {
        let stamp:Int64=10000+Int64(index)
        let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:stamp)
        let config=try SandboxConfiguration(job:id,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
        try admission.reserve(job:id,memory:config.memory,cpus:1,sample:sample(stamp),now:stamp)
        _=try journal.reserveSandbox(job:job,configuration:config)
    }
    for tick in 0..<5 {
        try controller.tick(now:11000+Int64(tick*100),sample:sample(11000+Int64(tick*100)),admission:&admission,transportReady:{_ in false},cancelModel:{_ in})
    }
    guard runtime.commands.allSatisfy({if case .start=$0 {return false};return true}) else { fatalError("Container started before trusted transport readiness") }
    for tick in 0..<7 {
        try controller.tick(now:13000+Int64(tick*500),sample:sample(13000+Int64(tick*500)),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard try journal.jobs().allSatisfy({$0.state == .running}) else { fatalError("Sandbox coordinator did not reach running") }
    var cancelled:[String]=[]
    try controller.tick(now:19000,sample:sample(19000,cpu:90),admission:&admission,transportReady:{_ in true},cancelModel:{cancelled.append($0)})
    guard cancelled==[ids[1]],try journal.jobs().first(where:{$0.id==ids[0]})?.state == .running else { fatalError("Pressure did not select durable newest-owned job only") }
    for tick in 0..<24 {
        try controller.tick(now:19100+Int64(tick*500),sample:sample(19100+Int64(tick*500)),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard try journal.jobs().first(where:{$0.id==ids[1]})?.state == .removed else { fatalError("Owned sandbox cleanup did not finish") }
    print("PASS: asynchronous sandbox coordinator, transport-before-start fencing, newest-owned pressure revocation and proof-gated cleanup")
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
    func sample(_ now:Int64)->ResourceSample {ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)}
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
        ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:vm,diskFree:100<<30,cpu:cpu,pressure:.normal,thermal:.nominal,vmSampledAt:now)
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
    let sample=ResourceSample(sampledAt:11000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
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
    func sample(_ now:Int64)->ResourceSample {ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:now)}
    let id=UUID().uuidString.lowercased(),job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:10000)
    let config=try SandboxConfiguration(job:id,nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:512<<20,cpus:1)
    try admission.reserve(job:id,memory:config.memory,cpus:1,sample:sample(10000),now:10000)
    _=try journal.reserveSandbox(job:job,configuration:config)
    for tick in 0..<14 {
        let now:Int64=10000+Int64(tick)*500;runtime.resourceNow=now
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard !runtime.resourceRequests.isEmpty,controller.vmAvailable(now:16500)==4<<30,controller.vmEpoch(now:16500)?.count==64,
          controller.vmAvailable(now:30000)==nil else {fatalError("VM controller failed fresh/stale capacity publication")}
    for pair in zip(runtime.resourceRequests,runtime.resourceRequests.dropFirst()) {guard pair.1-pair.0>=2000 else {fatalError("Unbounded VM polling")}}
    runtime.resourceFailure=true
    for tick in 0..<8 {
        let now:Int64=17000+Int64(tick)*500;runtime.resourceNow=now
        try controller.tick(now:now,sample:sample(now),admission:&admission,transportReady:{_ in true},cancelModel:{_ in})
    }
    guard controller.vmAvailable(now:20500)==nil,controller.vmEpoch(now:20500)==nil else {fatalError("Failed source retained verified VM capacity")}
    print("PASS: serialized VM coordinator polls owned running targets at2s, publishes only fresh envelopes and immediately invalidates failed/stale resource authority (fake runtime telemetry)")
}
