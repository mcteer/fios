import Foundation
import Darwin

// Real installed pipe worker, disposable HTTP mock, synthetic source only.
// A delayed mock response distinguishes post-dispatch source loss from a
// pre-send refusal. Separate journal/admission state, no native model call.
func runBusySourceWorkerTests(directory:URL,factory:PythonWorkerFactory,original:WorkerDispatchBinding,postReports:Int32)throws->Data {
    func readReports()->Data {
        var result=Data(),buffer=[UInt8](repeating:0,count:4096)
        while true {
            let count=Darwin.read(postReports,&buffer,buffer.count)
            if count<=0 {break};result.append(contentsOf:buffer.prefix(count))
            if result.count>4096 {fatalError("Mock count output exceeded bound")}
        }
        return result
    }
    // Prove all earlier healthy requests and pre-send refusals retained their
    // original exact count before this one independent fixture starts.
    let previous=String(decoding:readReports(),as:UTF8.self).split(separator:"\n")
    guard previous.count==9,let last=previous.last,
          (try JSONSerialization.jsonObject(with:Data(last.utf8)) as? [String:Int])?["posts"]==9 else {throw RuntimeError.identity}
    let journal=try Journal(directory:directory),broker=ModelBroker(journal:journal,factory:factory)
    let id=UUID().uuidString.lowercased(),request=UUID().uuidString.lowercased(),owner=String(repeating:"a",count:64)
    let stamp=HostResources.nowMilliseconds()
    _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:String(repeating:"b",count:64),created:stamp))
    try journal.transitionJob(id:id,to:.running,now:stamp)
    func binding(conflict:Bool)->WorkerDispatchBinding {
        let snapshot=NativeSnapshot(host:original.host,endpointHash:original.nativeSnapshot.endpointHash,nativeEpoch:original.nativeSnapshot.nativeEpoch,
            sequence:original.nativeSnapshot.sequence,sampledAt:HostResources.nowMilliseconds(),allClientLifecycleCoverage:true,
            residentModel:conflict ? "fixture/other-model":original.canonicalModel,outstandingOwners:1,loading:false)
        return WorkerDispatchBinding(baseURL:original.baseURL,guardPath:original.guardPath,host:original.host,profileHash:original.profileHash,
            managerEpoch:original.managerEpoch,canonicalModel:original.canonicalModel,nativeModel:original.nativeModel,nativeSnapshot:snapshot,
            nativeCompatibilityAccepted:true,apiKey:nil)
    }
    var admission=AdmissionPolicy()
    let sample=ResourceSample(sampledAt:stamp,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    try broker.submit(job:id,owner:owner,requestID:request,context:[ModelText(role:"user",content:"fixture-source-conflict")],
        binding:binding(conflict:false),nativeCapacityProven:true,sample:sample,admission:&admission,now:stamp)
    var reports=Data(),text=false,complete=false
    let limit=ProcessInfo.processInfo.systemUptime+10
    while !reports.contains(10),ProcessInfo.processInfo.systemUptime<limit {
        let events=try broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in binding(conflict:false)})
        for event in events[id] ?? [] {
            if case .text=event {text=true};if case .complete=event {complete=true}
        }
        reports.append(readReports());Thread.sleep(forTimeInterval:0.005)
    }
    guard let report=try JSONSerialization.jsonObject(with:reports) as? [String:Int],report["posts"]==10,
          broker.activeWorkers==1,!text,!complete else {throw RuntimeError.identity}
    let cleanup=ProcessInfo.processInfo.systemUptime+2
    while broker.activeWorkers>0,ProcessInfo.processInfo.systemUptime<cleanup {
        let events=try broker.poll(now:HostResources.nowMilliseconds(),uptime:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,source:{_ in binding(conflict:true)})
        for event in events[id] ?? [] {
            if case .text=event {text=true};if case .complete=event {complete=true}
        }
        Thread.sleep(forTimeInterval:0.005)
    }
    guard broker.activeWorkers==0,!text,!complete,try journal.workerGrants().isEmpty,
          try journal.jobs().first(where:{$0.id==id})?.state == .revoking,
          try journal.unresolvedRequestIDs()==[request],try journal.uncertainCount()==1 else {
        fatalError("FOREIGN_BUSY_SOURCE_DID_NOT_REVOKE_WITH_ORIGINAL_UNCERTAINTY")
    }
    // Return only the one content-free aggregate already consumed above to
    // the enclosing count assertion; there can be no additional POST.
    guard readReports().isEmpty else {throw RuntimeError.identity}
    print("PASS: post-dispatch foreign busy model revokes/reaps private worker, suppresses text and retains exact native uncertainty; mock only")
    return reports
}
