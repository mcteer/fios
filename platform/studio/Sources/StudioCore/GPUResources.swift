import Foundation
import CoreFoundation
import IOKit

public struct GPUSample:Sendable {
    public let utilization:Double
    public let inUseBytes:UInt64?
    public let allocatedBytes:UInt64?
    public init(utilization:Double,inUseBytes:UInt64?,allocatedBytes:UInt64?) {
        self.utilization=utilization;self.inUseBytes=inUseBytes;self.allocatedBytes=allocatedBytes
    }
}

enum GPUResources {
    // Observational driver counters, NOT proof of native request completion or
    // allocatable unified memory. Missing keys never become zero readings.
    static func decode(_ fields:[String:Any])->GPUSample? {
        func number(_ name:String)->NSNumber? {
            guard let value=fields[name] as? NSNumber,CFGetTypeID(value) != CFBooleanGetTypeID(),value.doubleValue.isFinite,value.doubleValue>=0 else {return nil};return value
        }
        guard let utilization=number("Device Utilization %")?.doubleValue,utilization<=100 else {return nil}
        func bytes(_ name:String)->UInt64? {
            guard let value=number(name),value.doubleValue<=Double(ActivityPolicy.maximumTimestamp),value.doubleValue.rounded(.down)==value.doubleValue else {return nil};return value.uint64Value
        }
        return GPUSample(utilization:utilization,inUseBytes:bytes("In use system memory"),allocatedBytes:bytes("Alloc system memory"))
    }
    static func sample()->GPUSample? {
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AGXAccelerator"),&iterator)==KERN_SUCCESS else {return nil}
        defer {IOObjectRelease(iterator)}
        let service=IOIteratorNext(iterator)
        guard service != 0 else {return nil};defer {IOObjectRelease(service)}
        let additional=IOIteratorNext(iterator)
        if additional != 0 {IOObjectRelease(additional);return nil} // No invented multi-device aggregation.
        guard let value=IORegistryEntryCreateCFProperty(service,"PerformanceStatistics" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? [String:Any] else {return nil}
        return decode(value)
    }
}
