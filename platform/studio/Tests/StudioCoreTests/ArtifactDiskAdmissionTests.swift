import Foundation

func runArtifactDiskAdmissionTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("fios-artifact-disk-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)}
    let owner=String(repeating:"a",count:64),debt:UInt64=16<<20,floor:UInt64=10<<30
    let record:[String:Any]=["id":UUID().uuidString.lowercased(),"job":UUID().uuidString.lowercased(),"ownerHash":owner,"created":1000,"bytes":Int(debt),"sha256":String(repeating:"0",count:64),"state":"failed"]
    try AtomicState.write(JSONSerialization.data(withJSONObject:["version":1,"records":[record]]),to:root.appendingPathComponent("index.json"))
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    let store=try ArtifactStore(directory:root,availableBytes:{entered.signal();release.wait();return floor+debt})
    let service=AsyncArtifacts(store:store)
    func sample(_ disk:UInt64)->ResourceSample {
        ResourceSample(sampledAt:1000,physical:128<<30,available:64<<30,vmAvailable:8<<30,diskFree:disk,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:1000)
    }
    func workerDenied(_ value:ResourceSample)throws {
        var policy=AdmissionPolicy()
        do {try policy.reserveWorker(key:"disk",sample:value,now:1000);fatalError("Artifact disk commitments ignored at admission")}catch AdmissionError.capacity{}
    }
    let exact=service.reservingDisk(in:sample(floor+debt))
    guard exact.diskCommitted==debt,exact.diskFree==floor+debt,
          exact.replacingVM(4<<30).diskCommitted==debt else {fatalError("Disk debt lost or raw sensor overwritten")}
    var policy=AdmissionPolicy()
    try policy.reserveWorker(key:"exact",sample:exact,now:1000)
    try workerDenied(service.reservingDisk(in:sample(floor+debt-1)))
    guard service.reservingDisk(in:exact).diskCommitted==debt else {fatalError("Same artifact debt double-counted on snapshot refresh")}
    var excessive=sample(UInt64.max);excessive.diskCommitted=UInt64.max
    try workerDenied(excessive)
    let first=UUID().uuidString.lowercased(),second=UUID().uuidString.lowercased()
    try service.publish(request:first,job:UUID().uuidString.lowercased(),owner:owner,data:Data([1]),now:1001)
    guard entered.wait(timeout:.now()+2) == .success else {fatalError("Bounded publication fixture never entered")}
    try service.publish(request:second,job:UUID().uuidString.lowercased(),owner:owner,data:Data([2]),now:1001)
    // First publication is blocked before its durable record; second is queued.
    // Both byte declarations must be visible BEFORE off-loop work completes.
    guard service.reservingDisk(in:sample(floor+debt)).diskCommitted==debt+2 else {fatalError("Queued publication bytes not reserved atomically")}
    try workerDenied(service.reservingDisk(in:sample(floor+debt)))
    release.signal();release.signal()
    let deadline=ProcessInfo.processInfo.systemUptime+3
    var results:[ArtifactServiceResult]=[]
    while results.count<2 && ProcessInfo.processInfo.systemUptime<deadline {results+=service.drain();Thread.sleep(forTimeInterval:0.001)}
    guard results.count==2 else {fatalError("Publication result was lost")}
    for result in results {guard case .failure(.capacity)=result.result else {fatalError("Disk-short publication was not refused")}}
    guard service.reservingDisk(in:sample(floor+debt)).diskCommitted==debt else {fatalError("Rejected queued publication leaked or durable failed debt disappeared")}
    var recovered=AdmissionPolicy()
    try recovered.reserveWorker(key:"after-refusal",sample:service.reservingDisk(in:sample(floor+debt)),now:1000)
    let readyStore=try ArtifactStore(directory:root.appendingPathComponent("ready"),availableBytes:{20<<30})
    let readyService=AsyncArtifacts(store:readyStore)
    func readyResult()throws->ArtifactServiceResult {
        let limit=ProcessInfo.processInfo.systemUptime+3
        while ProcessInfo.processInfo.systemUptime<limit {
            if let result=readyService.drain().first {return result}
            Thread.sleep(forTimeInterval:0.001)
        }
        throw ArtifactServiceFailure.unavailable
    }
    try readyService.publish(request:UUID().uuidString.lowercased(),job:UUID().uuidString.lowercased(),owner:owner,data:Data([3]),now:1000)
    guard case .success(.published)=try readyResult().result else {fatalError("Ready export fixture not actually published")}
    // The filesystem sample can predate this completed write. Retain the full
    // bounded commitment, rather than briefly release it on ready publication.
    guard readyService.reservingDisk(in:sample(floor)).diskCommitted==1 else {fatalError("Ready publication released debt against a pre-write free-space sample")}
    try workerDenied(readyService.reservingDisk(in:sample(floor)))
    try readyService.expire(request:UUID().uuidString.lowercased(),now:1000+86400000)
    guard case .success(.expired)=try readyResult().result,
          readyService.reservingDisk(in:sample(floor)).diskCommitted==0 else {fatalError("Proven retained export cleanup did not release its disk commitment")}
    print("PASS: failed/queued/ready export disk commitments, exact10GiB-after-debt admission, short/overflow refusal, VM preservation and cleanup-only debt release")
}
