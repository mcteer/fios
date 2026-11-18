import Foundation
import Darwin

func runCPUTests() throws {
    var sampler=CPUSampler()
    guard sampler.observe(ticks:[10,10,80,0],now:1000)==nil else { fatalError("First CPU sample fabricated utilization") }
    guard sampler.observe(ticks:[20,20,160,0],now:3000)==20 else { fatalError("CPU tick delta incorrect") }
    guard sampler.observe(ticks:[20,20,160,0],now:5000)==nil else { fatalError("Unchanged counter fabricated idle") }
    guard sampler.observe(ticks:[21,21,161,0],now:4000)==nil else { fatalError("Clock rollback accepted") }
    guard sampler.observe(ticks:nil,now:6000)==nil else { fatalError("Missing CPU measurement fabricated idle") }
    _=sampler.observe(ticks:[100,100,100,0],now:7000)
    guard sampler.observe(ticks:[1,1,1,0],now:8000)==nil else { fatalError("Reset CPU counters accepted as utilization") }
    guard CPUSampler.readTicks()?.count==4 else { fatalError("Native CPU counters unavailable") }
    let now = HostResources.nowMilliseconds()
    let stale = HostResources.sample(statePath: NSTemporaryDirectory(), measuredCPU: 25, measuredCPUAt: now - 6000)
    guard stale.cpu == nil, stale.sampledAt >= now, stale.diskFree != nil else {
        fatalError("Expired CPU data made fresh host observations stale")
    }
    let recent = HostResources.sample(statePath: NSTemporaryDirectory(), measuredCPU: 25, measuredCPUAt: now - 4000)
    let exported = try ResourceObservationExport.encode(sample:recent,gpu:nil,gpuSampledAt:nil,now:now+2000,epoch:UUID().uuidString.lowercased(),sequence:1,vmEpoch:nil)
    guard recent.cpu == 25, recent.sampledAt >= now, exported.resources["cpu"] is NSNull,
          exported.resources["diskFree"] is UInt64 else {fatalError("CPU expiry aged independent disk observations")}
    var fixture=ResourceSample(sampledAt:now,physical:32<<30,available:24<<30,vmAvailable:nil,diskFree:20<<30,cpu:25,pressure:.normal,thermal:.nominal)
    fixture.cpuSampledAt=now-4000
    let admission=AdmissionPolicy()
    guard admission.resourcesSafe(fixture,now:now+1000,needsVM:false),
          !admission.resourcesSafe(fixture,now:now+1001,needsVM:false) else {fatalError("Fresh host sensors renewed CPU admission")}
    func usage()throws->(UInt64,Double) {
        var native=rusage_info_v2(),posix=rusage()
        let status=withUnsafeMutablePointer(to:&native) {$0.withMemoryRebound(to:rusage_info_t?.self,capacity:1) {proc_pid_rusage(getpid(),RUSAGE_INFO_V2,$0)}}
        guard status==0,getrusage(RUSAGE_SELF,&posix)==0 else {throw RuntimeError.invalid}
        return (native.ri_user_time+native.ri_system_time,Double(posix.ru_utime.tv_sec+posix.ru_stime.tv_sec)+Double(posix.ru_utime.tv_usec+posix.ru_stime.tv_usec)/1e6)
    }
    let before=try usage(),end=ProcessInfo.processInfo.systemUptime+0.05
    while ProcessInfo.processInfo.systemUptime<end {}
    let after=try usage(),nativeSeconds=ProcessCPU.seconds(ticks:after.0-before.0),posixSeconds=after.1-before.1
    guard nativeSeconds.isFinite,abs(nativeSeconds-posixSeconds)<0.01 else {fatalError("Mach CPU units disagree with POSIX microseconds")}
    print("PASS: Mach CPU conversion independently agrees with POSIX getrusage; no nanosecond assumption")
    print("PASS: native CPU tick sampling, measured utilization, unknown-first/missing/stalled/rollback rejection")
}
