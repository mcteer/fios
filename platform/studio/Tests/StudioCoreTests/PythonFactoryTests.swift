import Foundation
import CryptoKit
import Darwin

func runPythonFactoryTests() throws {
    func progress(_ phase:String) {FileHandle.standardError.write(Data(("Python factory fixture: "+phase+"\n").utf8))}
    progress("begin")
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let invocation=root.appendingPathComponent(".venv/bin/python")
    let executable=invocation.resolvingSymlinksInPath()
    let sha=SHA256.hash(data:try Data(contentsOf:executable)).map {String(format:"%02x",$0)}.joined()
    let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("tests/fixtures/platform/model.json"))) as! [String:Any]
    progress("metadata begin")
    let factory=try PythonWorkerFactory(invocation:invocation.path,executableSHA256:sha,policySHA256:fixture["policy_sha256"] as! String)
    progress("metadata ready")
    guard factory.metadata.policy_input_units==fixture["policy_input_units"] as? Int else { fatalError("Installed policy units diverged from cross-language fixture") }
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
    for _ in 0..<4 {
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
    guard broker.activeWorkers==0,try journal.unresolvedCount()==2,try journal.workerGrants().isEmpty,
          try journal.jobs().filter({active.contains($0.id)}).allSatisfy({$0.state == .revoking}) else { fatalError("Source loss did not revoke/reap without clearing native uncertainty") }
    progress("source-loss workers reaped")
    // Mock fixture reports only aggregate POST counts, never headers/prompts.
    var counts=Data()
    while true {
        var bytes=[UInt8](repeating:0,count:4096)
        let n=Darwin.read(fd,&bytes,bytes.count)
        if n<=0 { break };counts.append(contentsOf:bytes.prefix(n))
        guard counts.count<4096 else { throw RuntimeError.outputLimit }
    }
    let reports=String(decoding:counts,as:UTF8.self).split(separator:"\n")
    guard reports.count==9,let last=reports.last,
          let summary=try JSONSerialization.jsonObject(with:Data(last.utf8)) as? [String:Int],summary["posts"]==9 else { fatalError("Pre-send source loss dispatched or replayed a model POST") }
    let reaped=HostResources.nowMilliseconds()
    try admission.reserveWorker(key:"reaped-one",sample:resources(reaped),now:reaped)
    try admission.reserveWorker(key:"reaped-two",sample:resources(reaped),now:reaped)
    print("PASS: pinned production Python/real private guard/mock HTTP, durable4-call budget,2-worker cap and source-loss revoke/reap with native uncertainty retained; no real inference/native acceptance")
}
