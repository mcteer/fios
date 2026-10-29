import Foundation

private func expectAdmissionReject(_ body: () throws -> Void) {
    do { try body() } catch { return }; preconditionFailure("Unsafe admission accepted")
}
func runAdmissionTests() throws {
    let resources = ResourceSample(sampledAt: 10_000, physical: 128 << 30, available: 64 << 30,
                                   vmAvailable: 8 << 30, diskFree: 100 << 30, cpu: 10,
                                   pressure: .normal, thermal: .nominal, vmSampledAt:10_000)
    var undatedAdmission=AdmissionPolicy()
    let undatedVM=resources.replacingVM(8<<30)
    do {
        try undatedAdmission.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:undatedVM,now:10000)
        fatalError("Undated VM capacity admitted")
    } catch AdmissionError.stale {}
    guard !undatedAdmission.resourcesSafe(undatedVM,now:10000,needsVM:true) else {fatalError("Undated VM capacity reported safe")}
    try undatedAdmission.reserveWorker(key:"host-only",sample:undatedVM,now:10000)
    for stamp:Int64 in [5000,11000] {
        var exact=AdmissionPolicy()
        let measured=resources.replacingVM(8<<30,sampledAt:stamp)
        try exact.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:measured,now:10000)
        guard exact.resourcesSafe(measured,now:10000,needsVM:true) else {fatalError("Exact VM timestamp boundary refused")}
    }
    for stamp:Int64 in [4999,11001,-1,Int64.max] {
        var invalidVM=AdmissionPolicy()
        let measured=resources.replacingVM(8<<30,sampledAt:stamp)
        expectAdmissionReject {try invalidVM.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:measured,now:10000)}
    }
    var sourceFreshness=AdmissionPolicy()
    let agedVM=resources.replacingVM(8<<30,sampledAt:4999)
    expectAdmissionReject {try sourceFreshness.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:agedVM,now:10000)}
    try sourceFreshness.reserveWorker(key:"independent-native",sample:agedVM,now:10000)
    expectAdmissionReject {try sourceFreshness.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:resources.replacingVM(8<<30,sampledAt:Int64.min),now:10000)}
    var admission = AdmissionPolicy()
    let a = UUID().uuidString.lowercased(), b = UUID().uuidString.lowercased()
    try admission.reserve(job: a, memory: 512 << 20, cpus: 1, sample: resources, now: 10_000)
    try admission.reserve(job: b, memory: 512 << 20, cpus: 1, sample: resources, now: 10_000)
    expectAdmissionReject { try admission.reserve(job: UUID().uuidString.lowercased(), memory: 512 << 20, cpus: 1, sample: resources, now: 10_000) }
    expectAdmissionReject { try admission.reserve(job: a, memory: 512 << 20, cpus: 1, sample: resources, now: 10_000) }
    admission.releaseProvenAbsent(job: b)
    expectAdmissionReject { try admission.reserve(job: b, memory: 512 << 20, cpus: 1, sample: resources, now: 15_001) }
    expectAdmissionReject { try admission.reserve(job: b, memory: 3 << 30, cpus: 1, sample: resources, now: 10_000) }
    let nativeOnly=ResourceSample(sampledAt:10_000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    var nativeAdmission=AdmissionPolicy()
    try nativeAdmission.reserveWorker(key:"one",sample:nativeOnly,now:10_000)
    try nativeAdmission.reserveWorker(key:"two",sample:nativeOnly,now:10_000)
    expectAdmissionReject { try nativeAdmission.reserveWorker(key:"three",sample:nativeOnly,now:10_000) }
    expectAdmissionReject { try nativeAdmission.reserve(job:UUID().uuidString.lowercased(),memory:512<<20,cpus:1,sample:nativeOnly,now:10_000) }
    let old=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"a",count:64),image:"sha256:"+String(repeating:"b",count:64),memory:2<<30,cpus:2)
    var recovered=AdmissionPolicy()
    try recovered.restoreSandbox(old)
    try recovered.restoreSandbox(old) // Idempotent accounting, no double charge.
    let tight=ResourceSample(sampledAt:10_000,physical:64<<30,available:18<<30,vmAvailable:8<<30,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal,vmSampledAt:10_000)
    expectAdmissionReject {try recovered.reserveWorker(key:"new",sample:tight,now:10_000)}
    recovered.releaseProvenAbsent(job:old.job)
    try recovered.reserveWorker(key:"new",sample:tight,now:10_000)
    var lease = try JobLease(created: 10_000, lifetime: 60_000)
    try lease.renew(now: 20_000)
    precondition(lease.valid(now: 49_999))
    precondition(!lease.valid(now: 50_000))
    expectAdmissionReject { try lease.renew(now: 50_000) }
    var absolute = try JobLease(created: 10_000, lifetime: 30_000)
    try absolute.renew(now: 20_000)
    precondition(!absolute.valid(now: 40_000))
    absolute.revoke()
    expectAdmissionReject { try absolute.renew(now: 21_000) }
    print("PASS: resource admission slots/memory/freshness and irreversible owner leases")
}
