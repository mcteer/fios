import Foundation
import Darwin

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
    func replacingVM(_ value:UInt64?,sampledAt vmAt:Int64? = nil)->ResourceSample {
        ResourceSample(sampledAt:sampledAt,physical:physical,available:available,vmAvailable:value,diskFree:diskFree,cpu:cpu,pressure:pressure,thermal:thermal,vmSampledAt:value==nil ? nil : vmAt,diskCommitted:diskCommitted,lowPowerMode:lowPowerMode)
    }
}

public enum HostResources {
    public static func nowMilliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    public static func sample(statePath: String, verifiedVMAvailable: UInt64? = nil, verifiedVMAt:Int64? = nil, measuredCPU: Double? = nil) -> ResourceSample {
        // Keep the oldest collection edge; a slow later sensor must not
        // refresh earlier CPU/memory readings on return.
        let sampledAt = nowMilliseconds()
        let physical = ProcessInfo.processInfo.physicalMemory
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host=mach_host_self()
        defer { _=mach_port_deallocate(mach_task_self_,host) }
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        // Deliberately conservative: count only genuinely free pages; no
        // speculative reclaim of cached/compressed/native-model allocations.
        let available: UInt64? = status == KERN_SUCCESS ? min(UInt64(statistics.free_count) * UInt64(getpagesize()), physical) : nil
        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let pressureKnown = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0
        let pressure: MemoryPressure = !pressureKnown ? .unknown : (level == 1 ? .normal : (level == 2 ? .warning : (level == 4 ? .critical : .unknown)))
        // Load average is not CPU utilization. First/stalled/missing tick
        // measurements remain unknown until the persistent sampler can compare.
        let cpu = measuredCPU.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
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
        return ResourceSample(sampledAt: sampledAt, physical: physical,
                              available: available, vmAvailable: verifiedVMAvailable,
                              diskFree: disk, cpu: cpu, pressure: pressure, thermal: thermal,
                              vmSampledAt:verifiedVMAvailable==nil ? nil : verifiedVMAt,
                              lowPowerMode:ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
