import Foundation

private final class HeldLineageSource:NativeLineageReading,@unchecked Sendable {
    let peer:NativeControlPeer
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var calls=0
    init(peer:NativeControlPeer) {self.peer=peer}
    var count:Int {lock.lock();defer {lock.unlock()};return calls}
    func lineage(instance:String,correlationID:String)throws->NativeRequestLineageSample {
        lock.lock();calls+=1;let sequence=UInt64(calls);lock.unlock()
        entered.signal()
        guard release.wait(timeout:.now()+3) == .success else {throw NativeControlError.deadline}
        return NativeRequestLineageSample(peer:peer,sampledAt:10000,lineage:NativeRequestLineage(instance:instance,correlationID:correlationID,
            sampleSequence:sequence,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:1,active:0,responding:0))
    }
}
func runNativeLineagePollingTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let jobs=["00000000-0000-4000-8000-000000000001","00000000-0000-4000-8000-000000000002"]
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:String(repeating:"1",count:32),canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    let peer=NativeControlPeer(pid:42,start:99,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"c",count:64)))
    do {
        let journal=try Journal(directory:directory)
        for job in jobs {try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope);try journal.markDispatched(job:job,attempt:0)}
        let source=HeldLineageSource(peer:peer),poller=NativeLineagePoller(journal:journal,source:source)
        func drain()throws {
            let end=ProcessInfo.processInfo.systemUptime+2
            while ProcessInfo.processInfo.systemUptime<end {
                if try poller.drain(now:10001) {return}
                Thread.sleep(forTimeInterval:0.001)
            }
            throw NativeControlError.deadline
        }
        let began=ProcessInfo.processInfo.systemUptime
        guard try poller.beginNext(),ProcessInfo.processInfo.systemUptime-began<0.1,
              source.entered.wait(timeout:.now()+1) == .success,
              try !poller.beginNext(),try !poller.drain(now:10000),source.count==1 else {throw JournalError.invalid}
        // Normal completion can precede an asynchronous diagnostic reply.
        try journal.resolveInference(job:jobs[0],attempt:0,scope:scope,outcome:.complete)
        source.release.signal();try drain()
        guard try journal.inferenceScope(job:jobs[0],attempt:0)?.state == .complete,try journal.unresolvedCount()==1 else {throw JournalError.invalid}
        guard try poller.beginNext(),source.entered.wait(timeout:.now()+1) == .success else {throw JournalError.invalid}
        source.release.signal();try drain()
        guard source.count==2,try journal.inferenceScope(job:jobs[1],attempt:0)?.state == .dispatched else {throw JournalError.invalid}
    }
    do {
        let journal=try Journal(directory:directory)
        let id=try scope.nativeRequestCorrelationID(job:jobs[1],attempt:0)
        let replay=NativeRequestLineageSample(peer:peer,sampledAt:10002,lineage:NativeRequestLineage(instance:scope.nativeEpoch,correlationID:id,
            sampleSequence:2,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:0,preparing:1,active:0,responding:0))
        guard case .unknown=try journal.observeLineage(job:jobs[1],attempt:0,scope:scope,peer:peer,sample:replay,now:10002),
              try journal.unresolvedCount()==1,try journal.uncertainCount()==1 else {throw JournalError.invalid}
    }
    print("PASS: one-slot off-loop lineage reads, responsive manager polling, late-reply completion preservation and actual journal checkpoint/restart replay retention; synthetic source only")
}
