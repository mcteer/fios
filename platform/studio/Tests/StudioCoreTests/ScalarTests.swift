import Foundation
import Darwin

func runScalarTests() throws {
    // Swift String equality normalizes canonically equivalent Unicode. Native
    // model registry/SQLite IDs are byte-exact and must never inherit that alias.
    let composed="org/caf\u{e9}",decomposed="org/cafe\u{301}"
    guard composed == decomposed,!composed.utf8.elementsEqual(decomposed.utf8) else {fatalError("Invalid exact-ID regression fixture")}
    let snapshot=NativeSnapshot(host:"fios-edge-a.lab",endpointHash:String(repeating:"a",count:64),nativeEpoch:"native-fixture",sequence:1,sampledAt:1000,
        allClientLifecycleCoverage:true,residentModel:composed,outstandingOwners:1,loading:false)
    guard try !ActivityPolicy.permits(target:decomposed,snapshot:snapshot,now:1000) else {fatalError("Canonical Unicode equivalence bypassed exact native model guard")}
    guard try ActivityPolicy.permits(target:composed,snapshot:snapshot,now:1000) else {fatalError("Byte-exact same-model sharing rejected")}
    var owners=InferenceOwnership()
    try owners.claim(request:"first",model:composed)
    do {try owners.claim(request:"second",model:decomposed);fatalError("Different UTF-8 model IDs shared an ownership scope")}
    catch PolicyError.conflictingModel {}
    guard WireScalar.integer(NSNumber(value:0))==0,
          WireScalar.integer(NSNumber(value:WireScalar.maximumTimestamp))==WireScalar.maximumTimestamp,
          WireScalar.integer(NSNumber(value:WireScalar.maximumTimestamp+1))==nil,
          WireScalar.integer(NSNumber(value:UInt64.max))==nil,
          WireScalar.integer(NSNumber(value:-1))==nil,
          WireScalar.integer(NSNumber(value:true))==nil,
          WireScalar.integer(NSNumber(value:1.0))==nil else {fatalError("Shared integer bounds/coercion invalid")}
    let uuid="abcdefab-cdef-4abc-8def-abcdefabcdef"
    guard WireScalar.uuid(uuid),!WireScalar.uuid(uuid.uppercased()),!WireScalar.uuid(" "+uuid),
          WireScalar.host(String(repeating:"a",count:128)),!WireScalar.host(String(repeating:"a",count:129)),
          !WireScalar.host("host\u{e9}"),!WireScalar.host("host\u{0}"),
          WireScalar.model(String(repeating:"\u{e9}",count:512)),!WireScalar.model(String(repeating:"\u{e9}",count:513)),
          WireScalar.sha256(String(repeating:"a",count:64)),!WireScalar.sha256(String(repeating:"A",count:64)),
          !WireScalar.sha256(String(repeating:"a",count:63)),!WireScalar.exactModel(composed,decomposed),
          !WireScalar.exactModel(nil,nil),!WireScalar.exactModel("","") else {fatalError("Shared scalar boundaries invalid")}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory.appendingPathComponent("state"))
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let jobs=JobController(journal:journal,executor:UnavailableSandboxRuntime())
    let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("exports"),availableBytes:{100<<30}))
    let sandbox=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,socket:"/fixture/never.sock",peerUID:geteuid())
    let commands=TaskCommands(journal:journal,tasks:tasks,sandbox:sandbox,artifacts:artifacts,approvedImages:[],enrolled:true,peerUID:geteuid(),admissionOpen:{true})
    let binding=WorkerDispatchBinding(baseURL:"http://127.0.0.1:9/v1",guardPath:"/fixture/observe.sock",host:snapshot.host,
        profileHash:String(repeating:"b",count:64),managerEpoch:uuid,canonicalModel:composed,nativeModel:composed,
        nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let payload:[String:Any] = ["owner":TaskOwner.newToken(),"phase":"begin","idempotency":UUID().uuidString.lowercased(),
        "kind":"model","length":0,"sha256":PythonWorkerFactory.digest(""),"lifetime":900000,
        "model":decomposed,"image":NSNull(),"memory":0,"cpus":0]
    let request=try ControlRequest.decode(JSONSerialization.data(withJSONObject:["version":1,"id":UUID().uuidString.lowercased(),"operation":"job.create","payload":payload]))
    let sample=ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:1000)
    var admission=AdmissionPolicy()
    do {_=try commands.handle(request,role:.task,sample:sample,admission:&admission,binding:{_ in binding},nativeCapacityProven:true,now:1000,uptime:1000)
        fatalError("Task model name used canonical Unicode equality to borrow a different grant")}
    catch TaskCommandError.model_unavailable {}
    guard try journal.jobs().isEmpty,try journal.unresolvedCount()==0 else {fatalError("Rejected model alias created durable work")}
    print("PASS: shared canonical UUID/ASCII host/UTF-8 model/lowercase hash/safe-integer scalars and byte-exact model admission/ownership/task grants without Unicode-normalized aliases")
}
