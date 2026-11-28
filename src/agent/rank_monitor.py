"""Sample a native rank from its worker process, independently of MLX."""

from concurrent.futures import ThreadPoolExecutor
import json
import os
import signal
import socket
from subprocess import SubprocessError

from backend.enrollment import Rejected
from backend.moe_measurements import MAX_SAMPLE_GAP_MS
from .macos_memory import footprint, headroom
from .moe_watchdog import RankWatchdog, swap_used


EVENTS = {b"l": "load", b"p": "prefill", b"d": "decode"}
COMMANDS = {phase: event for event, phase in EVENTS.items()}
PHASE_TIMEOUT = MAX_SAMPLE_GAP_MS / 1000


class RankPhases:
    def __init__(self, channel):
        self.channel = channel
        self.channel.settimeout(PHASE_TIMEOUT)

    def phase(self, name):
        self.exchange(COMMANDS[name])

    def exchange(self, event):
        # Wait for the independent sample before proceeding into a new phase.
        self.channel.sendall(event)
        if self.channel.recv(1) != b"+":
            raise Rejected("rank_observation_unavailable", 409)


def rank_sample(memory, pid):
    available, pressure = headroom(memory)
    _, peak = footprint(pid)
    return available, pressure, peak, swap_used()


def observe_rank(channel, child, budget, attempt, *, sample=rank_sample):
    watchdog = RankWatchdog(**budget, sample=lambda memory: sample(memory, child.pid))
    channel.settimeout(0.5)
    try:
        watchdog.phase("load")
        expected = iter((b"l", b"p", b"d", b"e"))
        while True:
            try:
                event = channel.recv(1)
            except TimeoutError:
                watchdog.poll()
                continue
            if not event:
                return None
            if event != next(expected, None):
                raise Rejected("rank_observation_unavailable", 409)
            if event == b"e":
                if len(watchdog.summaries) != len(EVENTS):
                    raise Rejected("rank_observation_unavailable", 409)
                evidence = watchdog.evidence(attempt)
                channel.sendall(b"+")
                return evidence
            if event == b"l":
                watchdog.poll()
            else:
                watchdog.phase(EVENTS[event])
            channel.sendall(b"+")
    except (OSError, ValueError, SubprocessError):
        if child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        raise


def supervised_rank(spawn, work, timeout):
    control, channel = socket.socketpair()
    with control, channel:
        child = spawn(channel.fileno())
        payload = dict(work, phase_fd=channel.fileno())
        channel.close()
        with ThreadPoolExecutor(max_workers=1) as monitor:
            observation = monitor.submit(observe_rank, control, child, work["watchdog"],
                                         work["identity"]["attempt"])
            try:
                stdout, _ = child.communicate(json.dumps(payload).encode("utf-8"), timeout=timeout)
            except BaseException:
                control.shutdown(socket.SHUT_RDWR)
                raise
            evidence = observation.result()
        if child.returncode == 0 and evidence is None:
            raise Rejected("rank_observation_unavailable", 409)
        return child, stdout, evidence
