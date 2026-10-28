import Foundation
import CryptoKit

func runModelBrokerTests() throws {
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let python=root.appendingPathComponent(".venv/bin/python")
    let sha=SHA256.hash(data:try Data(contentsOf:python.resolvingSymlinksInPath())).map {String(format:"%02x",$0)}.joined()
    let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("tests/fixtures/platform/model.json"))) as! [String:Any]
    let factory=try PythonWorkerFactory(invocation:python.path,executableSHA256:sha,policySHA256:fixture["policy_sha256"] as! String)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try Journal(directory:directory),owner=String(repeating:"a",count:64),id=UUID().uuidString.lowercased()
    _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:10_000))
    try journal.transitionJob(id:id,to:.running,now:10_000)
    let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest("http://127.0.0.1:1/v1"),nativeEpoch:"native-fixture-one",sequence:1,sampledAt:10_000,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
    let binding=WorkerDispatchBinding(baseURL:"http://127.0.0.1:1/v1",guardPath:"/fixture/observe.sock",host:"fixture-host",profileHash:String(repeating:"f",count:64),managerEpoch:UUID().uuidString.lowercased(),canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    let sample=ResourceSample(sampledAt:10_000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    let broker=ModelBroker(journal:journal,factory:factory)
    var admission=AdmissionPolicy()
    do {
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,nativeCapacityProven:false,sample:sample,admission:&admission,now:10_000)
        fatalError("Unknown native capacity dispatched")
    } catch AdmissionError.capacity {}
    guard try journal.requestCount(job:id)==0,broker.activeWorkers==0 else { fatalError("Rejected capacity spent permission") }
    do {
        try broker.submit(job:id,owner:owner,requestID:UUID().uuidString.lowercased(),context:[ModelText(role:"user",content:"fixture")],binding:binding,nativeCapacityProven:false,sample:sample,admission:&admission,now:9999)
        fatalError("Clock rollback accepted")
    } catch AdmissionError.expired {}
    guard try journal.jobs().first?.state == .revoking else { fatalError("Broker clock rollback did not durably revoke job") }
    print("PASS: broker owner lease/native-capacity fail-closed and irreversible clock fencing")
}
