"""Storage regressions for the private chat ledger."""
from concurrent.futures import ThreadPoolExecutor
import sqlite3
import tempfile
from pathlib import Path
from threading import Barrier
import unittest

from backend.conversations import ConversationStore
from backend.enrollment import Rejected
from backend.job_ledger import JobLedger, usage_counts, usage_view


class LedgerFixture(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.path = Path(folder.name) / "jobs.sqlite"
        JobLedger.initialize(self.path)
        self.jobs = JobLedger(self.path)


class ChatLedgerTests(LedgerFixture):
    def test_migration_preserves_populated_v1_and_allows_mini_hold(self):
        old = self.jobs.submit("owner", dict(incarnation=self.jobs.context(), key="one",
                                             profile="fake-single-v1", tokens=8, deadline=60))
        with self.jobs.transaction() as db:
            db.execute("INSERT INTO holds(slot,job,kind) VALUES ('studio-a',?,'cleanup')",
                       (old["id"],))
        self.jobs.migrate()
        self.jobs.migrate()
        jobs = JobLedger(self.path)
        self.assertEqual(jobs.get("owner", old["id"])["slots"], ["studio-a"])
        self.assertEqual(jobs.events("owner", old["id"], 0)[0]["state"], "queued")
        with jobs.transaction() as db:
            db.execute("INSERT INTO holds(slot,kind) VALUES ('fios-core','cleanup')")

    def test_real_restore_of_v1_snapshot_fences_all_slots(self):
        snapshot = self.path.with_name("backup.sqlite")
        self.jobs.backup(snapshot)
        self.jobs.migrate()
        self.jobs.restore(snapshot)
        with self.jobs.transaction(write=False) as db:
            holds = {row["slot"] for row in db.execute("SELECT slot FROM holds")}
            self.assertEqual(holds, {"fios-core", "studio-a", "studio-b"})
            self.assertFalse(JobLedger.restoring(db))

    def test_directional_usage_has_no_fake_tariff(self):
        counts = usage_counts({"input": {"kind": "measured", "value": 21}}, 8, input_limit=32)
        self.assertEqual(counts["output"], {"kind": "unknown"})
        self.assertIsNone(usage_view('{"input":{"kind":"measured","value":21}}',
                                     synthetic=False)["cost"])
        with self.assertRaises(Rejected):
            usage_counts({"output": {"kind": "measured", "value": 21}}, 8, input_limit=32)


class ConversationStorageTests(LedgerFixture):
    def setUp(self):
        super().setUp()
        self.store = ConversationStore(self.jobs, b"k" * 32, quota=70_000)

    def test_owner_quota_race_replay_delete_and_reuse(self):
        first = self.store.create("alice", "first")
        second = self.store.create("alice", "second")
        gate = Barrier(2)
        incarnation = self.jobs.context()

        def submit(item):
            conversation, key = item
            gate.wait(timeout=3)
            try:
                return self.store.submit("alice", conversation, incarnation, key, None,
                                         "coding", "Calculate a total", False)
            except Rejected as error:
                return error.reason

        with ThreadPoolExecutor(2) as pool:
            results = list(pool.map(submit, ((first, "one"), (second, "two"))))
        self.assertIn("quota", results)
        admitted = next(result for result in results if isinstance(result, dict))
        loser = second if admitted["conversation"] == first else first
        with self.assertRaisesRegex(Rejected, "quota"):
            self.store.submit("alice", loser, incarnation, "next", None, "coding", "Sum", False)
        winning_key = "one" if loser == second else "two"
        self.assertEqual(self.store.submit("alice", admitted["conversation"], incarnation,
                                           winning_key, None, "coding", "Calculate a total", False),
                         admitted)
        with self.assertRaises(Rejected):
            self.store.delete("bob", admitted["conversation"])
        self.store.delete("alice", admitted["conversation"])
        next_turn = self.store.submit("alice", loser, incarnation, "next", None,
                                      "coding", "Sum", False)
        self.assertEqual(next_turn["conversation"], loser)

    def test_settlement_and_restore_release_quota_without_leaking_content(self):
        first = self.store.create("alice", "first")
        second = self.store.create("alice", "second")
        snapshot = self.path.with_name("backup.sqlite")
        self.jobs.backup(snapshot)
        incarnation = self.jobs.context()
        original = self.store.submit("alice", first, incarnation, "turn1", None,
                                     "general-chat", "Original prompt", False)
        with self.jobs.transaction() as db:
            self.jobs.transition(db, original["job"], "cancelled", "test")
        pending = self.store.submit("alice", second, incarnation, "turn2", None,
                                    "general-chat", "Second prompt", False)
        self.jobs.restore(snapshot)
        with self.assertRaisesRegex(Rejected, "ledger_changed"):
            self.store.submit("alice", second, incarnation, "turn2", None,
                              "general-chat", "Second prompt", False)
        replacement = self.store.submit("alice", second, self.jobs.context(), "turn3",
                                        pending["job"], "general-chat", "Explicit retry", False)
        self.assertNotEqual(replacement["job"], pending["job"])
        self.assertNotIn("Original prompt", self.jobs.path.read_bytes().decode("utf-8", "ignore"))

    def test_full_content_database_rolls_back_the_linked_job_and_quota(self):
        class FullContentStore(ConversationStore):
            full = False

            def attach(self, db):
                super().attach(db)
                if self.full:
                    pages = db.execute("PRAGMA content.page_count").fetchone()[0]
                    db.execute(f"PRAGMA content.max_page_count={pages}")

        store = FullContentStore(self.jobs, b"k" * 32, quota=100_000)
        conversation = store.create("alice", "first")
        arguments = ("alice", conversation, self.jobs.context(), "entry", None,
                     "general-chat", "fixture " * 1800, False)
        store.full = True
        with self.assertRaises(sqlite3.OperationalError) as failure:
            store.submit(*arguments)
        self.assertEqual(failure.exception.sqlite_errorcode, sqlite3.SQLITE_FULL)
        self.assertEqual(store.read("alice", conversation, "policy")["turns"], [])
        with self.jobs.transaction(write=False) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM jobs").fetchone()[0], 0)
        store.full = False
        stored = store.submit(*arguments)
        self.assertEqual(store.read("alice", conversation, "policy")["turns"][0]["job"], stored["job"])

    def test_changed_digest_key_cannot_replay_a_prior_chat_receipt(self):
        conversation = self.store.create("alice", "first")
        request = ("alice", conversation, self.jobs.context(), "turn", None,
                   "coding", "Sum the fixture rows.", False)
        original = self.store.submit(*request)
        reopened = ConversationStore(self.jobs, b"j" * 32)
        with self.assertRaisesRegex(Rejected, "conflict"):
            reopened.submit(*request)
        self.assertEqual(self.store.submit(*request), original)
