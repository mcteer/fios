import Foundation

// Synthetic trusted-binding inputs only; no native contract or lease is issued.
func runNativeAdmissionBindingTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory)
    let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal))
    let base="http://127.0.0.1:1/v1",host="fixture-host",hash=PythonWorkerFactory.digest("http://127.0.0.1:1/v1")
    let epoch=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
    func binding(host observedHost:String,hash observedHash:String,resident:String?=nil,owners:Int=0,loading:Bool=false,coverage:Bool=true)->WorkerDispatchBinding {
        let snapshot=NativeSnapshot(host:observedHost,endpointHash:observedHash,nativeEpoch:"fixture-native",sequence:1,sampledAt:1000,
            allClientLifecycleCoverage:coverage,residentModel:resident,outstandingOwners:owners,loading:loading)
        return WorkerDispatchBinding(baseURL:base,guardPath:"/fixture/observe.sock",host:host,profileHash:String(repeating:"b",count:64),
            managerEpoch:epoch,canonicalModel:"fixture/model",nativeModel:"fixture/model",nativeSnapshot:snapshot,nativeCompatibilityAccepted:true,apiKey:nil)
    }
    let sample=ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,cpuSampledAt:1000)
    var admission=AdmissionPolicy()
    let partial=binding(host:host,hash:hash,coverage:false)
    guard try !NativeAdmission.retainsSource(partial,now:1000),try !NativeAdmission.permitsDispatch(partial,now:1000) else {
        fatalError("Coherent but partial idle source gained native authority")
    }
    for candidate in [binding(host:"other-fixture-host",hash:hash),binding(host:host,hash:String(repeating:"c",count:64)),partial] {
        do {
            _=try tasks.reserveModelUpload(owner:owner,idempotency:UUID().uuidString.lowercased(),requestHash:String(repeating:"d",count:64),
                binding:candidate,nativeCapacityProven:true,sample:sample,admission:&admission,now:1000)
            fatalError("NATIVE_ADMISSION_FOREIGN_SOURCE_RESERVED_JOB")
        }catch AdmissionError.capacity {}
        guard try journal.jobs().isEmpty,try journal.unresolvedCount()==0 else {fatalError("Foreign source changed durable ownership")}
    }
    let accepted=try tasks.reserveModelUpload(owner:owner,idempotency:UUID().uuidString.lowercased(),requestHash:String(repeating:"d",count:64),
        binding:binding(host:host,hash:hash),nativeCapacityProven:true,sample:sample,admission:&admission,now:1000)
    guard accepted.state == .reserved,try journal.jobs().count==1,try journal.unresolvedCount()==0 else {throw PolicyError.invalidObservation}
    let foreign=binding(host:host,hash:hash,resident:"fixture/other-model",owners:1)
    guard !(try NativeAdmission.retainsSource(foreign,now:1000)) else {
        fatalError("NATIVE_SOURCE_ACCEPTED_FOREIGN_BUSY_MODEL")
    }
    // Loading must not hide a conflicting or unidentified outstanding owner.
    for resident in ["fixture/other-model", nil] as [String?] {
        guard !(try NativeAdmission.retainsSource(binding(host:host,hash:hash,resident:resident,owners:1,loading:true),now:1000)) else {
            fatalError("NATIVE_SOURCE_LOADING_MASKED_OUTSTANDING_OWNER")
        }
    }
    guard try NativeAdmission.retainsSource(binding(host:host,hash:hash,resident:"fixture/other-model",owners:0,loading:true),now:1000),
          try NativeAdmission.retainsSource(binding(host:host,hash:hash,resident:"fixture/model",owners:1,loading:true),now:1000) else {
        fatalError("NATIVE_SOURCE_REJECTED_NONCONFLICTING_PREPARATION")
    }
    guard try NativeAdmission.retainsSource(binding(host:host,hash:hash,resident:"fixture/model",owners:1),now:1000),
          try NativeAdmission.retainsSource(binding(host:host,hash:hash,loading:true),now:1000),
          try NativeAdmission.retainsSource(binding(host:host,hash:hash),now:1000) else {throw PolicyError.invalidObservation}
    print("PASS: selected host/endpoint source binding refuses before durable job reservation; coherent synthetic upload remains available")
}
