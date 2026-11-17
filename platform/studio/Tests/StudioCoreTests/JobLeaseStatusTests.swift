import Foundation
import Darwin

private final class LeaseDisplayRuntime:SandboxExecuting {
    var calls=0
    var active:Int {0}
    func submit(job:String,command:SandboxCommand)throws {calls+=1;throw SandboxExecutionFailure.unavailable}
    func drain()->[SandboxExecution] {[]}
}
func runJobLeaseStatusTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory.appendingPathComponent("state"))
    let token=TaskOwner.newToken(),owner=try TaskOwner(token:token,peerUID:geteuid()).hash
    let job=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),
        ownerHash:owner,requestHash:String(repeating:"b",count:64),created:1000)
    _=try journal.reserveJob(job)
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal)),runtime=LeaseDisplayRuntime()
    let jobs=JobController(journal:journal,executor:runtime)
    let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("exports"),availableBytes:{50<<30}))
    let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,socket:"/fixture/unused.sock",peerUID:geteuid())
    let commands=TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[],peerUID:geteuid())
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:1000,physical:24<<30,available:16<<30,vmAvailable:nil,diskFree:50<<30,cpu:10,pressure:.normal,thermal:.nominal)
    func call(_ operation:String,_ now:Int64,id:String?=nil)throws->[String:Any] {
        let request=try ControlRequest.decode(JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),
            "operation":operation,"payload":["owner":token,"job":id ?? job.id]]))
        let response=try commands.handle(request,role:.task,sample:sample,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:now,uptime:now)
        let bytes=try JSONSerialization.data(withJSONObject:response)
        guard let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {throw JournalError.invalid}
        return value
    }
    func lease(_ response:[String:Any])throws->[String:Any] {
        guard let value=response["lease"] as? [String:Any] else {
            throw NSError(domain:"JobLeaseStatus",code:1,userInfo:[NSLocalizedDescriptionKey:"Job status does not report its lease times"])
        }
        return value
    }
    let first=try lease(call("job.status",5000))
    guard first["created_at"] as? Int64 == 1000,first["expires_at"] as? Int64 == 31000,
          first["deadline_at"] as? Int64 == 901000,first["sampled_at"] as? Int64 == 5000,
          first["revoked"] as? Bool == false else {throw JournalError.invalid}
    let read=try lease(call("job.status",6000))
    guard read["expires_at"] as? Int64 == 31000 else {throw JournalError.invalid}
    let renewed=try lease(call("job.renew",20000))
    guard renewed["expires_at"] as? Int64 == 50000,renewed["deadline_at"] as? Int64 == 901000 else {throw JournalError.invalid}
    let cancelled=try lease(call("job.cancel",22000))
    guard cancelled["revoked"] as? Bool == true,cancelled["expires_at"] as? Int64 == 50000,
          runtime.calls==0 else {throw JournalError.invalid}
    let late=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),
        ownerHash:owner,requestHash:String(repeating:"c",count:64),created:23000)
    _=try journal.reserveJob(late);try journal.transitionJob(id:late.id,to:.running)
    try commands.tick(now:24000,uptime:24000,artifactResults:[],model:[late.id:[.text(kind:"text",content:"Hello")]])
    let delayed=try call("job.status",27001,id:late.id)
    guard let current=try journal.jobs().first(where:{$0.id==late.id}),
          delayed["state"] as? String == current.state.rawValue else {
        throw NSError(domain:"JobLeaseStatus",code:2,userInfo:[NSLocalizedDescriptionKey:"Output timeout response reports an earlier job state"])
    }
    guard delayed["output_lost"] as? Bool == true,
          try lease(delayed)["revoked"] as? Bool == current.lease.revoked,
          runtime.calls==0 else {throw JournalError.invalid}
    print("PASS: ordinary job status reports lease expiry, renewal and cancellation without extending reads")
}
