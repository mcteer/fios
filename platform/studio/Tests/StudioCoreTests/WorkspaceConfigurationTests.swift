import Foundation
import Darwin
import CryptoKit

// Ordinary configuration flow only. No runtime, model or service is invoked.
private final class WorkspaceUnusedRuntime:SandboxExecuting {
    private(set) var submitted=0
    var active:Int {0}
    func submit(job:String,command:SandboxCommand)throws {submitted+=1;throw RuntimeError.invalid}
    func drain()->[SandboxExecution] {[]}
}

func runWorkspaceConfigurationTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let state=directory.appendingPathComponent("state")
    var requested:[String:UInt64]=[:]
    do {
        let journal=try Journal(directory:state)
        let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
        let runtime=WorkspaceUnusedRuntime()
        let jobs=JobController(journal:journal,executor:runtime)
        let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("exports"),availableBytes:{100<<30}))
        let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,socket:"/fixture/unused.sock",peerUID:geteuid())
        let image="sha256:"+String(repeating:"a",count:64),token=TaskOwner.newToken()
        let commands=TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[image],enrolled:true,peerUID:geteuid(),admissionOpen:{true})
        var admission=AdmissionPolicy()
        let sample=ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:1000)
        let source=Data("print('ordinary workspace configuration')".utf8)
        for workspace:UInt64 in [128<<20,256<<20] {
            var fields:[String:Any]=["owner":token,"phase":"begin","idempotency":UUID().uuidString.lowercased(),"kind":"sandbox","length":source.count,"sha256":SHA256.hash(data:source).map{String(format:"%02x",$0)}.joined(),"lifetime":900000,"model":NSNull(),"image":image,"memory":512<<20,"cpus":1]
            if workspace != 128<<20 {fields["workspace"]=workspace}
            let request=try ControlRequest.decode(JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":"job.create","payload":fields]))
            let result=try commands.handle(request,role:.task,sample:sample,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:1000,uptime:1)
            guard let id=result["job"] as? String else {throw JournalError.invalid}
            let replay=try commands.handle(request,role:.task,sample:sample,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:1000,uptime:1)
            guard replay["job"] as? String==id else {throw JournalError.invalid}
            requested[id]=workspace
            let record=try journal.sandboxRecords().first{$0.configuration.job==id}!
            guard record.configuration.createArguments.contains("--tmpfs=/workspace:rw,nosuid,nodev,size=\(workspace),mode=0700,uid=65532,gid=65532"),
                  !record.createIssued,record.runtimeID==nil else {throw JournalError.invalid}
            let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(record.configuration)) as! [String:Any]
            if workspace==128<<20 {guard encoded["workspace"]==nil else {throw JournalError.invalid}}
        }
        guard runtime.submitted==0 else {throw JournalError.invalid}
    }
    // The first journal and controllers are gone before reopening the state.
    do {
        let journal=try Journal(directory:state)
        for record in try journal.sandboxRecords() {
            guard let workspace=requested[record.configuration.job],
                  record.configuration.createArguments.contains("--tmpfs=/workspace:rw,nosuid,nodev,size=\(workspace),mode=0700,uid=65532,gid=65532"),
                  !record.createIssued else {throw JournalError.invalid}
        }
        guard try journal.sandboxRecords().count==2 else {throw JournalError.invalid}
    }
    print("PASS: ordinary default128MiB and requested256MiB workspace configuration persists without runtime execution")
}
