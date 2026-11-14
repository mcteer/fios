import Foundation
import Darwin

struct CPUSampler {
    private var previous:([UInt32],Int64)?
    mutating func observe(ticks:[UInt32]?,now:Int64)->Double? {
        guard let ticks,ticks.count==4,now>=0,now<=ActivityPolicy.maximumTimestamp else { previous=nil;return nil }
        defer { previous=(ticks,now) }
        guard let prior=previous,now>prior.1,now-prior.1<=5000 else { return nil }
        let deltas=zip(ticks,prior.0).map { UInt64($0 &- $1) }
        let total=deltas.reduce(0,+)
        // A reset/hotplug discontinuity is not billions of elapsed ticks.
        // Genuine UInt32 wrap has a small modular delta at the 2s cadence.
        guard total>0,deltas.allSatisfy({$0<=1_000_000}) else { return nil }
        return Double(total-deltas[Int(CPU_STATE_IDLE)])/Double(total)*100
    }
    static func readTicks()->[UInt32]? {
        var statistics=host_cpu_load_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size/MemoryLayout<integer_t>.size)
        let host=mach_host_self();defer { _=mach_port_deallocate(mach_task_self_,host) }
        let code=withUnsafeMutablePointer(to:&statistics) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { host_statistics(host,HOST_CPU_LOAD_INFO,$0,&count) }
        }
        guard code==KERN_SUCCESS else { return nil }
        return withUnsafePointer(to:&statistics.cpu_ticks) { pointer in
            pointer.withMemoryRebound(to:UInt32.self,capacity:4) { Array(UnsafeBufferPointer(start:$0,count:4)) }
        }
    }
}
