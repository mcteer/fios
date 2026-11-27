from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import patch

from backend.enrollment import Rejected
from backend.job_ledger import JobLedger


class JobLedgerTests(unittest.TestCase):
    def test_busy_store_changes_neither_job_nor_event(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "jobs.sqlite"
            JobLedger.initialize(path)
            ledger = JobLedger(path)
            request = dict(incarnation=ledger.context(), key="retry", profile="fake-single-v1",
                           tokens=10, deadline=60)
            with closing(sqlite3.connect(path)) as lock, lock:
                lock.execute("BEGIN IMMEDIATE")
                with self.assertRaises(sqlite3.OperationalError):
                    ledger.submit("owner", request)
            self.assertEqual(ledger.list("owner", 0), [])
            job = ledger.submit("owner", request)
            self.assertEqual(len(ledger.events("owner", job["id"], 0)), 1)

    def test_concurrent_retry_full_queue_and_owner_isolation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "jobs.sqlite"
            JobLedger.initialize(path)
            ledger = JobLedger(path)
            request = dict(incarnation=ledger.context(), key="retry", profile="fake-single-v1",
                           tokens=10, deadline=60)
            barrier = threading.Barrier(2)

            def submit():
                barrier.wait(timeout=2)
                return ledger.submit("owner", request)

            with ThreadPoolExecutor(max_workers=2) as pool:
                first, second = (pool.submit(submit) for _ in range(2))
                job = first.result(timeout=2)
                self.assertEqual(second.result(timeout=2), job)
            self.assertEqual(len(ledger.events("owner", job["id"], 0)), 1)
            with self.assertRaisesRegex(Rejected, "unknown_job"):
                ledger.get("other", job["id"])
            with self.assertRaisesRegex(Rejected, "conflict"):
                ledger.submit("owner", request | {"tokens": 11})
            for index in range(15):
                ledger.submit("owner", request | {"key": f"queue-{index}"})
            with self.assertRaisesRegex(Rejected, "queue_full"):
                ledger.submit("owner", request | {"key": "overflow"})
            self.assertEqual(ledger.submit("owner", request), job)
            self.assertEqual(len(ledger.list("owner", 0)), 16)

    def test_submission_survives_restart_and_restore_rejects_old_envelope(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "jobs.sqlite"
            snapshot = path.with_name("snapshot.sqlite")
            JobLedger.initialize(path)
            ledger = JobLedger(path)
            context = ledger.context()
            first = dict(incarnation=context, key="first", profile="fake-single-v1",
                         tokens=10, deadline=60)
            initial = ledger.submit("operator", first)
            ledger.backup(snapshot)
            lost = first | {"key": "lost"}
            second = ledger.submit("operator", lost)
            self.assertEqual(JobLedger(path).submit("operator", lost), second)
            with patch("backend.job_ledger.os.replace", side_effect=InterruptedError):
                with self.assertRaises(InterruptedError):
                    ledger.restore(snapshot)
            self.assertEqual(JobLedger(path).context(), context)
            self.assertEqual(JobLedger(path).submit("operator", lost), second)
            ledger.restore(snapshot)
            restored = JobLedger(path)
            for old in (first, lost):
                with self.assertRaisesRegex(Rejected, "ledger_changed"):
                    restored.submit("operator", old)
            self.assertEqual(restored.get("operator", initial["id"])["state"], "failed")
            self.assertEqual(len(restored.list("operator", 0)), 1)
            self.assertNotEqual(restored.context(), context)
