import Foundation
import Darwin
import CryptoKit

func runServiceAdmissionTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let image="sha256:"+String(repeating:"a",count:64)
    let model=WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"b",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest("http://127.0.0.1:1/v1"),nativeEpoch:"fixture-native",sequence:1,sampledAt:1000,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false),nativeCompatibilityAccepted:true,apiKey:nil)
    let sample=ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:1000)
    func scenario(kind:String,hasModel:Bool,service:ManagedService,desired:ServiceDesired,blocked:Bool,late:Bool)throws {
        let state=directory.appendingPathComponent(UUID().uuidString)
        let journal=try Journal(directory:state),tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
        let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:state.appendingPathComponent("exports"),availableBytes:{100<<30}))
        let sandbox=SandboxTaskController(journal:journal,jobs:JobController(journal:journal,executor:UnavailableSandboxRuntime()),tasks:tasks,artifacts:artifacts,socket:"/fixture/never.sock",peerUID:geteuid())
        let commands=TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[image],enrolled:true,peerUID:geteuid(),admissionOpen:{true})
        var admission=AdmissionPolicy()
        let token=TaskOwner.newToken()
        let data=kind=="model" ? try JSONSerialization.data(withJSONObject:[["role":"user","content":"fixture only"]]):Data("print('fixture')".utf8)
        func call(_ operation:String,_ fields:[String:Any])throws->[String:Any] {
            let request=try ControlRequest.decode(JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":operation,"payload":fields.merging(["owner":token]) {_,new in new}]))
            return try commands.handle(request,role:.task,sample:sample,admission:&admission,binding:{_ in model},nativeCapacityProven:true,now:1000,uptime:1000)
        }
        let begin:[String:Any]=["phase":"begin","idempotency":UUID().uuidString.lowercased(),"kind":kind,"length":data.count,"sha256":SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined(),"lifetime":30000,"model":hasModel ? "fixture/model":NSNull(),"image":kind=="model" ? NSNull():image,"memory":kind=="model" ? 0:512<<20,"cpus":kind=="model" ? 0:1]
        if !late {try journal.setDesired(service:service.rawValue,desired:desired.rawValue)}
        if blocked && !late {
            do {_=try call("job.create",begin);throw RuntimeError.identity}
            catch TaskCommandError.native_unsupported {}catch {
                FileHandle.standardError.write(Data("DURABLE_MAINTENANCE_ADMITTED_WORK\n".utf8));throw error
            }
            guard try journal.jobs().isEmpty,try journal.activeLaunchCount()==0 else {throw JournalError.conflict}
            return
        }
        let created=try call("job.create",begin)
        guard let id=created["job"] as? String else {throw JournalError.invalid}
        if late {
            let operation=kind=="model" ? "model.request":"job.create"
            _=try call(operation,["phase":"chunk","job":id,"index":0,"data":data.base64EncodedString()])
            try journal.setDesired(service:service.rawValue,desired:desired.rawValue)
            do {_=try call(operation,["phase":"end","job":id]);throw RuntimeError.identity}
            catch TaskCommandError.native_unsupported {}catch {
                FileHandle.standardError.write(Data("DURABLE_MAINTENANCE_ACCEPTED_UPLOAD\n".utf8));throw error
            }
            guard let saved=try journal.jobs().first(where:{$0.id==id}),[.revoking,.removed].contains(saved.state),
                  try journal.requestCount(job:id)==0,try journal.activeLaunchCount()==0 else {throw JournalError.conflict}
        }
    }
    for desired:ServiceDesired in [.maintenance,.stopped] {
        try scenario(kind:"model",hasModel:true,service:.mlx,desired:desired,blocked:true,late:false)
        try scenario(kind:"sandbox",hasModel:false,service:.orbstack,desired:desired,blocked:true,late:false)
        try scenario(kind:"sandbox",hasModel:true,service:.mlx,desired:desired,blocked:true,late:false)
        try scenario(kind:"sandbox",hasModel:true,service:.orbstack,desired:desired,blocked:true,late:false)
    }
    try scenario(kind:"sandbox",hasModel:false,service:.mlx,desired:.maintenance,blocked:false,late:false)
    try scenario(kind:"model",hasModel:true,service:.orbstack,desired:.maintenance,blocked:false,late:false)
    try scenario(kind:"model",hasModel:true,service:.mlx,desired:.maintenance,blocked:true,late:true)
    try scenario(kind:"sandbox",hasModel:false,service:.orbstack,desired:.maintenance,blocked:true,late:true)
    let journal=try Journal(directory:directory.appendingPathComponent("broker")),broker=ModelBroker(journal:journal)
    let id=UUID().uuidString.lowercased(),owner=String(repeating:"c",count:64)
    _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"d",count:64),created:1000))
    try journal.transitionJob(id:id,to:.running,now:1000)
    try journal.setDesired(service:"mlx",desired:"maintenance")
    var admission=AdmissionPolicy()
    do {
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture only")],binding:model,nativeCapacityProven:true,sample:sample,admission:&admission,now:1000)
        throw RuntimeError.identity
    }catch AdmissionError.capacity {}catch {
        FileHandle.standardError.write(Data("MAINTENANCE_BROKER_GATE_MISSING\n".utf8));throw error
    }
    guard try journal.unresolvedCount()==0,try journal.activeLaunchCount()==0 else {throw JournalError.conflict}
    print("PASS: durable service maintenance/stopped intent fences new and uploaded work despite cached-open source; independent services preserved and broker entry closes before worker/claim; synthetic sources only")
}
