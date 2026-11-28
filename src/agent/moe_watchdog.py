"""Sample actual rank resources from before load through the end of decode."""

from contextlib import contextmanager
import ctypes
import os
from subprocess import SubprocessError
import threading
import time

from backend.enrollment import Rejected
from backend.moe_measurements import MAX_SAMPLE_GAP_MS, PHASES
from .macos_memory import footprint, headroom


class SwapUsage(ctypes.Structure):
    # xsw_usage from the macOS SDK. Read bytes directly to avoid display rounding.
    _fields_ = [("total", ctypes.c_uint64), ("available", ctypes.c_uint64),
                ("used", ctypes.c_uint64), ("page_size", ctypes.c_uint32),
                ("encrypted", ctypes.c_int32)]


def swap_used():
    sysctl = ctypes.CDLL(None, use_errno=True).sysctlbyname
    sysctl.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t),
                       ctypes.c_void_p, ctypes.c_size_t]
    data = SwapUsage()
    size = ctypes.c_size_t(ctypes.sizeof(data))
    if sysctl(b"vm.swapusage", ctypes.byref(data), ctypes.byref(size), None, 0) != 0:
        raise OSError(ctypes.get_errno(), "Could not measure used swap")
    if size.value != ctypes.sizeof(data) or data.used > data.total:
        raise ValueError("Invalid used swap observation")
    return data.used


def rank_sample(memory):
    available, pressure = headroom(memory)
    _, peak = footprint(os.getpid())
    return available, pressure, peak, swap_used()


class RankWatchdog:
    def __init__(self, *, memory, floor, ceiling, baseline, sample=rank_sample, clock=time.monotonic):
        self.memory, self.floor, self.ceiling = memory, floor, ceiling
        self.sample, self.clock = sample, clock
        self.started = clock()
        self.baseline = baseline
        self.summaries = []
        self.lock = threading.Lock()

    def read(self):
        available, pressure, peak, swap = self.sample(self.memory)
        if (pressure != "normal" or not self.floor <= available <= self.memory
                or not 0 < peak < self.ceiling or not 0 <= swap <= self.baseline):
            raise Rejected("unsafe_rank_resources", 409)
        return int((self.clock() - self.started) * 1000), available, peak

    def record(self, reading):
        timestamp, available, peak = reading
        summary = self.summaries[-1]
        gap = timestamp - summary["last_ms"]
        if not 0 <= gap <= MAX_SAMPLE_GAP_MS:
            raise Rejected("stale_rank_resources", 409)
        summary["last_ms"] = timestamp
        summary["max_gap_ms"] = max(summary["max_gap_ms"], gap)
        summary["min_headroom_bytes"] = min(summary["min_headroom_bytes"], available)
        summary["peak_footprint_bytes"] = max(summary["peak_footprint_bytes"], peak)

    def phase(self, name):
        with self.lock:
            if len(self.summaries) >= len(PHASES) or name != PHASES[len(self.summaries)]:
                raise ValueError("Invalid resource phase transition")
            reading = self.read()
            if self.summaries:
                self.record(reading)
            elif not 0 <= reading[0] <= MAX_SAMPLE_GAP_MS:
                raise Rejected("stale_rank_resources", 409)
            stamp, available, peak = reading
            self.summaries.append(dict(phase=name, first_ms=stamp, last_ms=stamp, max_gap_ms=0,
                                       min_headroom_bytes=available, peak_footprint_bytes=peak,
                                       max_swap_growth_bytes=0, worst_pressure="normal"))

    def poll(self):
        with self.lock:
            self.record(self.read())

    def evidence(self, attempt):
        self.poll()
        return dict(attempt=attempt, phases=self.summaries)

    @contextmanager
    def monitoring(self, *, abort=os._exit):
        self.phase("load")
        finished = threading.Event()

        def watch():
            while not finished.wait(0.5):
                try:
                    self.poll()
                except (OSError, ValueError, SubprocessError):
                    # A blocked MLX call cannot handle a Python exception on
                    # this thread. The owning worker reaps the failed rank.
                    abort(78)
                    return

        monitor = threading.Thread(target=watch, daemon=True)
        monitor.start()
        try:
            yield
        finally:
            finished.set()
            monitor.join(timeout=2.5)
            if monitor.is_alive():
                abort(78)
