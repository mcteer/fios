import Foundation
import CoreFoundation
import IOKit

public struct GPUSample:Sendable {
    public let utilization:Double?
    public let inUseBytes:UInt64?
    public let allocatedBytes:UInt64?
    public init(utilization:Double?,inUseBytes:UInt64?,allocatedBytes:UInt64?) {
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
        let utilization=number("Device Utilization %").flatMap{$0.doubleValue<=100 ? $0.doubleValue:nil}
        func bytes(_ name:String)->UInt64? {
            WireScalar.integer(fields[name]).map(UInt64.init)
        }
        let inUse=bytes("In use system memory"),allocated=bytes("Alloc system memory")
        guard utilization != nil || inUse != nil || allocated != nil else {return nil}
        return GPUSample(utilization:utilization,inUseBytes:inUse,allocatedBytes:allocated)
    }
    // Registry counters carry no device collection clock. The local read
    // start bounds their observation age without claiming device freshness.
    static func observation(now:()->Int64=HostResources.nowMilliseconds,read:()->GPUSample?=sample)->(sample:GPUSample,at:Int64)? {
        let start=now()
        guard (0...WireScalar.maximumTimestamp).contains(start),let sample=read() else {return nil}
        let end=now()
        guard (start...WireScalar.maximumTimestamp).contains(end),end-start<=5000 else {return nil}
        return (sample,start)
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
