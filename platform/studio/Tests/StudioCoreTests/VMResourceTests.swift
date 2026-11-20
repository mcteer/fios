import Foundation

func runVMResourceTests() throws {
    let raw=Data("MemTotal: 16384 kB\nMemFree: 8192 kB\nMemAvailable: 12000 kB\n".utf8)
    guard let memory=VMResources.kernelMemory(raw),memory.total==16<<20,memory.free==8<<20 else {fatalError("Kernel VM memory units misread")}
    for invalid in ["MemTotal: 1 kB\nMemFree: 2 kB\n","MemTotal: 1 kB\nMemTotal: 1 kB\nMemFree: 0 kB\n","MemTotal: 18446744073709551615 kB\nMemFree: 0 kB\n","MemTotal: 1 MB\nMemFree: 0 kB\n"] {
        guard VMResources.kernelMemory(Data(invalid.utf8))==nil else {fatalError("Malformed kernel VM memory accepted")}
    }
    let hash=String(repeating:"a",count:64)
    func value(_ coverage:Bool=true,_ time:Int64=1000,_ free:UInt64=8<<30)->VMResourceObservation {
        VMResourceObservation(runtimeHash:hash,sampledAt:time,configuredCap:12<<30,total:16<<30,free:free,allVMConsumersCovered:coverage)
    }
    guard VMResources.remaining(value(),expectedRuntimeHash:hash,now:1000)==4<<30,
          VMResources.remaining(value(false),expectedRuntimeHash:hash,now:1000)==nil,
          VMResources.remaining(value(),expectedRuntimeHash:String(repeating:"b",count:64),now:1000)==nil,
          VMResources.remaining(value(true,0),expectedRuntimeHash:hash,now:5001)==nil,
          VMResources.remaining(value(true,2001),expectedRuntimeHash:hash,now:1000)==nil,
          VMResources.remaining(value(true,1000,17<<30),expectedRuntimeHash:hash,now:1000)==nil,
          VMResources.remaining(value(true,1000,1<<30),expectedRuntimeHash:hash,now:1000)==0 else {fatalError("VM cap/whole-VM/freshness/identity policy failed")}
    let managerEpoch=UUID().uuidString.lowercased()
    for (now,stamp,fresh): (Int64,Int64,Bool) in [(1000,2000,true),(1000,2001,false),(6000,1000,true),(6001,1000,false)] {
        let remaining=VMResources.remaining(value(true,stamp),expectedRuntimeHash:hash,now:now)
        let sample=ResourceSample(sampledAt:now,physical:64<<30,available:32<<30,vmAvailable:4<<30,diskFree:100<<30,
                                  cpu:0,pressure:.normal,thermal:.nominal,vmSampledAt:stamp,cpuSampledAt:now)
        let report=try ResourceObservationExport.encode(sample:sample,gpu:nil,gpuSampledAt:nil,now:now,epoch:managerEpoch,sequence:1,vmEpoch:hash)
        guard remaining==(fresh ? 4<<30:nil),report.resources["vmAvailable"] as? UInt64==remaining,
              (report.observation["vm_epoch"] as? String)==(fresh ? hash:nil) else {
            fatalError("VM envelope and projection disagree at an exact clock boundary")
        }
    }
    print("PASS: whole-VM capacity policy distinguishes configured cap from remaining bytes, fences partial/stale/foreign/impossible readings; real global sensor integration outstanding")
}
