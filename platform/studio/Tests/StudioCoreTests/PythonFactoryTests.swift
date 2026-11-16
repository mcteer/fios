import Foundation
import CryptoKit
import Darwin
import CSQLite

func runPythonFactoryTests() throws {
    func progress(_ phase:String) {FileHandle.standardError.write(Data(("Python factory fixture: "+phase+"\n").utf8))}
    progress("begin")
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let invocation=root.appendingPathComponent(".venv/bin/python")
    let executable=invocation.resolvingSymlinksInPath()
    let sha=SHA256.hash(data:try Data(contentsOf:executable)).map {String(format:"%02x",$0)}.joined()
    let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("tests/fixtures/platform/model.json"))) as! [String:Any]
    do {
        try CommandSlots.shared.acquire();defer {CommandSlots.shared.release(nil)}
        try CommandSlots.shared.acquire();defer {CommandSlots.shared.release(nil)}
        do {
            _=try PythonWorkerFactory(invocation:invocation.path,executableSHA256:sha,policySHA256:fixture["policy_sha256"] as! String)
            fatalError("PYTHON_METADATA_PROBE_BYPASSED_SHARED_COMMAND_BUDGET")
        }catch RuntimeError.capacity {}
    }
    progress("metadata begin")
    let factory=try PythonWorkerFactory(invocation:invocation.path,executableSHA256:sha,policySHA256:fixture["policy_sha256"] as! String)
    progress("metadata ready")
    let metadataBytes=try JSONEncoder().encode(FactoryMetadataFixture(version:2,pipe_version:1,native_handoff_version:1,package_version:"0.1.0",python_version:"3.11.17",policy_sha256:factory.metadata.policy_sha256,policy_input_units:factory.metadata.policy_input_units))
    _=try WorkerMetadata.decode(metadataBytes,policySHA256:factory.metadata.policy_sha256)
    var legacy=try JSONSerialization.jsonObject(with:metadataBytes) as! [String:Any]
    legacy.removeValue(forKey:"native_handoff_version");legacy["version"]=1
    do {_=try WorkerMetadata.decode(JSONSerialization.data(withJSONObject:legacy),policySHA256:factory.metadata.policy_sha256);fatalError("Legacy private worker accepted without handoff contract")}catch RuntimeError.identity {}
    for unsupported in [0,2] {
        var invalid=try JSONSerialization.jsonObject(with:metadataBytes) as! [String:Any]
        invalid["native_handoff_version"]=unsupported
        do {_=try WorkerMetadata.decode(JSONSerialization.data(withJSONObject:invalid),policySHA256:factory.metadata.policy_sha256);fatalError("Unsupported handoff protocol accepted")}catch RuntimeError.identity {}
    }
    var preparationMetadata=try JSONSerialization.jsonObject(with:metadataBytes) as! [String:Any]
    preparationMetadata["version"]=3;preparationMetadata["native_preparation_version"]=1
    guard try WorkerMetadata.decode(JSONSerialization.data(withJSONObject:preparationMetadata),policySHA256:factory.metadata.policy_sha256).native_preparation_version==1 else {fatalError("Preparation worker protocol lost")}
    for unsupported in [0,2] {
        var invalid=preparationMetadata;invalid["native_preparation_version"]=unsupported
        do {_=try WorkerMetadata.decode(JSONSerialization.data(withJSONObject:invalid),policySHA256:factory.metadata.policy_sha256);fatalError("Unsupported preparation protocol accepted")}catch RuntimeError.identity {}
    }
    preparationMetadata["version"]=2
    do {_=try WorkerMetadata.decode(JSONSerialization.data(withJSONObject:preparationMetadata),policySHA256:factory.metadata.policy_sha256);fatalError("Legacy metadata silently acquired preparation capability")}catch RuntimeError.identity {}
    print("PASS: exact legacy metadata2 and scoped-preparation metadata3 contracts; unsupported or mixed versions refuse")
    guard factory.metadata.policy_input_units==fixture["policy_input_units"] as? Int else { fatalError("Installed policy units diverged from cross-language fixture") }
    try runNeverSpawnedWorkerTests(factory:factory)
    try runHandoffNeverSpawnedTests(factory:factory)
    try runHandoffPreparationFailureTests(factory:factory)
    try runUnusedPreparationCancellationTest(factory:factory)
    try runUnusedFactoryWithdrawalTests(factory:factory)
    do {
        _=try PythonWorkerFactory(invocation:invocation.path,executableSHA256:String(repeating:"0",count:64),policySHA256:fixture["policy_sha256"] as! String)
        fatalError("Wrong interpreter hash accepted")
    } catch RuntimeError.identity {}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds()
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest("http://127.0.0.1:1/v1"),nativeEpoch:"native-fixture-one",sequence:1,sampledAt:now,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:false,apiKey:nil)
    do {
        _=try factory.start(journal:journal,job:UUID().uuidString.lowercased(),attempt:0,binding:binding,command:Data(),now:now)
        fatalError("Unaccepted native profile launched a worker")
    } catch PolicyError.invalidObservation {}
    guard try journal.workerGrants().isEmpty else { fatalError("Rejected native profile consumed a worker grant") }
    let mock=Process(),input=Pipe(),output=Pipe()
    let epoch=UUID().uuidString.lowercased()
    mock.executableURL=invocation;mock.arguments=["-I","-B",root.appendingPathComponent("tests/fixtures/platform/native-server.py").path,directory.path,epoch]
    guard let mockPort=ProcessInfo.processInfo.environment["FIOS_PLATFORM_MOCK_PORT"],
          let selectedPort=Int(mockPort),(49152...65535).contains(selectedPort),String(selectedPort)==mockPort else {throw RuntimeError.invalid}
    mock.environment=["PATH":"/usr/bin:/bin","LANG":"C","FIOS_PLATFORM_MOCK_PORT":mockPort]
    mock.standardInput=input;mock.standardOutput=output;mock.standardError=FileHandle.nullDevice
    progress("mock launch begin")
    try mock.run()
    progress("mock launch ready")
    defer {
        progress("mock cleanup begin")
        try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()
        let limit=ProcessInfo.processInfo.systemUptime+2
        while mock.isRunning && ProcessInfo.processInfo.systemUptime<limit { Thread.sleep(forTimeInterval:0.01) }
        if mock.isRunning { kill(mock.processIdentifier,SIGKILL) }
        if !mock.isRunning { mock.waitUntilExit() }
        progress("mock cleanup done")
    }
    let fd=output.fileHandleForReading.fileDescriptor
    guard fcntl(fd,F_SETFL,O_NONBLOCK)>=0 else { throw RuntimeError.launch }
    let readyDeadline=ProcessInfo.processInfo.systemUptime+5
    var ready=Data()
    while !ready.contains(10) && ProcessInfo.processInfo.systemUptime<readyDeadline {
        var bytes=[UInt8](repeating:0,count:4096)
        let count=Darwin.read(fd,&bytes,bytes.count)
        if count>0 { ready.append(contentsOf:bytes.prefix(count)) }
        guard ready.count<=4096 else { throw RuntimeError.outputLimit }
        Thread.sleep(forTimeInterval:0.01)
    }
    guard let descriptor=try JSONSerialization.jsonObject(with:ready) as? [String:Any],
          let port=descriptor["port"] as? Int,port==selectedPort else { throw RuntimeError.launch }
    progress("mock endpoint ready")
    guard try ServiceHealthProbe(port:port).probe() == .healthy else {fatalError("Fixed mock GET /health unavailable")}
    // Preserve an explicit reviewed ephemeral port instead of falling back to
    // the fixed native default. This mock accepts GET /health only.
    let reviewedInputs=try NativeServingLaunchInputs(arguments:["--serve","--host","0.0.0.0","--port",String(port),"--api-key","--host"],environment:[:],workingDirectory:"/")
    guard try ServiceHealthProbe(reviewedInputs:reviewedInputs).probe() == .healthy else {fatalError("Reviewed health listener/port not preserved")}
    for host in ["::","0:0:0:0:0:0:0:1"] {
        let inputs=try NativeServingLaunchInputs(arguments:["--serve","--host",host,"--port",String(port),"--api-key-env","FIOS_MLX_SERVING_API_KEY"],environment:["FIOS_MLX_SERVING_API_KEY":"fixture-health"],workingDirectory:"/")
        guard try ServiceHealthProbe(reviewedInputs:inputs).probe() == .healthy else {fatalError("Reviewed IPv6 health listener/authority failed")}
    }
    let mockIdentity=ServiceIdentity(pid:mock.processIdentifier,start:try WorkerResources.startIdentifier(pid:mock.processIdentifier),sha256:sha)
    let localProbe=try ServiceHealthProbe(port:port)
    guard let firstListener=localProbe.listenerIdentity(for:mockIdentity),
          localProbe.listenerIdentity(for:mockIdentity)==firstListener else {fatalError("Original mock listener not associated with its exact process")}
    let ipv6Inputs=try NativeServingLaunchInputs(arguments:["--serve","--host","::","--port",String(port),"--api-key","fixture-health"],environment:[:],workingDirectory:"/")
    guard let ipv6Listener=try ServiceHealthProbe(reviewedInputs:ipv6Inputs).listenerIdentity(for:mockIdentity),
          ipv6Listener != firstListener else {fatalError("IPv6 process listener missing or confused with IPv4")}
    let wrongProcess=ServiceIdentity(pid:getpid(),start:try WorkerResources.startIdentifier(pid:getpid()),sha256:sha)
    guard localProbe.listenerIdentity(for:wrongProcess)==nil else {fatalError("Another process acquired mock listener association")}
    let wrongStart=ServiceIdentity(pid:mockIdentity.pid,start:mockIdentity.start+1,sha256:sha)
    guard localProbe.listenerIdentity(for:wrongStart)==nil else {fatalError("Foreign process generation acquired listener")}
    // The native mock returns healthy ONLY for GET /health. Its later exact
    // POST counts must remain unchanged: health must never issue inference.
    let base="http://127.0.0.1:\(port)/v1",hash=PythonWorkerFactory.digest(base)
    let timestamp=HostResources.nowMilliseconds(),job=UUID().uuidString.lowercased()
    try journal.claim(job:job,attempt:0,model:"fixture/model")
    let observation=NativeSnapshot(host:"fixture-host",endpointHash:hash,nativeEpoch:"native-fixture-one",sequence:1,sampledAt:timestamp,allClientLifecycleCoverage:true,residentModel:"fixture/idle-other",outstandingOwners:0,loading:false)
    let accepted=WorkerDispatchBinding(baseURL:base,guardPath:directory.appendingPathComponent("observe.sock").path,host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:epoch,canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:observation,nativeCompatibilityAccepted:true,apiKey:nil)
    let command=try JSONSerialization.data(withJSONObject:["v":1,"type":"run","job_id":job,"attempt":0,"epoch":epoch,"model":"fixture/model","endpoint_hash":hash,"expires_at":timestamp+5000,"context":[["role":"user","content":"fixture only"]]])
    progress("direct worker launch begin")
    let worker=try factory.start(journal:journal,job:job,attempt:0,binding:accepted,command:command,now:timestamp)
    progress("direct worker launch ready")
    let finish=ProcessInfo.processInfo.systemUptime+10
    var answer="",complete=false
    while !worker.reaped && ProcessInfo.processInfo.systemUptime<finish {
        for event in try worker.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:true) {
            if case .text(_,let text)=event { answer+=text }
            if case .complete=event { complete=true }
        }
        Thread.sleep(forTimeInterval:0.01)
    }
    guard complete,answer=="MOCK_ONLY",worker.reaped,try journal.unresolvedCount()==0,try journal.workerGrants().isEmpty else { fatalError("Fixed production entry/independent guard/mock API roundtrip failed") }
    progress("direct worker reaped")
    let broker=ModelBroker(journal:journal,factory:factory),owner=String(repeating:"a",count:64),scoped=UUID().uuidString.lowercased()
    _=try journal.reserveJob(DurableJob(id:scoped,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:HostResources.nowMilliseconds()))
    try journal.transitionJob(id:scoped,to:.running)
    func freshBinding()->WorkerDispatchBinding {
        let state=NativeSnapshot(host:"fixture-host",endpointHash:hash,nativeEpoch:"native-fixture-one",sequence:1,sampledAt:HostResources.nowMilliseconds(),allClientLifecycleCoverage:true,residentModel:"fixture/idle-other",outstandingOwners:0,loading:false)
        return WorkerDispatchBinding(baseURL:base,guardPath:directory.appendingPathComponent("observe.sock").path,host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:epoch,canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:state,nativeCompatibilityAccepted:true,apiKey:nil)
    }
    func resources(_ now:Int64)->ResourceSample { ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal) }
    var admission=AdmissionPolicy()
    progress("broker rounds begin")
    for attempt in 0..<4 {
        let time=HostResources.nowMilliseconds()
        try broker.submit(job:scoped,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture only")],binding:freshBinding(),nativeCapacityProven:true,sample:resources(time),admission:&admission,now:time)
        progress("broker round submitted")
        let limit=ProcessInfo.processInfo.systemUptime+10
        var text="",done=false
        while broker.activeWorkers>0 && ProcessInfo.processInfo.systemUptime<limit {
            let events=try broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in freshBinding()})
            for event in events[scoped] ?? [] {
                if case .text(_,let chunk)=event { text+=chunk }
                if case .complete=event { done=true }
            }
            Thread.sleep(forTimeInterval:0.01)
        }
        guard done,text=="MOCK_ONLY",broker.activeWorkers==0 else { fatalError("Broker fixed-target mock roundtrip failed") }
        guard let retained=try journal.inferenceScope(job:scoped,attempt:attempt),retained.state == .uncertain,
              try journal.hasClaim(job:scoped,attempt:attempt) else {
            fatalError("BROKER_HTTP_COMPLETION_RELEASED_NATIVE_OWNERSHIP")
        }
        // This fixture supplies a separate synthetic native terminal receipt
        // between rounds. HTTP completion above must never supply it.
        try journal.resolveInference(job:scoped,attempt:attempt,scope:retained.scope,outcome:.complete)
    }
    let time=HostResources.nowMilliseconds()
    do {
        try broker.submit(job:scoped,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture only")],binding:freshBinding(),nativeCapacityProven:true,sample:resources(time),admission:&admission,now:time)
        fatalError("Fifth model request dispatched")
    } catch JournalError.trackingLimit {}
    guard try journal.requestCount(job:scoped)==4,try journal.unresolvedCount()==0 else { fatalError("Broker lost durable finite budget") }
    try journal.transitionJob(id:scoped,to:.revoking)
    try journal.transitionJob(id:scoped,to:.removed)
    progress("broker rounds reaped")
    let controller=TaskController(journal:journal,broker:broker),idempotency=UUID().uuidString.lowercased()
    let modelContext=[ModelText(role:"user",content:"fixture only")]
    let created=try controller.createModelJob(owner:owner,idempotency:idempotency,context:modelContext,binding:freshBinding(),nativeCapacityProven:true,sample:resources(time),admission:&admission,now:time)
    guard try controller.createModelJob(owner:owner,idempotency:idempotency,context:modelContext,binding:freshBinding(),nativeCapacityProven:true,sample:resources(time),admission:&admission,now:time).id==created.id else { fatalError("Active model job idempotency diverged") }
    let modelEnd=ProcessInfo.processInfo.systemUptime+10
    var modelText=""
    while try journal.jobs().first(where:{$0.id==created.id})?.state != .removed && ProcessInfo.processInfo.systemUptime<modelEnd {
        let events=try controller.tick(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in freshBinding()})
        for event in events[created.id] ?? [] { if case .text(_,let text)=event { modelText+=text } }
        Thread.sleep(forTimeInterval:0.01)
    }
    let replay=try controller.createModelJob(owner:owner,idempotency:idempotency,context:modelContext,binding:freshBinding(),nativeCapacityProven:true,sample:resources(time),admission:&admission,now:time)
    guard modelText=="MOCK_ONLY",replay.id==created.id,replay.state == .removed,try journal.requestCount(job:created.id)==1 else { fatalError("Model-only lifecycle/data/idempotency failed") }
    progress("model-only controller reaped")
    let uploadHash=String(repeating:"d",count:64),uploadStamp=HostResources.nowMilliseconds()
    let uploaded=try controller.reserveModelUpload(owner:owner,idempotency:UUID().uuidString.lowercased(),requestHash:uploadHash,binding:freshBinding(),nativeCapacityProven:true,sample:resources(uploadStamp),admission:&admission,now:uploadStamp)
    guard uploaded.state == .reserved,broker.activeWorkers==0,try journal.requestCount(job:uploaded.id)==0 else {fatalError("Input reservation dispatched before complete validation")}
    _=try controller.startModelUpload(id:uploaded.id,owner:owner,requestHash:uploadHash,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture only")],binding:freshBinding(),nativeCapacityProven:true,sample:resources(HostResources.nowMilliseconds()),admission:&admission,now:HostResources.nowMilliseconds())
    var uploadText=""
    let uploadEnd=ProcessInfo.processInfo.systemUptime+10
    while ProcessInfo.processInfo.systemUptime<uploadEnd {
        let events=try controller.tick(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in freshBinding()})
        for event in events[uploaded.id] ?? [] {if case .text(_,let text)=event {uploadText+=text}}
        if try journal.jobs().first(where:{$0.id==uploaded.id})?.state == .removed {break}
        Thread.sleep(forTimeInterval:0.01)
    }
    guard uploadText=="MOCK_ONLY",try journal.requestCount(job:uploaded.id)==1 else {fatalError("Validated reserved model input failed")}
    let replayUpload=try controller.startModelUpload(id:uploaded.id,owner:owner,requestHash:uploadHash,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture only")],binding:freshBinding(),nativeCapacityProven:true,sample:resources(HostResources.nowMilliseconds()),admission:&admission,now:HostResources.nowMilliseconds())
    guard replayUpload.state == .removed,broker.activeWorkers==0,try journal.requestCount(job:uploaded.id)==1 else {fatalError("Consumed input upload replayed")}
    progress("model upload reaped")
    let exportService=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("gateway-exports"),availableBytes:{100<<30}))
    let noRuntime=JobController(journal:journal,executor:UnavailableSandboxRuntime())
    let unusedSandbox=SandboxTaskController(journal:journal,jobs:noRuntime,tasks:controller,artifacts:exportService,socket:"/fixture/no-runtime.sock",peerUID:geteuid())
    let gateway=TaskCommands(journal:journal,tasks:controller,sandbox:unusedSandbox,artifacts:exportService,approvedImages:[],enrolled:true,peerUID:geteuid(),admissionOpen:{true})
    let credential=TaskOwner.newToken()
    let inputContext=try JSONSerialization.data(withJSONObject:[["role":"user","content":"fixture only"]])
    func rpc(_ operation:String,_ payload:[String:Any]) throws->[String:Any] {
        let data=try JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":operation,"payload":payload.merging(["owner":credential]) {_,new in new}])
        let now=HostResources.nowMilliseconds()
        return try gateway.handle(ControlRequest.decode(data),role:.task,sample:resources(now),admission:&admission,binding:{name in name=="fixture/model" ? freshBinding():nil},nativeCapacityProven:true,now:now,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000))
    }
    let reserved=try rpc("job.create",["phase":"begin","idempotency":UUID().uuidString.lowercased(),"kind":"model","length":inputContext.count,"sha256":SHA256.hash(data:inputContext).map {String(format:"%02x",$0)}.joined(),"lifetime":30000,"model":"fixture/model","image":NSNull(),"memory":0,"cpus":0])
    let rpcJob=reserved["job"] as! String
    guard reserved["state"] as? String=="reserved",try journal.requestCount(job:rpcJob)==0 else {fatalError("Task API dispatched before complete input")}
    _=try rpc("model.request",["phase":"chunk","job":rpcJob,"index":0,"data":inputContext.base64EncodedString()])
    _=try rpc("model.request",["phase":"end","job":rpcJob])
    // A lost end acknowledgement may be replayed while the first worker is
    // still running, not only after its independent local reap finishes.
    _=try rpc("model.request",["phase":"end","job":rpcJob])
    guard try journal.requestCount(job:rpcJob)==1 else {fatalError("Active end replay dispatched twice")}
    var rpcText="",rpcDone=false
    let rpcEnd=ProcessInfo.processInfo.systemUptime+10
    while ProcessInfo.processInfo.systemUptime<rpcEnd {
        let now=HostResources.nowMilliseconds(),up=Int64(ProcessInfo.processInfo.systemUptime*1000)
        let events=try controller.tick(now:now,uptime:up,admission:&admission,source:{_ in freshBinding()})
        try gateway.tick(now:now,uptime:up,artifactResults:[],model:events)
        let state=try rpc("job.status",["job":rpcJob])
        if let event=state["event"] as? [String:Any] {
            if event["type"] as? String=="model.text" {rpcText+=event["content"] as! String}
            if event["type"] as? String=="model.done" {rpcDone=event["status"] as? String=="complete"}
        }
        if rpcDone {break}
        Thread.sleep(forTimeInterval:0.01)
    }
    guard rpcDone,rpcText=="MOCK_ONLY",try journal.requestCount(job:rpcJob)==1 else {fatalError("Owner task API/model input/output stream failed")}
    _=try rpc("model.request",["phase":"end","job":rpcJob])
    guard try journal.requestCount(job:rpcJob)==1 else {fatalError("Task API model end replay spent another request")}
    progress("owner RPC model reaped")
    // Fake runtime identity/lifecycle; real production Python/Unix/HTTP mock path.
    let sandboxID=UUID().uuidString.lowercased(),containerID=String(repeating:"c",count:64)
    let configuration=try SandboxConfiguration(job:sandboxID,nonce:String(repeating:"d",count:64),image:"sha256:"+String(repeating:"e",count:64),memory:512<<20,cpus:1)
    let sandbox=try DurableJob(id:sandboxID,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:HostResources.nowMilliseconds())
    _=try journal.reserveSandbox(job:sandbox,configuration:configuration)
    let lifecycle=SandboxLifecycle(journal:journal)
    _=try lifecycle.next(job:sandboxID,now:HostResources.nowMilliseconds(),resourcesSafe:true)
    try lifecycle.created(job:sandboxID,runtimeID:containerID)
    _=try lifecycle.observed(job:sandboxID,presence:.present(id:containerID,name:"/"+configuration.name,image:configuration.image,nonce:configuration.nonce,running:false),now:HostResources.nowMilliseconds(),resourcesSafe:true)
    _=try lifecycle.observed(job:sandboxID,presence:.present(id:containerID,name:"/"+configuration.name,image:configuration.image,nonce:configuration.nonce,running:true),now:HostResources.nowMilliseconds(),resourcesSafe:true)
    try controller.registerSandbox(id:sandboxID,owner:owner,runtimeID:containerID,binding:freshBinding())
    let requestID=UUID().uuidString.lowercased(),stamp=HostResources.nowMilliseconds()
    let requestFrame=try JSONSerialization.data(withJSONObject:["version":1,"type":"model.request","id":requestID,"prompt":"fixture only"])
    try controller.sandboxModelFrame(id:sandboxID,runtimeID:containerID,data:requestFrame,binding:freshBinding(),nativeCapacityProven:true,sample:resources(stamp),admission:&admission,now:stamp,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000))
    var sandboxText="",sandboxDone=false
    let sandboxEnd=ProcessInfo.processInfo.systemUptime+10
    while broker.activeWorkers>0 && ProcessInfo.processInfo.systemUptime<sandboxEnd {
        let events=try controller.tick(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in freshBinding()})
        for frame in try controller.sandboxModelData(events)[sandboxID] ?? [] {
            let value=try JSONSerialization.jsonObject(with:frame) as! [String:Any]
            guard value["id"] as? String==requestID else { fatalError("Sandbox model response crossed scopes") }
            if value["type"] as? String=="model.delta" { sandboxText+=value["content"] as! String }
            if value["type"] as? String=="model.done" { sandboxDone=value["status"] as? String=="complete" }
        }
        Thread.sleep(forTimeInterval:0.01)
    }
    guard sandboxDone,sandboxText=="MOCK_ONLY",try journal.requestCount(job:sandboxID)==1 else { fatalError("Scoped sandbox model mediation failed") }
    try lifecycle.cancelled(job:sandboxID,now:HostResources.nowMilliseconds())
    _=try lifecycle.observed(job:sandboxID,presence:.absent,now:HostResources.nowMilliseconds(),resourcesSafe:true)
    progress("sandbox-mediated model reaped")
    let earlierUnresolved=try journal.unresolvedCount(),earlierUncertain=try journal.uncertainCount()
    let active=[UUID().uuidString.lowercased(),UUID().uuidString.lowercased()]
    for id in active {
        let stamp=HostResources.nowMilliseconds()
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:stamp))
        try journal.transitionJob(id:id,to:.running,now:stamp)
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture only")],binding:freshBinding(),nativeCapacityProven:true,sample:resources(stamp),admission:&admission,now:stamp)
    }
    progress("two pending workers submitted")
    guard broker.activeWorkers==2 else { fatalError("Two scoped workers were not admitted") }
    do { try admission.reserveWorker(key:"third",sample:resources(time),now:time);fatalError("Third worker admitted") } catch AdmissionError.capacity {}
    let lost=ProcessInfo.processInfo.systemUptime
    while broker.activeWorkers>0 && ProcessInfo.processInfo.systemUptime-lost<2 {
        _=try broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in nil})
        Thread.sleep(forTimeInterval:0.01)
    }
    let sourceLossStates=try active.map {try journal.inferenceScope(job:$0,attempt:0)?.state}
    let retainedSourceLoss=sourceLossStates.filter {$0 == .uncertain}.count
    guard broker.activeWorkers==0,sourceLossStates.allSatisfy({$0 == .uncertain || $0 == .not_sent}),
          try journal.unresolvedCount()==earlierUnresolved+retainedSourceLoss,
          try journal.uncertainCount()==earlierUncertain+retainedSourceLoss,try journal.workerGrants().isEmpty,
          try active.allSatisfy({try journal.workerLaunchReaped(job:$0,attempt:0) && journal.requestCount(job:$0)==1}),
          try journal.jobs().filter({active.contains($0.id)}).allSatisfy({$0.state == .revoking}) else { fatalError("Source loss did not revoke/reap without clearing native uncertainty") }
    progress("source-loss workers reaped")
    let conflictReports=try runBusySourceWorkerTests(directory:directory.appendingPathComponent("busy-source"),factory:factory,
        original:freshBinding(),postReports:fd)
    // Mock fixture reports only aggregate POST counts, never headers/prompts.
    var counts=conflictReports
    while true {
        var bytes=[UInt8](repeating:0,count:4096)
        let n=Darwin.read(fd,&bytes,bytes.count)
        if n<=0 { break };counts.append(contentsOf:bytes.prefix(n))
        guard counts.count<4096 else { throw RuntimeError.outputLimit }
    }
    let reports=String(decoding:counts,as:UTF8.self).split(separator:"\n")
    guard reports.count==1,let last=reports.last,
          let summary=try JSONSerialization.jsonObject(with:Data(last.utf8)) as? [String:Int],summary["posts"]==10 else { fatalError("Source conflict dispatched or replayed an extra model POST") }
    // Actual installed child carries the original native identity, while its
    // mock completion/reap must leave the native claim unresolved.
    let handoffEpoch=String(repeating:"1",count:32)
    try Data(handoffEpoch.utf8).write(to:directory.appendingPathComponent("native-epoch"))
    let handoffDirectory=directory.appendingPathComponent("handoff-state")
    let handoffJournal=try Journal(directory:handoffDirectory),handoffJob=UUID().uuidString.lowercased()
    let handoffNow=HostResources.nowMilliseconds()
    let handoffSnapshot=NativeSnapshot(host:"fixture-host",endpointHash:hash,nativeEpoch:handoffEpoch,sequence:1,sampledAt:handoffNow,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let handoffBinding=WorkerDispatchBinding(baseURL:base,guardPath:directory.appendingPathComponent("observe.sock").path,host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:epoch,canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:handoffSnapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let handoffPeer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    let handoffSource=FixtureHandoffSource(peer:handoffPeer)
    let handoffBroker=ModelBroker(journal:handoffJournal,factory:factory,handoffSource:handoffSource)
    _=try handoffJournal.reserveJob(DurableJob(id:handoffJob,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:handoffNow))
    try handoffJournal.transitionJob(id:handoffJob,to:.running)
    var handoffAdmission=AdmissionPolicy()
    let beforePreparation=ProcessInfo.processInfo.systemUptime
    try handoffBroker.submit(job:handoffJob,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture handoff")],binding:handoffBinding,nativeCapacityProven:true,sample:resources(handoffNow),admission:&handoffAdmission,now:handoffNow)
    guard ProcessInfo.processInfo.systemUptime-beforePreparation<0.1,
          handoffSource.entered.wait(timeout:.now()+1) == .success,
          try handoffJournal.workerGrants().isEmpty,
          try handoffJournal.inferenceScope(job:handoffJob,attempt:0)?.state == .dispatched else {fatalError("Coordinator blocked or spawned before registration")}
    handoffSource.release.signal()
    guard handoffSource.lineageReady.wait(timeout:.now()+1) == .success else {throw RuntimeError.deadline}
    let handoffScope=try handoffBinding.inferenceScope()
    let diagnostic=NativeRequestLineageSample(peer:handoffPeer,sampledAt:HostResources.nowMilliseconds(),lineage:NativeRequestLineage(instance:handoffEpoch,correlationID:try handoffScope.nativeRequestCorrelationID(job:handoffJob,attempt:0),sampleSequence:3,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:1,preparing:0,active:0,responding:0))
    _=try handoffJournal.observeLineage(job:handoffJob,attempt:0,scope:handoffScope,peer:handoffPeer,sample:diagnostic,now:HostResources.nowMilliseconds())
    var handoffAnswer="",handoffComplete=false
    let handoffDeadline=ProcessInfo.processInfo.systemUptime+10
    while handoffBroker.active(job:handoffJob) && ProcessInfo.processInfo.systemUptime<handoffDeadline {
        let events=try handoffBroker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&handoffAdmission,source:{_ in handoffBinding})
        for event in events[handoffJob] ?? [] {
            if case .text(_,let text)=event {handoffAnswer+=text}
            if case .complete=event {handoffComplete=true}
        }
        Thread.sleep(forTimeInterval:0.01)
    }
    guard handoffComplete,handoffAnswer=="MOCK_ONLY",!handoffBroker.active(job:handoffJob),
          try handoffJournal.activeLaunchCount()==0,try handoffJournal.unresolvedCount()==1,
          try handoffJournal.inferenceScope(job:handoffJob,attempt:0)?.state == .uncertain else {fatalError("Bound coordinator child lost header or cleared native hold")}
    print("PASS: broker durably dispatches before off-loop registration, checkpoints original root before child launch and forwards it on one installed mock POST; completion/reap retains native uncertainty")
    // An actual installed child's guard refuses the changed native epoch before
    // POST. Local reap alone holds the claim; the exact mock unconsumed-root
    // cancellation is then required to resolve only this new request.
    try Data(String(repeating:"2",count:32).utf8).write(to:directory.appendingPathComponent("native-epoch"))
    let zeroState=directory.appendingPathComponent("zero-post-state")
    let zeroJob=UUID().uuidString.lowercased(),zeroTime=HostResources.nowMilliseconds()
    do {
    let zeroJournal=try Journal(directory:zeroState)
    let zeroSource=FixtureHandoffSource(peer:handoffPeer,cancellationState:.cancelled)
    let zeroBroker=ModelBroker(journal:zeroJournal,factory:factory,handoffSource:zeroSource)
    let zeroSnapshot=NativeSnapshot(host:"fixture-host",endpointHash:hash,nativeEpoch:handoffEpoch,sequence:1,sampledAt:zeroTime,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let zeroBinding=WorkerDispatchBinding(baseURL:base,guardPath:directory.appendingPathComponent("observe.sock").path,host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:epoch,canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:zeroSnapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    _=try zeroJournal.reserveJob(DurableJob(id:zeroJob,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:zeroTime))
    try zeroJournal.transitionJob(id:zeroJob,to:.running)
    var zeroAdmission=AdmissionPolicy()
    try zeroBroker.submit(job:zeroJob,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture zero post")],binding:zeroBinding,nativeCapacityProven:true,sample:resources(zeroTime),admission:&zeroAdmission,now:zeroTime)
    guard zeroSource.entered.wait(timeout:.now()+1) == .success else {throw RuntimeError.deadline}
    zeroSource.release.signal()
    var zeroUsage=false,zeroFailure=false
    let zeroDeadline=ProcessInfo.processInfo.systemUptime+10
    while (zeroBroker.active(job:zeroJob) || zeroBroker.nativeNonDispatchPending) && ProcessInfo.processInfo.systemUptime<zeroDeadline {
        let events=try zeroBroker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&zeroAdmission,source:{_ in zeroBinding})
        for event in events[zeroJob] ?? [] {
            if case .usage(let posts,_)=event {guard posts==0 else {fatalError("Refused epoch dispatched a model POST")};zeroUsage=true}
            if case .failed(let code)=event,code=="model_unavailable" {zeroFailure=true}
        }
        Thread.sleep(forTimeInterval:0.01)
    }
    guard zeroUsage,zeroFailure,!zeroBroker.active(job:zeroJob),!zeroBroker.nativeNonDispatchPending,
          try zeroJournal.unresolvedCount()==0,try zeroJournal.requestCount(job:zeroJob)==1,
          try zeroJournal.handoffNonDispatchReceipt(job:zeroJob,attempt:0)?.localProducer == "reaped_zero_post",
          try zeroJournal.handoffNonDispatchReceipt(job:zeroJob,attempt:0)?.grantSHA256 != nil else {fatalError("Zero-post/native closure lost bound grant, decision or spent budget")}
    }
    let zeroReopened=try Journal(directory:zeroState)
    guard try zeroReopened.unresolvedCount()==0,
          try zeroReopened.handoffNonDispatchReceipt(job:zeroJob,attempt:0)?.localProducer == "reaped_zero_post",
          try zeroReopened.requestCount(job:zeroJob)==1 else {fatalError("Reopened zero-post decision lost original producer/budget")}
    print("PASS: installed private child emits verified zero-POST refusal; exact native cancellation plus durable reap records only not_sent with original grant and spent budget across restart")
    let reaped=HostResources.nowMilliseconds()
    try admission.reserveWorker(key:"reaped-one",sample:resources(reaped),now:reaped)
    try admission.reserveWorker(key:"reaped-two",sample:resources(reaped),now:reaped)
    print("PASS: pinned production Python/real private guard/mock HTTP, durable4-call budget,2-worker cap and source-loss revoke/reap with native uncertainty retained; no real inference/native acceptance")
}

private func runNeverSpawnedWorkerTests(factory:PythonWorkerFactory)throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let older=UUID().uuidString.lowercased(),id=UUID().uuidString.lowercased(),contradictory=UUID().uuidString.lowercased(),legacy=UUID().uuidString.lowercased()
    let now=HostResources.nowMilliseconds(),base="http://127.0.0.1:1/v1"
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:"fixture-never-spawned",sequence:1,sampledAt:now,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let scope=try binding.inferenceScope(),started=Int64(ProcessInfo.processInfo.systemUptime*1000)
    func evidence(_ operation:PendingPythonWorker)throws->WorkerNeverSpawnedEvidence {
        let end=ProcessInfo.processInfo.systemUptime+2
        while ProcessInfo.processInfo.systemUptime<end {
            if let result=operation.take() {
                guard case .failure(.neverSpawned(let proof))=result,operation.take()==nil else {throw JournalError.conflict}
                return proof
            }
            Thread.sleep(forTimeInterval:0.005)
        }
        throw RuntimeError.deadline
    }
    do {
        let journal=try Journal(directory:directory)
        try journal.claim(job:older,attempt:0,model:binding.canonicalModel,scope:scope)
        try journal.markDispatched(job:older,attempt:0)
        try journal.markUncertain(job:older,attempt:0)
        try journal.claim(job:id,attempt:0,model:binding.canonicalModel,scope:scope)
        let plan=try journal.planWorkerStart(job:id,attempt:0)
        let foreign=WorkerDispatchBinding(baseURL:base,guardPath:binding.guardPath,host:binding.host,profileHash:String(repeating:"e",count:64),managerEpoch:binding.managerEpoch,canonicalModel:binding.canonicalModel,nativeModel:binding.nativeModel,nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
        do {
            _=try factory.beginStart(binding:foreign,plan:plan,started:started,now:now,initiallyCancelled:true)
            fatalError("NEVER_SPAWNED_PLAN_ACCEPTED_FOREIGN_SCOPE")
        }catch RuntimeError.identity {}
        let operation=try factory.beginStart(binding:binding,plan:plan,started:started,now:now,initiallyCancelled:true)
        do {
            _=try factory.beginStart(binding:binding,plan:plan,started:started,now:now,initiallyCancelled:true)
            fatalError("NEVER_SPAWNED_PLAN_REUSED")
        }catch RuntimeError.identity {}
        let proof=try evidence(operation)
        try journal.markUncertain(job:id,attempt:0)
        for (job,attempt) in [(older,0),(id,1)] {
            do {
                try journal.recordWorkerNeverSpawned(job:job,attempt:attempt,evidence:proof)
                fatalError("NEVER_SPAWNED_EVIDENCE_RELEASED_FOREIGN_ATTEMPT")
            }catch JournalError.conflict {}
        }
        guard try journal.unresolvedCount()==2,try journal.uncertainCount()==2,try journal.activeLaunchCount()==1 else {throw JournalError.conflict}
        try journal.recordWorkerNeverSpawned(job:id,attempt:0,evidence:proof)
        guard try journal.inferenceScope(job:id,attempt:0)?.state == .not_sent,
              try journal.inferenceScope(job:older,attempt:0)?.state == .uncertain,
              try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
              try journal.activeLaunchCount()==0,try journal.workerGrants().isEmpty,
              try journal.requestCount(job:id)==1 else {fatalError("NEVER_SPAWNED_EVIDENCE_CHANGED_OLDER_UNCERTAINTY_OR_REFUNDED_HISTORY")}
        do {
            try journal.recordWorkerNeverSpawned(job:id,attempt:0,evidence:proof)
            fatalError("NEVER_SPAWNED_EVIDENCE_REPLAYED")
        }catch JournalError.conflict {}
        try journal.claim(job:contradictory,attempt:0,model:binding.canonicalModel,scope:scope)
        let otherPlan=try journal.planWorkerStart(job:contradictory,attempt:0)
        let other=try evidence(factory.beginStart(binding:binding,plan:otherPlan,started:started,now:now,initiallyCancelled:true))
        try journal.markDispatched(job:contradictory,attempt:0)
        do {
            try journal.recordWorkerNeverSpawned(job:contradictory,attempt:0,evidence:other)
            fatalError("NEVER_SPAWNED_EVIDENCE_OVERRULED_DISPATCH")
        }catch JournalError.conflict {}
        guard try journal.activeLaunchCount()==1,try journal.unresolvedCount()==2 else {throw JournalError.conflict}
        try journal.markUncertain(job:contradictory,attempt:0)
        try journal.claim(job:legacy,attempt:0,model:binding.canonicalModel,scope:scope)
        let legacyNonce=try journal.planWorkerLaunch(job:legacy,attempt:0)
        try journal.recordWorkerNotStarted(job:legacy,attempt:0,nonce:legacyNonce)
        do {
            _=try journal.planWorkerStart(job:legacy,attempt:0)
            fatalError("DURABLE_REAP_HISTORY_RECONSTRUCTED_LIVE_START_PLAN")
        }catch JournalError.conflict {}
        guard try journal.inferenceScope(job:legacy,attempt:0)?.state == .reserved else {throw JournalError.conflict}
        try journal.markUncertain(job:legacy,attempt:0)
    }
    let reopened=try Journal(directory:directory)
    guard try reopened.inferenceScope(job:id,attempt:0)?.state == .not_sent,
          try reopened.uncertainCount()==3,try reopened.unresolvedCount()==3,
          try reopened.requestCount(job:id)==1 else {throw JournalError.conflict}
    print("PASS: live one-use pre-spawn cancellation records exact not-sent attempt atomically, retaining older native uncertainty and request history; no worker/model POST")
}

// Synthetic native identity only; cancellation must retain its independent claim.
private func runHandoffNeverSpawnedTests(factory:PythonWorkerFactory)throws {
    for independentlyResolved in [false,true] {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds()
    let base="http://127.0.0.1:1/v1",epoch=String(repeating:"1",count:32)
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:epoch,sequence:1,sampledAt:now,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let scope=try binding.inferenceScope(),job=UUID().uuidString.lowercased(),older=UUID().uuidString.lowercased()
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    try journal.claim(job:older,attempt:0,model:scope.canonicalModel,scope:scope)
    try journal.markDispatched(job:older,attempt:0);try journal.markUncertain(job:older,attempt:0)
    try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
    let plan=try journal.planWorkerStart(job:job,attempt:0)
    try journal.markDispatched(job:job,attempt:0)
    do {_=try WorkerHandoffBinding.capture(plan:plan,journal:journal,peer:peer);fatalError("Unobserved native root accepted")}catch RuntimeError.identity {}
    let correlation=try scope.nativeRequestCorrelationID(job:job,attempt:0)
    let sample=NativeRequestLineageSample(peer:peer,sampledAt:now,lineage:NativeRequestLineage(instance:epoch,correlationID:correlation,sampleSequence:1,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:1,preparing:0,active:0,responding:0))
    _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample,now:now)
    let handoff=try WorkerHandoffBinding.capture(plan:plan,journal:journal,peer:peer)
    guard handoff.rootSequence==UInt64.max,handoff.correlationID==correlation else {throw JournalError.conflict}
    do {try handoff.validate(job:older,attempt:0,scope:scope);fatalError("Foreign handoff accepted")}catch RuntimeError.identity {}
    let operation=try factory.beginStart(binding:binding,plan:plan,started:Int64(ProcessInfo.processInfo.systemUptime*1000),now:now,initiallyCancelled:true,handoff:handoff)
    do {_=try factory.withdrawUnstarted(plan:plan,handoff:handoff);fatalError("Consumed factory plan produced withdrawal proof")}catch RuntimeError.identity {}
    let deadline=ProcessInfo.processInfo.systemUptime+2
    var proof:WorkerNeverSpawnedEvidence?
    while ProcessInfo.processInfo.systemUptime<deadline {
        if let result=operation.take() {
            guard case .failure(.neverSpawned(let evidence))=result else {throw JournalError.conflict}
            proof=evidence;break
        }
        Thread.sleep(forTimeInterval:0.005)
    }
    guard let proof else {throw RuntimeError.deadline}
    // Unit-only terminal transition models separately accepted native proof;
    // the worker's no-spawn acknowledgement must neither mint nor undo it.
    if independentlyResolved {try journal.resolveInference(job:job,attempt:0,scope:scope,outcome:.not_sent)}
    try journal.recordWorkerNeverSpawned(job:job,attempt:0,evidence:proof)
    guard try journal.activeLaunchCount()==0,try journal.unresolvedCount()==(independentlyResolved ? 1:2),try journal.uncertainCount()==(independentlyResolved ? 1:2),
          try journal.inferenceScope(job:job,attempt:0)?.state == (independentlyResolved ? .not_sent:.uncertain),
          try journal.inferenceScope(job:older,attempt:0)?.state == .uncertain else {fatalError("Local cancellation cleared native handoff or older uncertainty")}
    do {try journal.recordWorkerNeverSpawned(job:job,attempt:0,evidence:proof);fatalError("Handoff cancellation replay accepted")}catch JournalError.conflict {}
    if !independentlyResolved {
        guard try !journal.resolveClosedHandoff(evidence:.neverSpawned(proof),sample:nil,now:now),
              try journal.unresolvedCount()==2 else {fatalError("Local proof without native cancellation resolved claim")}
        let native=NativeHandoffSample(peer:peer,sampledAt:now,result:NativeHandoffResult(operation:.cancel,instance:epoch,correlationID:correlation,rootSequence:UInt64.max,sampleSequence:2,state:.cancelled,uncertain:false))
        guard try journal.resolveClosedHandoff(evidence:.neverSpawned(proof),sample:native,now:now),
              try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
              try journal.inferenceScope(job:job,attempt:0)?.state == .not_sent,
              try journal.inferenceScope(job:older,attempt:0)?.state == .uncertain,
              try journal.requestCount(job:job)==1,
              try journal.handoffNonDispatchReceipt(job:job,attempt:0)?.localProducer == "never_spawned" else {fatalError("Native closed-handoff proof lost durable receipt or changed older uncertainty/history")}
        do {_=try journal.resolveClosedHandoff(evidence:.neverSpawned(proof),sample:native,now:now);fatalError("Native non-dispatch proof replayed")}catch JournalError.conflict {}
    }
    }
    print("PASS: original full-width native root binds once-only launch; local cancellation preserves both native claims until scoped native cancellation closes only its own not_sent decision")
}

// Held synthetic registration proves manager responsiveness and spawn ordering.
private final class FixtureHandoffSource:NativeHandoffPreparing,@unchecked Sendable {
    let peer:NativeControlPeer
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),lineageReady=DispatchSemaphore(value:0)
    let wrongRoot:Bool
    let lineageUnavailable:Bool
    let cancellationState:NativeHandoffState
    private let counterLock=NSLock()
    private var registrationCount=0
    private var cancellationCount=0
    var registrations:Int {counterLock.lock();defer {counterLock.unlock()};return registrationCount}
    var cancellations:Int {counterLock.lock();defer {counterLock.unlock()};return cancellationCount}
    init(peer:NativeControlPeer,wrongRoot:Bool=false,lineageUnavailable:Bool=false,cancellationState:NativeHandoffState = .handedOff) {self.peer=peer;self.wrongRoot=wrongRoot;self.lineageUnavailable=lineageUnavailable;self.cancellationState=cancellationState}
    func registerHandoff(instance:String,correlationID:String)throws->NativeHandoffSample {
        counterLock.lock();registrationCount+=1;counterLock.unlock()
        entered.signal()
        guard release.wait(timeout:.now()+2) == .success else {throw NativeControlError.deadline}
        return NativeHandoffSample(peer:peer,sampledAt:HostResources.nowMilliseconds(),result:NativeHandoffResult(operation:.register,instance:instance,correlationID:correlationID,rootSequence:UInt64.max,sampleSequence:1,state:.pending,uncertain:false))
    }
    func cancelHandoff(instance:String,correlationID:String,rootSequence:UInt64)throws->NativeHandoffSample {
        counterLock.lock();cancellationCount+=1;counterLock.unlock()
        return NativeHandoffSample(peer:peer,sampledAt:HostResources.nowMilliseconds(),result:NativeHandoffResult(operation:.cancel,instance:instance,correlationID:correlationID,rootSequence:rootSequence,sampleSequence:4,state:cancellationState,uncertain:false))
    }
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample {
        if lineageUnavailable {lineageReady.signal();throw NativeControlError.unavailable}
        let value=NativeRequestLineageSample(peer:peer,sampledAt:HostResources.nowMilliseconds(),lineage:NativeRequestLineage(instance:instance,correlationID:correlationID,sampleSequence:2,rootSequence:wrongRoot ? 7:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:1,preparing:0,active:0,responding:0))
        lineageReady.signal();return value
    }
}

private func runHandoffPreparationFailureTests(factory:PythonWorkerFactory)throws {
    for scenario in [(cancelled:false,wrongRoot:true,lineageUnavailable:false,storageFailure:false,delayedRecovery:false),(cancelled:false,wrongRoot:false,lineageUnavailable:true,storageFailure:false,delayedRecovery:false),(cancelled:true,wrongRoot:false,lineageUnavailable:false,storageFailure:false,delayedRecovery:false),(cancelled:false,wrongRoot:false,lineageUnavailable:true,storageFailure:true,delayedRecovery:true),(cancelled:false,wrongRoot:false,lineageUnavailable:false,storageFailure:true,delayedRecovery:false)] {
        let cancelled=scenario.cancelled
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds()
        let base="http://127.0.0.1:1/v1",epoch=String(repeating:"1",count:32)
        let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:epoch,sequence:1,sampledAt:now,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
        let binding=WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
        let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
        let source=FixtureHandoffSource(peer:peer,wrongRoot:scenario.wrongRoot,lineageUnavailable:scenario.lineageUnavailable)
        let broker=ModelBroker(journal:journal,factory:factory,handoffSource:source)
        let id=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:now))
        try journal.transitionJob(id:id,to:.running)
        var admission=AdmissionPolicy()
        let sample=ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,nativeCapacityProven:true,sample:sample,admission:&admission,now:now)
        guard source.entered.wait(timeout:.now()+1) == .success else {throw RuntimeError.deadline}
        let uptime=Int64(ProcessInfo.processInfo.systemUptime*1000)
        if cancelled {try broker.cancel(job:id,uptime:uptime)}
        let began=ProcessInfo.processInfo.systemUptime
        _=try broker.poll(now:now,uptime:uptime,admission:&admission,source:{_ in binding})
        guard ProcessInfo.processInfo.systemUptime-began<0.1,broker.active(job:id),try journal.workerGrants().isEmpty else {fatalError("Preparation blocked poll or spawned prematurely")}
        // Finite same-process writer contention in this disposable platform
        // journal only. No second manager/app or Fios database is involved.
        var blocker:OpaquePointer?
        defer {if blocker != nil {sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil);sqlite3_close(blocker)}}
        if scenario.storageFailure {
            guard sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path,&blocker,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK,
                  sqlite3_exec(blocker,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        }
        source.release.signal()
        if scenario.storageFailure {
            guard source.lineageReady.wait(timeout:.now()+1) == .success else {throw RuntimeError.deadline}
            var encounteredWrite=false
            let deadline=ProcessInfo.processInfo.systemUptime+3
            while !encounteredWrite && ProcessInfo.processInfo.systemUptime<deadline {
                let start=ProcessInfo.processInfo.systemUptime
                _=try? broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(start*1000),admission:&admission,source:{_ in binding})
                encounteredWrite=ProcessInfo.processInfo.systemUptime-start>=0.8
                if !encounteredWrite {Thread.sleep(forTimeInterval:0.001)}
            }
            guard encounteredWrite,broker.active(job:id),try journal.activeLaunchCount()==1,
                  try journal.workerGrants().isEmpty else {fatalError("PREPARATION_REPLY_LOST_BEFORE_DURABLE_REGISTRATION")}
            guard sqlite3_exec(blocker,"ROLLBACK",nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        }
        let end=ProcessInfo.processInfo.systemUptime+2
        while broker.active(job:id) && ProcessInfo.processInfo.systemUptime<end {
            // Old registration remains identity metadata after the freshness
            // window. This never permits launching from a stale observation.
            _=try broker.poll(now:HostResources.nowMilliseconds()+(scenario.delayedRecovery ? 6000:0),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in binding})
            Thread.sleep(forTimeInterval:0.005)
        }
        guard try journal.originalNativeRoot(job:id,attempt:0,scope:binding.inferenceScope(),peer:peer)==UInt64.max else {fatalError("Lineage failure/cancellation discarded verified original registration")}
        guard !broker.active(job:id),try journal.activeLaunchCount()==0,try journal.workerGrants().isEmpty,
              source.registrations==1,
              try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
              try journal.inferenceScope(job:id,attempt:0)?.state == .uncertain else {fatalError("Preparation failure/cancel spawned or cleared native uncertainty")}
        if cancelled {
            guard try journal.jobs().first(where:{$0.id==id})?.state == .running else {fatalError("Model-only cancellation revoked the whole sandbox job")}
        }
        if scenario.storageFailure {
            guard try journal.jobs().first(where:{$0.id==id})?.state == .revoking else {fatalError("Storage recovery revived job admission")}
        }
    }
    print("PASS: broker lineage failure/cancel and finite writer contention retain one original registration through durable retry and stale-identity storage; no delayed spawn/RPC retry/native release or whole-job model-cancel revocation")
}

private func runUnusedPreparationCancellationTest(factory:PythonWorkerFactory)throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds(),base="http://127.0.0.1:1/v1",epoch=String(repeating:"1",count:32)
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:epoch,sequence:1,sampledAt:now,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/observe.sock",host:snapshot.host,profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let scope=try binding.inferenceScope(),peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    let older=UUID().uuidString.lowercased()
    try journal.claim(job:older,attempt:0,model:scope.canonicalModel,scope:scope)
    try journal.markDispatched(job:older,attempt:0);try journal.markUncertain(job:older,attempt:0)
    let source=FixtureHandoffSource(peer:peer,cancellationState:.cancelled),broker=ModelBroker(journal:journal,factory:factory,handoffSource:source)
    let id=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
    _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:now))
    try journal.transitionJob(id:id,to:.running)
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,nativeCapacityProven:true,sample:sample,admission:&admission,now:now)
    guard source.entered.wait(timeout:.now()+1) == .success else {throw RuntimeError.deadline}
    try broker.cancel(job:id,uptime:Int64(ProcessInfo.processInfo.systemUptime*1000));source.release.signal()
    let end=ProcessInfo.processInfo.systemUptime+3
    while (broker.active(job:id) || broker.nativeNonDispatchPending) && ProcessInfo.processInfo.systemUptime<end {
        _=try broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in binding})
        Thread.sleep(forTimeInterval:0.005)
    }
    guard !broker.active(job:id),!broker.nativeNonDispatchPending,source.registrations==1,source.cancellations==1,
          try journal.inferenceScope(job:id,attempt:0)?.state == .not_sent,
          try journal.inferenceScope(job:older,attempt:0)?.state == .uncertain,
          try journal.unresolvedCount()==1,try journal.uncertainCount()==1,
          try journal.requestCount(job:id)==1,try journal.workerGrants().isEmpty,
          try journal.activeLaunchCount()==0,try journal.jobs().first(where:{$0.id==id})?.state == .running,
          try journal.handoffNonDispatchReceipt(job:id,attempt:0)?.localProducer=="never_spawned" else {fatalError("UNUSED_PREPARATION_NOT_CLOSED_BY_PAIRED_NATIVE_CANCEL")}
    print("PASS: cancelled unused preparation pairs live no-spawn and exact native cancellation, preserving older uncertainty/history and enclosing sandbox job")
}

private func runUnusedFactoryWithdrawalTests(factory:PythonWorkerFactory)throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds(),base="http://127.0.0.1:1/v1",epoch=String(repeating:"1",count:32)
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:epoch,sequence:1,sampledAt:now,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/observe.sock",host:snapshot.host,profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let scope=try binding.inferenceScope(),job=UUID().uuidString.lowercased(),peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"d",count:64)))
    try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
    let plan=try journal.planWorkerStart(job:job,attempt:0);try journal.markDispatched(job:job,attempt:0)
    do {_=try WorkerHandoffBinding.captureForNonDispatch(plan:plan,journal:journal,peer:peer);fatalError("Rootless cleanup binding accepted")}catch RuntimeError.identity {}
    let id=try scope.nativeRequestCorrelationID(job:job,attempt:0)
    let sample=NativeRequestLineageSample(peer:peer,sampledAt:now,lineage:NativeRequestLineage(instance:epoch,correlationID:id,sampleSequence:1,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:1,preparing:0,active:0,responding:0))
    _=try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample,now:now)
    let launch=try WorkerHandoffBinding.capture(plan:plan,journal:journal,peer:peer)
    try journal.markUncertain(job:job,attempt:0)
    do {_=try WorkerHandoffBinding.capture(plan:plan,journal:journal,peer:peer);fatalError("Uncertain scope acquired launch binding")}catch RuntimeError.identity {}
    let cleanup=try WorkerHandoffBinding.captureForNonDispatch(plan:plan,journal:journal,peer:peer)
    do {_=try factory.beginStart(binding:binding,plan:plan,started:Int64(ProcessInfo.processInfo.systemUptime*1000),now:now,handoff:cleanup);fatalError("Cleanup binding started a worker")}catch RuntimeError.identity {}
    let proof=try factory.withdrawUnstarted(plan:plan,handoff:cleanup)
    do {_=try factory.withdrawUnstarted(plan:plan,handoff:cleanup);fatalError("Withdrawal evidence replay accepted")}catch RuntimeError.identity {}
    do {_=try factory.beginStart(binding:binding,plan:plan,started:Int64(ProcessInfo.processInfo.systemUptime*1000),now:now,handoff:launch);fatalError("Withdrawn plan launched through old binding")}catch RuntimeError.identity {}
    try journal.recordWorkerNeverSpawned(job:job,attempt:0,evidence:proof)
    guard try journal.activeLaunchCount()==0,try journal.workerGrants().isEmpty,
          try journal.inferenceScope(job:job,attempt:0)?.state == .uncertain,
          try journal.unresolvedCount()==1,try journal.requestCount(job:job)==1,
          try !journal.resolveClosedHandoff(evidence:.neverSpawned(proof),sample:nil,now:now) else {throw JournalError.conflict}
    print("PASS: cleanup-only original binding cannot launch, withdrawal consumes one unused plan without process and local evidence alone retains native uncertainty/history")
}

private struct FactoryMetadataFixture:Encodable {
    let version:Int
    let pipe_version:Int
    let native_handoff_version:Int
    let package_version:String
    let python_version:String
    let policy_sha256:String
    let policy_input_units:Int
}
