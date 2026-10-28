import Foundation
import Darwin
import CryptoKit

private final class NeverRuntime:SandboxExecuting {
    var active:Int {0}
    func submit(job:String,command:SandboxCommand) throws {throw SandboxExecutionFailure.unavailable}
    func drain()->[SandboxExecution] {[]}
}
func runComposedPressureTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let cases:[(String,ResourceSample)]=[
        ("critical",ResourceSample(sampledAt:6000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.critical,thermal:.nominal)),
        ("stale",ResourceSample(sampledAt:0,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)),
        ("thermal",ResourceSample(sampledAt:6000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.serious))
    ]
    for (name,sample) in cases {
        let state=directory.appendingPathComponent(name)
        let journal=try Journal(directory:state)
        let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
        let jobs=JobController(journal:journal,executor:NeverRuntime())
        let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:state.appendingPathComponent("exports"),availableBytes:{100<<30}))
        let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,socket:"/fixture/never.sock",peerUID:geteuid())
        var ids:[String]=[],admission=AdmissionPolicy()
        for index in 0..<2 {
            let id=UUID().uuidString.lowercased();ids.append(id)
            _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:1000+Int64(index)))
            try journal.transitionJob(id:id,to:.running)
        }
        try journal.claim(job:ids[1],attempt:0,model:"fixture-model")
        try journal.markUncertain(job:ids[1],attempt:0)
        _=try sandbox.tick(now:6000,uptime:6,sample:sample,admission:&admission,source:{_ in nil},nativeCapacityProven:false)
        guard try journal.jobs().first(where:{$0.id==ids[1]})?.state == .removed,
              try journal.jobs().first(where:{$0.id==ids[0]})?.state == .running,
              try journal.unresolvedCount()==1 else {fatalError("Composed pressure cleanup lost global order/native uncertainty: "+name)}
        do {try admission.reserveWorker(key:"blocked",sample:sample,now:6000);fatalError("Unsafe telemetry left worker admission open")}catch AdmissionError.capacity{}catch AdmissionError.stale{}
    }
    print("PASS: composed critical/stale/thermal host pressure cancels newest model-only job through owner controller, closes admission and preserves native uncertainty")
}

func runTaskCommandTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory.appendingPathComponent("state"))
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let jobs=JobController(journal:journal,executor:NeverRuntime())
    let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("exports"),availableBytes:{100<<30}))
    let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,socket:"/fixture/never.sock",peerUID:geteuid())
    let image="sha256:"+String(repeating:"a",count:64),token=TaskOwner.newToken(),foreign=TaskOwner.newToken()
    let disabled=TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[image],peerUID:geteuid())
    var open=true
    let commands=TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[image],enrolled:true,peerUID:geteuid(),admissionOpen:{open})
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    func request(_ operation:String,_ fields:[String:Any],_ auth:String?=nil) throws -> ControlRequest {
        try ControlRequest.decode(JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":operation,"payload":fields.merging(["owner":auth ?? token]) {_,new in new}]))
    }
    func call(_ operation:String,_ fields:[String:Any],auth:String?=nil,now:Int64=1000) throws->[String:Any] {
        try commands.handle(request(operation,fields,auth),role:.task,sample:sample,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:now,uptime:1000)
    }
    let source=Data("print('fixture')".utf8),key=UUID().uuidString.lowercased()
    let begin:[String:Any]=["phase":"begin","idempotency":key,"kind":"sandbox","length":source.count,"sha256":SHA256.hash(data:source).map {String(format:"%02x",$0)}.joined(),"lifetime":900000,"model":NSNull(),"image":image,"memory":512<<20,"cpus":1]
    do {_=try disabled.handle(request("job.create",begin),role:.task,sample:sample,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:1000,uptime:1000);fatalError("Unenrolled task API admitted work")} catch TaskCommandError.native_unsupported {}
    guard try journal.jobs().isEmpty else {fatalError("Closed activation created durable work")}
    do {_=try commands.handle(request("job.create",begin),role:.operator,sample:sample,admission:&admission,binding:{_ in nil},nativeCapacityProven:false,now:1000,uptime:1000);fatalError("Operator implicitly gained task role")} catch TaskCommandError.unauthorized {}
    open=false
    do {_=try call("job.create",begin);fatalError("Source-loss admission remained open")} catch TaskCommandError.native_unsupported {}
    open=true
    let created=try call("job.create",begin)
    guard let id=created["job"] as? String,created["state"] as? String=="reserved",try journal.requestCount(job:id)==0 else {fatalError("Task input reservation dispatched")}
    do {_=try call("job.status",["job":id],auth:foreign);fatalError("Foreign owner read job")} catch TaskCommandError.unauthorized {}
    _=try call("job.create",["phase":"chunk","job":id,"index":0,"data":source.base64EncodedString()],now:1001)
    _=try call("job.create",["phase":"end","job":id],now:1002)
    _=try call("job.create",["phase":"end","job":id],now:1003)
    guard try journal.requestCount(job:id)==0 else {fatalError("Upload replay dispatched a model")}
    let opaque=try JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":"service.desired","payload":["service":"mlx","desired":"stopped"]])
    try commands.tick(now:1003,uptime:1003,artifactResults:[],output:[SandboxTaskOutput(job:id,stream:"stdout",data:opaque)])
    do {_=try call("job.status",["job":id],auth:foreign,now:1003);fatalError("Foreign owner consumed output")} catch TaskCommandError.unauthorized {}
    let firstEvent=try call("job.status",["job":id],now:1003)["event"] as? [String:Any]
    guard firstEvent?["data"] as? String==opaque.base64EncodedString(),firstEvent?["event_index"] as? Int==0 else {fatalError("Task output was interpreted or lost")}
    guard try journal.desired(service:"mlx")=="running" else {fatalError("Generated management envelope gained authority")}
    try commands.tick(now:1003,uptime:1003,artifactResults:[],model:[id:[.text(kind:"answer",content:"opaque model output")]])
    let modelEvent=try call("job.status",["job":id],now:1003)["event"] as? [String:Any]
    guard modelEvent?["content"] as? String=="opaque model output",modelEvent?["event_index"] as? Int==1 else {fatalError("Draining output reset ordinal")}
    try commands.tick(now:1003,uptime:1003,artifactResults:[],output:Array(repeating:SandboxTaskOutput(job:id,stream:"stdout",data:opaque),count:65))
    let lost=try call("job.status",["job":id],now:1003)
    guard lost["output_lost"] as? Bool==true,lost["event"]==nil,try journal.jobs().first?.state == .revoking else {fatalError("Backpressure did not irreversibly revoke task")}
    try commands.tick(now:1003,uptime:1003,artifactResults:[],output:[SandboxTaskOutput(job:id,stream:"stdout",data:opaque)])
    guard try call("job.status",["job":id],now:1003)["event"]==nil else {fatalError("Lost output mailbox revived")}
    _=try call("job.cancel",["job":id],now:1004)
    guard try journal.jobs().first?.state == .revoking else {fatalError("Sandbox cancel declared premature absence")}
    let publication=UUID().uuidString.lowercased(),owner=try TaskOwner(token:token,peerUID:geteuid()).hash
    try artifacts.publish(request:publication,job:id,owner:owner,data:source,now:1005)
    func wait()throws->[ArtifactServiceResult] {
        let deadline=ProcessInfo.processInfo.systemUptime+3
        while ProcessInfo.processInfo.systemUptime<deadline {
            let result=artifacts.drain();if !result.isEmpty {return result};Thread.sleep(forTimeInterval:0.005)
        }
        throw RuntimeError.deadline
    }
    guard case .success(.published(let artifact))=try wait()[0].result else {fatalError("Fixture artifact failed")}
    let started=try call("artifact.read",["phase":"begin","artifact":artifact],now:1006)
    guard let stream=started["stream"] as? String else {fatalError("No finite download handle")}
    try commands.tick(now:1007,uptime:1007,artifactResults:wait())
    do {_=try call("artifact.read",["phase":"next","stream":stream],auth:foreign,now:1008);fatalError("Foreign owner used download handle")} catch TaskCommandError.unauthorized {}
    guard try call("artifact.read",["phase":"next","stream":stream],now:1008)["type"] as? String=="begin",
          try call("artifact.read",["phase":"next","stream":stream],now:1009)["data"] as? String==source.base64EncodedString(),
          try call("artifact.read",["phase":"next","stream":stream],now:1010)["type"] as? String=="end" else {fatalError("Owner artifact stream invalid")}
    do {_=try call("artifact.read",["phase":"next","stream":stream],now:1011);fatalError("Consumed artifact stream revived")} catch TaskCommandError.unauthorized {}
    print("PASS: task-role/opaque-owner API, closed/source-loss admission, reserve-before-input, once-only validation, proof-gated cancel and asynchronous owner-only finite artifact routing")
}
