import Foundation

func runAdmissionBoundaryTests() throws {
    let gib:UInt64=1<<30,worker:UInt64=512<<20
    func sample(physical:UInt64=128<<30,available:UInt64?=64<<30,vm:UInt64?=8<<30,disk:UInt64?=100<<30,
                cpu:Double?=10,pressure:MemoryPressure = .normal,thermal:ThermalState = .nominal,at:Int64=10000)->ResourceSample {
        ResourceSample(sampledAt:at,physical:physical,available:available,vmAvailable:vm,diskFree:disk,cpu:cpu,pressure:pressure,thermal:thermal)
    }
    func reject(_ value:ResourceSample,vm:Bool=false) throws {
        var policy=AdmissionPolicy()
        do {
            if vm {try policy.reserve(job:UUID().uuidString.lowercased(),memory:worker,cpus:1,sample:value,now:10000)}
            else {try policy.reserveWorker(key:"fixture",sample:value,now:10000)}
            fatalError("Unknown/unsafe sensor admitted work")
        } catch is AdmissionError {}
    }
    let invalidCPU:[Double?]=[nil,Double.nan,Double.infinity,-0.01,80.001]
    for cpu in invalidCPU {
        try reject(sample(cpu:cpu));try reject(sample(cpu:cpu),vm:true)
    }
    for pressure in [MemoryPressure.warning,.critical,.unknown] {try reject(sample(pressure:pressure))}
    for thermal in [ThermalState.serious,.critical,.unknown] {try reject(sample(thermal:thermal))}
    try reject(sample(available:nil));try reject(sample(available:129*gib))
    try reject(sample(disk:nil));try reject(sample(disk:10*gib-1))
    try reject(sample(vm:nil),vm:true)
    try reject(sample(at:4999));try reject(sample(at:11001));try reject(sample(at:-1))
    var noVM=AdmissionPolicy()
    try noVM.reserveWorker(key:"independent-native",sample:sample(vm:nil),now:10000)
    for timestamp in [Int64(5000),11000] {
        var policy=AdmissionPolicy()
        try policy.reserveWorker(key:"exact-age",sample:sample(cpu:80,thermal:.fair,at:timestamp),now:10000)
    }
    let physical=128*gib
    let twentyPercent=physical/5+(physical%5 == 0 ? 0:1)
    let full=sample(physical:physical,available:twentyPercent+5*gib,vm:4*gib,disk:10*gib,cpu:80,thermal:.fair)
    var mixed=AdmissionPolicy()
    let first=UUID().uuidString.lowercased(),second=UUID().uuidString.lowercased()
    try mixed.reserve(job:first,memory:2*gib,cpus:2,sample:full,now:10000)
    try mixed.reserve(job:second,memory:2*gib,cpus:2,sample:full,now:10000)
    try mixed.reserveWorker(key:"one",sample:full,now:10000)
    try mixed.reserveWorker(key:"two",sample:full,now:10000)
    guard mixed.resourcesSafe(full,now:10000,needsVM:true) else {fatalError("Exact mixed reservation boundary refused")}
    do {try mixed.reserveWorker(key:"third",sample:full,now:10000);fatalError("Third worker admitted")}catch is AdmissionError{}
    do {try mixed.reserve(job:UUID().uuidString.lowercased(),memory:worker,cpus:1,sample:full,now:10000);fatalError("Third sandbox admitted")}catch is AdmissionError{}
    guard !mixed.resourcesSafe(sample(available:twentyPercent+5*gib-1),now:10000,needsVM:false) else {fatalError("Fractional20% host headroom admitted one byte of excess mixed commitment")}
    guard !mixed.resourcesSafe(full,now:15001,needsVM:false) else {fatalError("Stale host telemetry stayed safe")}
    guard !mixed.resourcesSafe(sample(vm:4*gib-1),now:10000,needsVM:true),
          mixed.resourcesSafe(sample(vm:4*gib-1),now:10000,needsVM:false) else {fatalError("VM loss ignored or leaked to native-only work")}
    mixed.releaseProvenAbsent(job:second)
    mixed.releaseWorkerAfterReap(key:"two")
    try mixed.reserve(job:UUID().uuidString.lowercased(),memory:worker,cpus:1,sample:full,now:10000)
    for (memory,cpus) in [(worker-1,1),(2*gib+1,1),(worker,0),(worker,3)] {
        var policy=AdmissionPolicy()
        do {try policy.reserve(job:UUID().uuidString.lowercased(),memory:memory,cpus:cpus,sample:sample(),now:10000);fatalError("Invalid sandbox resource limit admitted")}catch is AdmissionError{}
    }
    for physical in [64*gib,128*gib,UInt64.max-1,UInt64.max] {
        let minimum=max(16*gib,physical/5+(physical%5 == 0 ? 0:1))
        var exact=AdmissionPolicy()
        try exact.reserveWorker(key:"exact-headroom",sample:sample(physical:physical,available:minimum+worker),now:10000)
        // A fractional byte of the20% requirement must round UP, never make
        // an additional byte available to a task/worker reservation.
        try reject(sample(physical:physical,available:minimum+worker-1))
    }
    func withJournal(_ body:(Journal)throws->Void) throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-admission-"+UUID().uuidString)
        var journal:Journal?=try Journal(directory:directory)
        defer {journal=nil;try? FileManager.default.removeItem(at:directory)}
        try body(journal!)
    }
    func proposed(created:Int64=10000)->DurableJob {
        try! DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:created)
    }
    func configuration(_ job:DurableJob)throws->SandboxConfiguration {
        try SandboxConfiguration(job:job.id,nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:2*gib,cpus:2)
    }
    for sandboxFirst in [true,false] {
        try withJournal {journal in
            // Each ordering uses a fresh independent journal, never a second
            // application opening the same SQLite file.
            for sandbox in (sandboxFirst ? [true,false]:[false,true]) {
                for _ in 0..<2 {
                    let job=proposed()
                    if sandbox {_ = try journal.reserveSandbox(job:job,configuration:configuration(job))}
                    else {_ = try journal.reserveJob(job)}
                }
            }
            guard try journal.jobs().filter({$0.state != .removed}).count==4 else {fatalError("Mixed host job slots not available")}
            do {_ = try journal.reserveJob(proposed());fatalError("Third native/fifth total job admitted")}catch JournalError.trackingLimit{}
            let extra=proposed()
            do {_ = try journal.reserveSandbox(job:extra,configuration:configuration(extra));fatalError("Third sandbox/fifth total job admitted")}catch JournalError.trackingLimit{}
        }
    }
    try withJournal {journal in
        // Real bounded durable rows, no execution/inference or large payloads.
        for _ in 0..<256 {
            let job=try journal.reserveJob(proposed())
            try journal.transitionJob(id:job.id,to:.revoking,now:10000)
            try journal.transitionJob(id:job.id,to:.removed,now:10000)
        }
        guard try journal.jobs().count==256 else {fatalError("Retention boundary not reached")}
        do {_ = try journal.reserveJob(proposed());fatalError("Retained-job quota admitted more work")}catch JournalError.trackingLimit{}
        let extra=proposed()
        do {_ = try journal.reserveSandbox(job:extra,configuration:configuration(extra));fatalError("Retained-job quota admitted sandbox")}catch JournalError.trackingLimit{}
        try journal.expireTerminalJobs(now:10000+86400000-1)
        guard try journal.jobs().count==256 else {fatalError("Retention expired early")}
        try journal.expireTerminalJobs(now:10000+86400000)
        guard try journal.jobs().isEmpty else {fatalError("Eligible fixture tombstones not reclaimed")}
        _ = try journal.reserveJob(proposed(created:10000+86400000))
    }
    print("PASS: unknown/critical sensors, CPU/thermal/disk/clock boundaries, mixed sandbox+worker/job reservations, retention refusal, scoped loss and conservative fractional headroom")
}
