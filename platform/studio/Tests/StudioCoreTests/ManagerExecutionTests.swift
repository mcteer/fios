import Foundation
import Darwin
import CryptoKit

func runManagerExecutionTests()throws {
    let path="/usr/bin/false",hash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let runtime=try DockerRuntime(executable:VerifiedExecutable(path:path,sha256:hash),socket:"/fixture/never.sock")
    let image="sha256:"+String(repeating:"a",count:64)
    for images:Set<String> in [[],["fios:current"],Set((0..<9).map {"sha256:"+String(repeating:String($0),count:64)})] {
        do {
            _=try ManagerExecutionPorts(runtime:runtime,approvedImages:images,resources:{_,_ in nil})
            fatalError("Invalid manager execution configuration accepted")
        } catch RuntimeError.invalid {}
    }
    let ports=try ManagerExecutionPorts(runtime:runtime,approvedImages:[image],resources:{_,_ in nil})
    let unknown=ports.sample(now:1000,cpu:10)
    guard unknown.sampledAt==1000,unknown.available==nil,unknown.vmAvailable==nil,
          unknown.cpu==nil,unknown.diskFree==nil,unknown.pressure == .unknown,
          !ports.admissionOpen(),!ports.nativeCapacityProven(),ports.binding("fixture",managerEpoch:UUID().uuidString.lowercased())==nil else {fatalError("Missing manager source gained capacity or authority")}
    let value=ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    let unavailable=try ManagerExecutionPorts(runtime:runtime,approvedImages:[image],resources:{_,_ in value})
    let cached=try ManagerExecutionPorts(runtime:runtime,approvedImages:[image],vmSource:.cached,resources:{_,_ in value})
    guard unavailable.sample(now:1000,cpu:10).vmAvailable==nil,
          cached.sample(now:1000,cpu:10).vmAvailable==8<<30,
          !cached.admissionOpen(),!cached.nativeCapacityProven() else {fatalError("VM numbers implicitly selected a source or granted native admission")}
    let current=UUID().uuidString.lowercased(),old=UUID().uuidString.lowercased(),base="http://127.0.0.1:1/v1"
    func bound(_ epoch:String,canonical:String="fixture/model",native:String?=nil)->WorkerDispatchBinding {
        let snapshot=NativeSnapshot(host:"fixture-host",endpointHash:PythonWorkerFactory.digest(base),nativeEpoch:"fixture-native",sequence:1,sampledAt:1000,allClientLifecycleCoverage:true,residentModel:nil,outstandingOwners:0,loading:false)
        return WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/never.sock",host:"fixture-host",profileHash:String(repeating:"a",count:64),managerEpoch:epoch,canonicalModel:canonical,nativeModel:native ?? canonical,nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    }
    let stale=try ManagerExecutionPorts(runtime:runtime,approvedImages:[image],resources:{_,_ in nil},binding:{_,_ in bound(old)})
    let fresh=try ManagerExecutionPorts(runtime:runtime,approvedImages:[image],resources:{_,_ in nil},binding:{_,epoch in bound(epoch)})
    guard stale.binding("fixture/model",managerEpoch:current)==nil else {fatalError("Stale manager generation binding accepted")}
    guard fresh.binding("foreign/model",managerEpoch:current)==nil else {fatalError("Mismatched canonical model binding accepted")}
    guard fresh.binding("fixture/model",managerEpoch:current)?.managerEpoch==current else {fatalError("Current manager generation binding rejected")}
    let composed="fixture/caf\u{00e9}",decomposed="fixture/cafe\u{0301}"
    guard composed==decomposed else {fatalError("Fixture must reproduce Swift canonical equivalence")}
    guard ModelBroker.scopeIdentity(bound(current,canonical:composed)) != ModelBroker.scopeIdentity(bound(current,canonical:decomposed)),
          ModelBroker.scopeIdentity(bound(current,native:composed)) != ModelBroker.scopeIdentity(bound(current,native:decomposed)) else {fatalError("Canonical Unicode equivalence bypassed broker scope identity")}
    let executor=try ports.makeExecutor()
    guard executor.active==0 else {fatalError("Manager construction dispatched runtime work")}
    print("PASS: bounded code-only manager composition, immutable image declarations, unavailable cached sources stay unknown and all execution/admission defaults closed; no daemon call")
}
