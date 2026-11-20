import Foundation
import Darwin

public enum ResourceClock {
    static func valid(_ stamp:Int64)->Bool {(0...WireScalar.maximumTimestamp).contains(stamp)}
    static func age(now:Int64,sampledAt:Int64)->Int64? {
        guard valid(now),valid(sampledAt) else {return nil}
        return now-sampledAt
    }
    static func fresh(age:Int64)->Bool {(-1000...5000).contains(age)}
    public static func fresh(now:Int64,sampledAt:Int64)->Bool {
        age(now:now,sampledAt:sampledAt).map {fresh(age:$0)} ?? false
    }
}

public struct ResourceSample: Codable, Sendable {
    public let sampledAt: Int64
    public let physical: UInt64
    public let available: UInt64?
    public let vmAvailable: UInt64?
    public let diskFree: UInt64?
    public let cpu: Double?
    public let pressure: MemoryPressure
    public let thermal: ThermalState
    public var vmSampledAt:Int64? = nil
    // Full retained export reservations plus queued declarations. Keeping
    // ready bytes reserved also covers a free-space sample predating a write.
    public var diskCommitted:UInt64 = 0
    public var lowPowerMode:Bool? = nil
    public var cpuSampledAt:Int64? = nil
    func replacingVM(_ value:UInt64?,sampledAt vmAt:Int64? = nil)->ResourceSample {
        ResourceSample(sampledAt:sampledAt,physical:physical,available:available,vmAvailable:value,diskFree:diskFree,cpu:cpu,pressure:pressure,thermal:thermal,vmSampledAt:value==nil ? nil : vmAt,diskCommitted:diskCommitted,lowPowerMode:lowPowerMode,cpuSampledAt:cpuSampledAt)
    }
}

public enum HostResources {
    public static func nowMilliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    static func freeMemory(physical:UInt64,pageSize:UInt64,
                           read:(UnsafeMutablePointer<integer_t>,inout mach_msg_type_number_t)->kern_return_t)->UInt64? {
        var statistics=vm_statistics64_data_t()
        let expected=mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var count=expected
        let status=withUnsafeMutablePointer(to:&statistics) {pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(expected)) {read($0,&count)}
        }
        guard status==KERN_SUCCESS,count==expected,pageSize>0 else {return nil}
        let bytes=UInt64(statistics.free_count).multipliedReportingOverflow(by:pageSize)
        return bytes.overflow ? nil:min(bytes.partialValue,physical)
    }
    static func memoryPressure(read:(inout Int32,inout Int)->Int32)->MemoryPressure {
        var level:Int32=0
        let expected=MemoryLayout<Int32>.size
        var count=expected
        guard read(&level,&count)==0,count==expected else {return .unknown}
        switch level {case 1:return .normal;case 2:return .warning;case 4:return .critical;default:return .unknown}
    }
    public static func sample(statePath: String, verifiedVMAvailable: UInt64? = nil, verifiedVMAt:Int64? = nil, measuredCPU: Double? = nil, measuredCPUAt:Int64? = nil) -> ResourceSample {
        // Stamp host sensors before collection. CPU has its own observation
        // clock, which must not age the independent host sensors.
        let collectedAt = nowMilliseconds()
        // Load average is not utilization. Missing tick measurements or their
        // original collection time remain unknown, rather than gaining this clock.
        let cpuObservation = measuredCPU.flatMap { value -> (value: Double, at: Int64)? in
            guard value.isFinite, (0...100).contains(value), let time = measuredCPUAt,
                  let age=ResourceClock.age(now:collectedAt,sampledAt:time),
                  age>=0,ResourceClock.fresh(age:age) else { return nil }
            return (value, time)
        }
        let physical = ProcessInfo.processInfo.physicalMemory
        let host=mach_host_self()
        defer { _=mach_port_deallocate(mach_task_self_,host) }
        // Deliberately conservative: count only genuinely free pages; no
        // speculative reclaim of cached/compressed/native-model allocations.
        let available=freeMemory(physical:physical,pageSize:UInt64(getpagesize())) {buffer,count in
            host_statistics64(host,HOST_VM_INFO64,buffer,&count)
        }
        let pressure=memoryPressure {level,size in sysctlbyname("kern.memorystatus_vm_pressure_level",&level,&size,nil,0)}
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: statePath)
        let disk = (attributes?[.systemFreeSize] as? NSNumber)?.uint64Value
        let thermal: ThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .unknown
        }
        // Unsupported pressure observation stays unknown; never synthesize
        // normal from available bytes.
        return ResourceSample(sampledAt: collectedAt, physical: physical,
                              available: available, vmAvailable: verifiedVMAvailable,
                              diskFree: disk, cpu: cpuObservation?.value, pressure: pressure, thermal: thermal,
                              vmSampledAt:verifiedVMAvailable==nil ? nil : verifiedVMAt,
                              lowPowerMode:ProcessInfo.processInfo.isLowPowerModeEnabled,cpuSampledAt:cpuObservation?.at)
    }
}
