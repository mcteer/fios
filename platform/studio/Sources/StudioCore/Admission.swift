import Foundation

public enum AdmissionError: Error { case invalid, stale, capacity, expired }

struct AdmissionPolicy {
    private struct Reservation { let memory: UInt64; let cpus: Int }
    private var reservations: [String: Reservation] = [:]
    private var workers = Set<String>()

    private func headroom(_ sample: ResourceSample, now: Int64, newMemory: UInt64, needsVM: Bool) throws {
        guard now >= 0, sample.sampledAt >= 0,
              now <= ActivityPolicy.maximumTimestamp, sample.sampledAt <= ActivityPolicy.maximumTimestamp,
              (-1000...5000).contains(now - sample.sampledAt) else { throw AdmissionError.stale }
        guard sample.pressure == .normal, [.nominal,.fair].contains(sample.thermal),
              let cpu = sample.cpu, cpu.isFinite, (0...80).contains(cpu),
              let available = sample.available, available <= sample.physical,
              let disk = sample.diskFree, disk >= 10 << 30,
              disk - (10 << 30) >= sample.diskCommitted
        else { throw AdmissionError.capacity }
        let native = HostRAMBudget.nativeHeadroom(physicalBytes:sample.physical)
        let owned = reservations.values.reduce(UInt64(0)) { $0 + $1.memory } + UInt64(workers.count) * (512 << 20)
        guard available >= native, available - native >= owned,
              available - native - owned >= newMemory
        else { throw AdmissionError.capacity }
        if needsVM {
            let vmAt=sample.vmSampledAt ?? sample.sampledAt
            guard vmAt>=0,vmAt<=ActivityPolicy.maximumTimestamp,(-1000...5000).contains(now-vmAt) else {throw AdmissionError.stale}
            let committed=reservations.values.reduce(UInt64(0), { $0 + $1.memory })
            guard let vm=sample.vmAvailable,vm>=committed,vm-committed>=newMemory else { throw AdmissionError.capacity }
        }
    }
    func resourcesSafe(_ sample:ResourceSample,now:Int64,needsVM:Bool) -> Bool {
        (try? headroom(sample,now:now,newMemory:0,needsVM:needsVM)) != nil
    }
    mutating func reserve(job: String, memory: UInt64, cpus: Int, sample: ResourceSample, now: Int64) throws {
        guard let uuid = UUID(uuidString: job), uuid.uuidString.lowercased() == job,
              (512 << 20...2 << 30).contains(memory), (1...2).contains(cpus), reservations[job] == nil
        else { throw AdmissionError.invalid }
        guard reservations.count < 2,
              reservations.values.reduce(0, { $0 + $1.cpus }) + cpus <= 4 else { throw AdmissionError.capacity }
        try headroom(sample, now: now, newMemory: memory, needsVM: true)
        reservations[job] = Reservation(memory: memory, cpus: cpus)
    }
    // Separate trusted one-use metadata bootstrap authority. Never called by
    // ordinary task admission, and never treats unknown VM bytes as available.
    mutating func reserveVMProbe(_ configuration:SandboxConfiguration,permission:VMProbePermission,sample:ResourceSample,now:Int64)throws {
        try permission.validate(now:now)
        guard permission.job==nil,configuration.job==permission.id,configuration.nonce==permission.nonce,configuration.image==permission.image,configuration.memory==512<<20,configuration.cpus==1,
              reservations[configuration.job]==nil,reservations.count<2,
              reservations.values.reduce(0,{$0+$1.cpus})+1<=4 else {throw AdmissionError.invalid}
        try headroom(sample,now:now,newMemory:configuration.memory,needsVM:false)
        reservations[configuration.job]=Reservation(memory:configuration.memory,cpus:1)
    }
    mutating func restoreSandbox(_ configuration:SandboxConfiguration) throws {
        if let existing=reservations[configuration.job] {
            guard existing.memory==configuration.memory,existing.cpus==configuration.cpus else {throw AdmissionError.invalid}
            return
        }
        guard reservations.count<2,reservations.values.reduce(0,{$0+$1.cpus})+configuration.cpus<=4 else {throw AdmissionError.capacity}
        reservations[configuration.job]=Reservation(memory:configuration.memory,cpus:configuration.cpus)
    }
    mutating func reserveWorker(key: String, sample: ResourceSample, now: Int64) throws {
        guard workers.count < 2, !workers.contains(key) else { throw AdmissionError.capacity }
        try headroom(sample, now: now, newMemory: 512 << 20, needsVM: false)
        workers.insert(key)
    }
    // Existing commitments are restored even under current pressure. Refusing
    // to account for them would incorrectly make new work look admissible.
    mutating func restoreWorker(key:String) throws {
        guard !key.isEmpty,workers.contains(key) || workers.count<2 else { throw AdmissionError.capacity }
        workers.insert(key)
    }
    mutating func releaseWorkerAfterReap(key: String) { workers.remove(key) }
    mutating func releaseProvenAbsent(job: String) { reservations.removeValue(forKey: job) }
}
