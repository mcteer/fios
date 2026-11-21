import Foundation
import Darwin

struct VMHostFootprint:Sendable {
    let pid:Int32
    let startIdentifier:UInt64
    let resident:UInt64
    let physicalFootprint:UInt64
    let wired:UInt64

    // Observational only. These counters MUST NOT become VM free capacity
    // without reviewed proof of complete backing/accounting coverage.
    static func sample(executable:VerifiedExecutable,pid:Int32,expectedStart:UInt64? = nil)throws->VMHostFootprint {
        guard pid>1 else {throw RuntimeError.invalid}
        try executable.verify()
        func path()throws->String {
            var value=[CChar](repeating:0,count:4096)
            guard proc_pidpath(pid,&value,UInt32(value.count))>0 else {throw RuntimeError.identity}
            guard let path=String(bytes:value.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw RuntimeError.identity}
            return path
        }
        func usage()throws->rusage_info_v2 {
            var value=rusage_info_v2()
            let code=withUnsafeMutablePointer(to:&value) {$0.withMemoryRebound(to:rusage_info_t?.self,capacity:1) {proc_pid_rusage(pid,RUSAGE_INFO_V2,$0)}}
            guard code==0,value.ri_proc_start_abstime>0,value.ri_proc_exit_abstime==0 else {throw RuntimeError.identity}
            return value
        }
        let first=try usage()
        guard try path()==executable.path,expectedStart==nil || expectedStart==first.ri_proc_start_abstime else {throw RuntimeError.identity}
        let last=try usage()
        guard first.ri_proc_start_abstime==last.ri_proc_start_abstime,try path()==executable.path else {throw RuntimeError.identity}
        return VMHostFootprint(pid:pid,startIdentifier:last.ri_proc_start_abstime,resident:last.ri_resident_size,physicalFootprint:last.ri_phys_footprint,wired:last.ri_wired_size)
    }
}
