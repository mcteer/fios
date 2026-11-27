from contextlib import closing
import tempfile
from pathlib import Path
import sqlite3
import unittest

from backend.enrollment import Ledger, Rejected


class StoreTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.state = Path(directory.name) / "state"

    def test_explicit_initialization(self):
        with self.assertRaises((OSError, ValueError)):
            Ledger(self.state)
        self.assertFalse(self.state.exists())
        Ledger.initialize(self.state)
        with self.assertRaises(FileExistsError):
            Ledger.initialize(self.state)
        self.assertEqual(Ledger(self.state).snapshot()["studio-a"]["enrollment"], "not_enrolled")
        database = self.state / "enrollment.sqlite"
        database.unlink()
        with self.assertRaises(FileNotFoundError):
            Ledger(self.state)
        self.assertFalse(database.exists())

    def test_unsafe_parent_cannot_receive_new_ledger(self):
        parent = self.state.parent / "shared"
        parent.mkdir()
        parent.chmod(0o777)
        with self.assertRaises(ValueError):
            Ledger.initialize(parent / "state")
        self.assertFalse((parent / "state").exists())

    def test_rotation_revocation_and_restart(self):
        Ledger.initialize(self.state)
        ledger = Ledger(self.state)
        pin = "a" * 64
        replacement = "b" * 64
        ledger.change("approve", "studio-a", None, machine="edge-a", pin=pin)
        with self.assertRaises(Rejected):
            ledger.change("approve", "studio-b", None, machine="edge-a", pin=replacement)
        ledger.change("rotate", "studio-a", pin, pin=replacement)
        with self.assertRaises(Rejected):
            ledger.change("rotate", "studio-a", pin, pin=replacement)
        with self.assertRaises(Rejected):
            ledger.open_session("studio-a", pin)
        ledger.change("revoke", "studio-a", replacement)
        with self.assertRaises(Rejected):
            ledger.change("revoke", "studio-a", replacement)
        restarted = Ledger(self.state)
        self.assertEqual(restarted.snapshot()["studio-a"]["enrollment"], "revoked")
        for old_pin in (pin, replacement):
            with self.assertRaises(Rejected):
                restarted.change("approve", "studio-a", replacement, machine="edge-a", pin=old_pin)
        restarted.change("approve", "studio-a", replacement, machine="edge-a", pin="c" * 64)
        self.assertEqual(restarted.snapshot()["studio-a"]["state"], "awaiting")

    def test_failed_audit_commit_does_not_change_live_or_durable_trust(self):
        Ledger.initialize(self.state)
        ledger = Ledger(self.state, wall=lambda: 1000, clock=lambda: 5)
        pin = "a" * 64
        ledger.change("approve", "studio-a", None, machine="edge-a", pin=pin)
        session = ledger.open_session("studio-a", pin)
        heartbeat = dict(version=1, node="studio-a", session=session, sequence=1,
                         sampled_at=1000, memory_bytes=1024, logical_cpus=1, load_1m=0.5)
        ledger.accept("studio-a", pin, heartbeat)
        before = ledger.snapshot()
        with closing(sqlite3.connect(self.state / "enrollment.sqlite")) as db:
            with db:
                db.execute("CREATE TRIGGER fail_audit BEFORE INSERT ON audit "
                           "BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            ledger.change("revoke", "studio-a", pin)
        self.assertEqual(ledger.snapshot(), before)
        ledger.accept("studio-a", pin, heartbeat | {"sequence": 2})
        self.assertEqual(Ledger(self.state).snapshot()["studio-a"]["enrollment"], "active")
