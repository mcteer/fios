import Foundation
import Darwin
import Dispatch

struct CPUSampler {
    private var previous:([UInt32],Int64)?
    // A failed sample breaks the interval, not the accepted clock history.
    private var clockWatermark:Int64=0
    mutating func observe(ticks:[UInt32]?,now:Int64)->Double? {
        guard (clockWatermark...ActivityPolicy.maximumTimestamp).contains(now) else {previous=nil;return nil}
        clockWatermark=now
        guard let ticks,ticks.count==4 else {previous=nil;return nil}
        defer { previous=(ticks,now) }
        guard let prior=previous,now>prior.1,now-prior.1<=5000 else { return nil }
        let deltas=zip(ticks,prior.0).map { UInt64($0 &- $1) }
        let total=deltas.reduce(0,+)
        // A reset/hotplug discontinuity is not billions of elapsed ticks.
        // Genuine UInt32 wrap has a small modular delta at the 2s cadence.
        guard total>0,deltas.allSatisfy({$0<=1_000_000}) else { return nil }
        return Double(total-deltas[Int(CPU_STATE_IDLE)])/Double(total)*100
    }
    // Mach supplies no collection timestamp. A bounded read may use its
    // original start, but a failed or late read must break the interval.
    mutating func measure(now:()->Int64=HostResources.nowMilliseconds,
                          uptime:()->UInt64={DispatchTime.now().uptimeNanoseconds},read:()->[UInt32]?=readTicks)->(value:Double,at:Int64)? {
        let started=uptime(),start=now()
        guard (clockWatermark...ActivityPolicy.maximumTimestamp).contains(start) else {previous=nil;return nil}
        let ticks=read()
        let end=now(),ended=uptime()
        guard (start...ActivityPolicy.maximumTimestamp).contains(end),end-start<=5000,
              ended>=started,ended-started<=5_000_000_000 else {
            _=observe(ticks:nil,now:start)
            return nil
        }
        return observe(ticks:ticks,now:start).map {($0,start)}
    }
    static func readTicks()->[UInt32]? {
        let host=mach_host_self();defer { _=mach_port_deallocate(mach_task_self_,host) }
        return readTicks {buffer,count in host_statistics(host,HOST_CPU_LOAD_INFO,buffer,&count)}
    }
    static func readTicks(_ read:(UnsafeMutablePointer<integer_t>,inout mach_msg_type_number_t)->kern_return_t)->[UInt32]? {
        var statistics=host_cpu_load_info_data_t()
        let expected=mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size/MemoryLayout<integer_t>.size)
        var count=expected
        let code=withUnsafeMutablePointer(to:&statistics) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(expected)) { read($0,&count) }
        }
        guard code==KERN_SUCCESS,count==expected else { return nil }
        return withUnsafePointer(to:&statistics.cpu_ticks) { pointer in
            pointer.withMemoryRebound(to:UInt32.self,capacity:4) { Array(UnsafeBufferPointer(start:$0,count:4)) }
        }
    }
}
