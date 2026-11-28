"""Recover the local OrbStack engine from an opted-in native supervisor."""

import subprocess
import time


class OrbStackRecovery:
    def __init__(self, orb, docker, *, run=subprocess.run, clock=time.monotonic):
        self.orb = orb
        self.docker = docker
        self.run = run
        self.clock = clock
        self.next_recovery = 0
        self.docker_failures = 0

    def command(self, *arguments, timeout):
        try:
            return self.run(list(arguments), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=timeout).returncode
        except (OSError, subprocess.SubprocessError):
            return None

    def recover(self, *arguments, pending, unavailable):
        if self.clock() < self.next_recovery:
            return unavailable
        # Allocate the cooldown before attempting recovery, even if the command times out.
        self.next_recovery = self.clock() + 60
        return pending if self.command(self.orb, *arguments, timeout=12) == 0 else "recovery_failed"

    def check(self):
        status = self.command(self.orb, "status", timeout=3)
        if status != 0:
            self.docker_failures = 0
            if status == 1:
                return self.recover("start", pending="starting", unavailable="stopped")
            return "starting" if status == 2 else "unknown"
        if self.command(self.docker, "--context", "orbstack", "info", "--format",
                        "{{.ServerVersion}}", timeout=3) == 0:
            self.docker_failures = 0
            return "ready"
        self.docker_failures += 1
        if self.docker_failures < 2:
            return "docker_unavailable"
        return self.recover("restart", "docker", pending="restarting_docker",
                            unavailable="docker_unavailable")
