import Darwin

// proc_pid_rusage CPU times use Mach absolute ticks on supported macOS.
// Do not divide them directly by1e9 (arm64 timebase is not necessarily1:1).
enum ProcessCPU {
    static func seconds(ticks:UInt64)->Double {
        var clock=mach_timebase_info_data_t()
        guard mach_timebase_info(&clock)==KERN_SUCCESS,clock.numer>0,clock.denom>0 else {return .infinity}
        return Double(ticks)*Double(clock.numer)/Double(clock.denom)/1e9
    }
}
