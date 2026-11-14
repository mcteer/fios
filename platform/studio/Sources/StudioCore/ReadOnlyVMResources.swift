import Foundation

// This surface cannot create/start/stop/remove a sandbox. The installed
// observation composition retains its executor privately, using only its
// existing bounded resource-work channel. Task execution remains separate.
protocol VMObservationWork:Sendable {
    func submit(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws
    func drain()->[VMReadResult]
}

private final class EnrolledVMObservationWork:VMObservationWork,@unchecked Sendable {
    private let executor:SandboxExecutor
    init(executor:SandboxExecutor) {self.executor=executor}
    func submit(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws {
        try executor.submitResources(configuration:configuration,id:id,leaseUntil:leaseUntil)
    }
    func drain()->[VMReadResult] {executor.drainResources()}
}

enum VMObservationConfiguration {
    static func load(directory:URL)throws->(any VMObservationWork)? {
        guard let policy=try VMResourceEnrolledPolicy.load(directory:directory) else {return nil}
        return EnrolledVMObservationWork(executor:try policy.makeObservationExecutor())
    }
}

enum VMObservationConfigurationOutcome:Sendable {
    case configured(any VMObservationWork),unconfigured,unavailable
}

// One original off-loop policy load. A stalled loader never gets replaced
// merely because time elapsed; no task, daemon or model operation runs here.
final class AsyncVMObservationConfiguration:@unchecked Sendable {
    private let lock=NSLock()
    private var result:VMObservationConfigurationOutcome?
    init(load:@escaping @Sendable()throws->(any VMObservationWork)?) {
        Thread.detachNewThread { [self] in
            let outcome:VMObservationConfigurationOutcome
            do {outcome=try load().map { .configured($0) } ?? .unconfigured}
            catch {outcome = .unavailable}
            lock.lock();result=outcome;lock.unlock()
        }
    }
    func poll()->VMObservationConfigurationOutcome? {
        lock.lock();defer {lock.unlock()};let value=result;result=nil;return value
    }
}

// Serialized observation only. An eligible target must already be recorded
// as owned, running and within its original lease. Unknown capacity never
// bootstraps a probe, replays a failed read or extends a task's permission.
final class ReadOnlyVMResources {
    private struct Target {
        let configuration:SandboxConfiguration
        let id:String
        let leaseUntil:Int64
    }
    private let work:any VMObservationWork
    private var pending:Target?
    private var latest:VMKernelSample?
    private var latestTarget:Target?
    private var failedTargets=Set<String>()
    private var previous:Int64 = -1
    private var lastBegin:Int64 = -2000
    private var fenced=false
    init(work:any VMObservationWork) {self.work=work}

    private func target(_ record:SandboxRecord,jobs:[DurableJob],now:Int64)->Target? {
        guard record.createIssued,record.startIssued,!record.removalProven,
              let id=record.runtimeID,WireScalar.sha256(id),
              let job=jobs.first(where:{$0.id==record.configuration.job}),job.state == .running else {return nil}
        var lease=job.lease
        guard lease.valid(now:now),now>=lease.created,lease.expires-now>=5000,
              lease.deadline>=lease.expires else {return nil}
        return Target(configuration:record.configuration,id:id,leaseUntil:lease.expires)
    }
    private func stillOwned(_ target:Target,records:[SandboxRecord],jobs:[DurableJob],now:Int64)->Bool {
        records.contains { record in
            guard let current=self.target(record,jobs:jobs,now:now) else {return false}
            return current.configuration==target.configuration && current.id==target.id && now<target.leaseUntil
        }
    }
    func tick(records:[SandboxRecord],jobs:[DurableJob],physical:UInt64,now:Int64) {
        guard (0...WireScalar.maximumTimestamp).contains(now),now>=previous else {fenced=true;latest=nil;return}
        previous=now
        if let latestTarget,!stillOwned(latestTarget,records:records,jobs:jobs,now:now) {latest=nil;self.latestTarget=nil}
        for result in work.drain() {
            guard let target=pending,result.job==target.configuration.job,result.runtimeID==target.id else {
                fenced=true;latest=nil;continue
            }
            pending=nil
            guard !fenced,stillOwned(target,records:records,jobs:jobs,now:now),
                  case .success(let sample)=result.result,let envelope=sample.envelope,
                  physical>0,sample.total>0,sample.total<=physical,sample.free<=sample.total,WireScalar.sha256(sample.bootHash),
                  (0...WireScalar.maximumTimestamp).contains(sample.sampledAt),(-1000...5000).contains(now-sample.sampledAt),
                  envelope.total==sample.total,envelope.free==sample.free,
                  envelope.configuredCap<=physical,envelope.sampledAt<=sample.sampledAt,
                  VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:now) != nil else {
                failedTargets.insert(target.id);latest=nil;continue
            }
            latest=sample;latestTarget=target
        }
        guard !fenced,pending==nil,now-lastBegin>=2000,failedTargets.count<64 else {return}
        guard let target=records.compactMap({self.target($0,jobs:jobs,now:now)}).first(where:{!failedTargets.contains($0.id)}) else {return}
        do {
            try work.submit(configuration:target.configuration,id:target.id,leaseUntil:target.leaseUntil)
            pending=target;lastBegin=now
        } catch AdmissionError.capacity {} // No effect was submitted; use the same bounded channel later.
        catch {failedTargets.insert(target.id);latest=nil}
    }
    private func envelope(now:Int64)->VMResourceObservation? {
        guard !fenced,now>=previous,let envelope=latest?.envelope,
              VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:now) != nil else {return nil}
        return envelope
    }
    func applying(to host:ResourceSample,now:Int64)->ResourceSample {
        guard let envelope=envelope(now:now),envelope.total<=host.physical,envelope.configuredCap<=host.physical,
              let available=VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:now) else {return host.replacingVM(nil)}
        return host.replacingVM(available,sampledAt:envelope.sampledAt)
    }
    func epoch(now:Int64)->String? {envelope(now:now)?.runtimeHash}
}
