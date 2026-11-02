import Foundation

func runSandboxSourceIdentityTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),manager=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
    let controller=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    func binding(_ epoch:String)->WorkerDispatchBinding {
        let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:String(repeating:"b",count:64),nativeEpoch:epoch,sequence:1,sampledAt:1000,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
        return WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"c",count:64),managerEpoch:manager,canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    }
    func registered(_ epoch:String)throws->(String,String) {
        let id=UUID().uuidString.lowercased(),runtime=String(repeating:"d",count:64)
        let config=try SandboxConfiguration(job:id,nonce:String(repeating:"e",count:64),image:"sha256:"+String(repeating:"f",count:64),memory:512<<20,cpus:1)
        _=try journal.reserveSandbox(job:DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"f",count:64),created:1000),configuration:config)
        let lifecycle=SandboxLifecycle(journal:journal)
        _=try lifecycle.next(job:id,now:1000,resourcesSafe:true)
        try lifecycle.created(job:id,runtimeID:runtime)
        _=try lifecycle.observed(job:id,presence:.present(id:runtime,name:"/"+config.name,image:config.image,nonce:config.nonce,running:false),now:1000,resourcesSafe:true)
        _=try lifecycle.observed(job:id,presence:.present(id:runtime,name:"/"+config.name,image:config.image,nonce:config.nonce,running:true),now:1000,resourcesSafe:true)
        try controller.registerSandbox(id:id,owner:owner,runtimeID:runtime,binding:binding(epoch))
        return(id,runtime)
    }
    let original="native/café",foreign="native/cafe\u{301}"
    guard original==foreign,Data(original.utf8) != Data(foreign.utf8) else {throw RuntimeError.invalid}
    let frame=try JSONSerialization.data(withJSONObject:["version":1,"type":"model.request","id":UUID().uuidString.lowercased(),"prompt":"fixture only"])
    let first=try registered(original)
    do {
        try controller.sandboxModelFrame(id:first.0,runtimeID:first.1,data:frame,binding:binding(foreign),nativeCapacityProven:false,sample:sample,admission:&admission,now:1000,uptime:1000)
        throw RuntimeError.identity
    }catch ControlError.unauthorized {}catch {
        FileHandle.standardError.write(Data("SANDBOX_NORMALIZED_NATIVE_EPOCH\n".utf8));throw error
    }
    guard try journal.requestCount(job:first.0)==0,try journal.jobs().first(where:{$0.id==first.0})?.state == .revoking else {throw JournalError.conflict}
    let second=try registered(original)
    do {
        try controller.sandboxModelFrame(id:second.0,runtimeID:second.1,data:frame,binding:binding(original),nativeCapacityProven:false,sample:sample,admission:&admission,now:1000,uptime:1000)
        throw RuntimeError.identity
    }catch PolicyError.invalidObservation {} // Exact source reaches the absent factory, never a POST.
    guard try journal.requestCount(job:second.0)==0,try journal.unresolvedCount()==0 else {throw JournalError.conflict}
    print("PASS: actual sandbox-frame entry byte-binds native source before parser/broker dispatch; changed source revokes without claim, exact source reaches closed factory; synthetic runtime only")
}
