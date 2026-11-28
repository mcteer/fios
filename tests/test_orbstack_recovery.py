from pathlib import Path
import subprocess
import unittest

from backend.orbstack_recovery import OrbStackRecovery


class OrbStackRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.now = 10
        self.orb = Path("/test/orb")
        self.docker = Path("/test/docker")
        self.calls = []
        self.codes = {}
        self.recovery = OrbStackRecovery(self.orb, self.docker, run=self.run_command,
                                         clock=lambda: self.now)

    def run_command(self, arguments, *, timeout, **_options):
        self.assertGreater(timeout, 0)
        command = tuple(arguments)
        self.calls.append(command)
        return subprocess.CompletedProcess(command, self.codes.get(command, 0))

    def test_stopped_engine_starts_once_and_reports_only_observed_recovery(self):
        probe = (self.orb, "status")
        self.codes[probe] = 1
        self.assertEqual(self.recovery.check(), "starting")
        self.assertEqual(self.recovery.check(), "stopped")
        self.assertEqual(self.calls.count((self.orb, "start")), 1)
        self.codes[probe] = 0
        self.assertEqual(self.recovery.check(), "ready")

    def test_docker_unavailability_must_repeat_before_restart(self):
        probe = (self.docker, "--context", "orbstack", "info", "--format", "{{.ServerVersion}}")
        self.codes[probe] = 1
        self.assertEqual(self.recovery.check(), "docker_unavailable")
        self.assertEqual(self.recovery.check(), "restarting_docker")
        self.assertEqual(self.recovery.check(), "docker_unavailable")
        self.assertEqual(self.calls.count((self.orb, "restart", "docker")), 1)

    def test_starting_or_unknown_status_never_restarts(self):
        for state in (2, 3):
            self.codes[(self.orb, "status")] = state
            for _ in range(4):
                self.recovery.check()
        self.assertTrue(all(args == (self.orb, "status") for args in self.calls))
