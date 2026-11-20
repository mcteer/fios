import Foundation
import Darwin

func runCPUTests() throws {
    var sampler=CPUSampler()
    guard sampler.observe(ticks:[10,10,80,0],now:1000)==nil else { fatalError("First CPU sample fabricated utilization") }
    guard sampler.observe(ticks:[20,20,160,0],now:3000)==20 else { fatalError("CPU tick delta incorrect") }
    guard sampler.observe(ticks:[20,20,160,0],now:5000)==nil else { fatalError("Unchanged counter fabricated idle") }
    guard sampler.observe(ticks:[21,21,161,0],now:4000)==nil else { fatalError("Clock rollback accepted") }
    guard sampler.observe(ticks:[22,22,162,0],now:4500)==nil,
          sampler.observe(ticks:[23,23,163,0],now:5000)==nil,
          sampler.observe(ticks:[24,24,164,0],now:5500) != nil else {
        fatalError("CPU clock rollback reused a pre-catch-up interval")
    }
    guard sampler.observe(ticks:nil,now:6000)==nil else { fatalError("Missing CPU measurement fabricated idle") }
    guard sampler.observe(ticks:[25,25,165,0],now:5998)==nil,
          sampler.observe(ticks:[26,26,166,0],now:5999)==nil,
          sampler.observe(ticks:[27,27,167,0],now:6000)==nil else {
        fatalError("Missing CPU sample reset accepted clock watermark")
    }
    _=sampler.observe(ticks:[100,100,100,0],now:7000)
    guard sampler.observe(ticks:[1,1,1,0],now:8000)==nil else { fatalError("Reset CPU counters accepted as utilization") }
    var bounded=CPUSampler()
    guard bounded.observe(ticks:[100,100,100,100],now:10000)==nil,
          bounded.observe(ticks:[100,100,101,100],now:15000)==0,
          bounded.observe(ticks:[100,100,102,100],now:20001)==nil,
          bounded.observe(ticks:[100,100,103,100],now:20002)==0 else {
        fatalError("CPU sampling interval did not enforce exact age or recover with a fresh baseline")
    }
    for count:mach_msg_type_number_t in [0,3,5] {
        guard CPUSampler.readTicks({buffer,reported in buffer[0]=10;reported=count;return KERN_SUCCESS})==nil else {
            fatalError("Mismatched CPU kernel count became a complete tick sample")
        }
    }
    var discontinuity=CPUSampler()
    _=discontinuity.observe(ticks:[1,1,1,0],now:1000)
    let short=CPUSampler.readTicks {buffer,count in buffer[0]=10;count=1;return KERN_SUCCESS}
    guard discontinuity.observe(ticks:short,now:2000)==nil,
          discontinuity.observe(ticks:[2,2,2,0],now:3000)==nil,
          discontinuity.observe(ticks:[3,3,3,0],now:4000) != nil else {fatalError("Short kernel read bridged the CPU sampling interval")}
    let full=CPUSampler.readTicks {buffer,count in
        guard count==4 else {return KERN_INVALID_ARGUMENT}
        for i in 0..<4 {buffer[i]=integer_t(i+1)}
        return KERN_SUCCESS
    }
    guard full==[1,2,3,4] else {fatalError("Full CPU kernel count lost exact ticks")}
    guard CPUSampler.readTicks()?.count==4 else { fatalError("Native CPU counters unavailable") }
    let expectedWords=mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size/MemoryLayout<integer_t>.size)
    for words in [0,expectedWords-1,expectedWords+1] {
        guard HostResources.freeMemory(physical:1<<20,pageSize:4096,read:{buffer,count in
            buffer[0]=3;count=words;return KERN_SUCCESS
        })==nil else {fatalError("Incomplete kernel memory reply supplied available bytes")}
    }
    guard HostResources.freeMemory(physical:8192,pageSize:4096,read:{buffer,_ in buffer[0]=3;return KERN_SUCCESS})==8192,
          HostResources.freeMemory(physical:8192,pageSize:UInt64.max,read:{buffer,_ in buffer[0]=3;return KERN_SUCCESS})==nil,
          HostResources.memoryPressure(read:{level,size in level=1;size=3;return 0}) == .unknown,
          HostResources.memoryPressure(read:{level,_ in level=1;return 0}) == .normal else {
        fatalError("Host memory reply bounds or pressure decoding changed")
    }
    let now = HostResources.nowMilliseconds()
    let stale = HostResources.sample(statePath: NSTemporaryDirectory(), measuredCPU: 25, measuredCPUAt: now - 6000)
    guard stale.cpu == nil, stale.sampledAt >= now, stale.diskFree != nil else {
        fatalError("Expired CPU data made fresh host observations stale")
    }
    let recent = HostResources.sample(statePath: NSTemporaryDirectory(), measuredCPU: 25, measuredCPUAt: now - 4000)
    let exported = try ResourceObservationExport.encode(sample:recent,gpu:nil,gpuSampledAt:nil,now:now+2000,epoch:UUID().uuidString.lowercased(),sequence:1,vmEpoch:nil)
    guard recent.cpu == 25, recent.sampledAt >= now, exported.resources["cpu"] is NSNull,
          exported.resources["diskFree"] is UInt64 else {fatalError("CPU expiry aged independent disk observations")}
    var fixture=ResourceSample(sampledAt:now,physical:32<<30,available:24<<30,vmAvailable:nil,diskFree:20<<30,cpu:25,pressure:.normal,thermal:.nominal,cpuSampledAt:now)
    fixture.cpuSampledAt=now-4000
    let admission=AdmissionPolicy()
    guard admission.resourcesSafe(fixture,now:now+1000,needsVM:false),
          !admission.resourcesSafe(fixture,now:now+1001,needsVM:false) else {fatalError("Fresh host sensors renewed CPU admission")}
    fixture.cpuSampledAt=nil
    guard !admission.resourcesSafe(fixture,now:now,needsVM:false) else {fatalError("Undated CPU borrowed host time for admission")}
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
