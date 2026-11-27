"""Native macOS memory pressure and process high-water measurements."""

import ctypes
import re
import subprocess


def headroom(memory_bytes):
    status = subprocess.check_output(["/usr/bin/memory_pressure", "-Q"], text=True, timeout=1)
    match = re.search(r"System-wide memory free percentage: (\d{1,3})%", status)
    reading = subprocess.check_output(
        ["/usr/sbin/sysctl", "-n", "kern.memorystatus_vm_pressure_level"],
        text=True, timeout=1).strip()
    levels = {"1": "normal", "2": "warning", "4": "critical"}
    if not match or not 0 <= int(match[1]) <= 100 or reading not in levels:
        raise ValueError("Could not verify memory pressure and headroom")
    # Whole-percent reporting is rounded. Budget one percentage point below it.
    return memory_bytes * max(0, int(match[1]) - 1) // 100, levels[reading]


class RUsageV4(ctypes.Structure):
    # The xnu rusage_info_v4 ABI starts with a 16-byte UUID and consecutive
    # uint64 counters. Preserve the full size expected by proc_pid_rusage.
    _fields_ = [
        ("uuid", ctypes.c_uint8 * 16),
        ("before_footprint", ctypes.c_uint64 * 7),
        ("physical", ctypes.c_uint64),
        ("before_peak", ctypes.c_uint64 * 20),
        ("lifetime_peak", ctypes.c_uint64),
        ("after_peak", ctypes.c_uint64 * 6),
    ]


def footprint(pid):
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    read = library.proc_pid_rusage
    read.argtypes = (ctypes.c_int, ctypes.c_int, ctypes.c_void_p)
    read.restype = ctypes.c_int
    usage = RUsageV4()
    if read(pid, 4, ctypes.byref(usage)) != 0:
        raise OSError(ctypes.get_errno(), "Could not measure process footprint")
    return usage.physical, usage.lifetime_peak
