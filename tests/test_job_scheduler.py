from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest

from backend.enrollment import Ledger, Rejected, STUDIOS
from backend.job_ledger import JobLedger, RESIDENT
from backend.job_protocol import worker
from backend.scheduler import MIB, Scheduler


class SchedulerTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.state = Path(temp.name) / "state"
        Ledger.initialize(self.state)
        self.now = 1000
        self.enrollment = Ledger(self.state, wall=lambda: self.now, clock=lambda: self.now)
        self.path = self.state / "jobs.sqlite"
        JobLedger.initialize(self.path)
        self.jobs = JobLedger(self.path, wall=lambda: self.now)
        self.scheduler = Scheduler(self.jobs, self.enrollment)
        self.pins = dict(zip(STUDIOS, ("a" * 64, "b" * 64)))
        self.sessions = {}
        self.seq = dict.fromkeys(STUDIOS, 0)
        for node in STUDIOS:
            self.enrollment.change("approve", node, None, machine=node, pin=self.pins[node])
            self.sessions[node] = self.enrollment.open_session(node, self.pins[node])

    def call(self, node, op, **fields):
        return worker(self.scheduler, f"/v1/jobs/{op}", node, self.pins[node],
                      {"version": 1, "node": node, "session": self.sessions[node], **fields})

    def observe(self, node, available=1024*MIB, resident=None):
        self.seq[node] += 1
        self.enrollment.accept(node, self.pins[node], dict(
            version=1, node=node, sampled_at=self.now, memory_bytes=2048*MIB, logical_cpus=2,
            load_1m=0, sequence=self.seq[node], session=self.sessions[node]))
        self.call(node, "capacity", sequence=self.seq[node], sampled_at=self.now,
                  available_bytes=available, resident_revision=resident)

    def submit(self, key="once", size="single", owner="operator"):
        return self.jobs.submit(owner, dict(incarnation=self.jobs.context(), key=key,
                                            profile=f"fake-{size}-v1", tokens=20, deadline=200))["id"]

    def get(self, job):
        return self.jobs.get("operator", job)

    @staticmethod
    def fields(grant):
        return {key: grant[key] for key in ("epoch", "job", "generation", "grant")}

    def reconcile(self, node):
        c = self.call(node, "poll")["challenge"]
        self.observe(node)
        fields = dict(challenge=c, sequence=self.seq[node], disposition="quiescent")
        self.call(node, "cleaned", **fields)
        self.call(node, "cleaned", **fields)

    def test_concurrent_constrained_placement_100_rounds(self):
        a, b = STUDIOS
        with ThreadPoolExecutor(max_workers=2) as pool:
            for trial in range(100):
                self.now += 11
                self.observe(a)
                self.observe(b, available=0)
                pair = self.submit(f"pair-{trial}", "pair")
                first = self.submit(f"a-{trial}")
                second = self.submit(f"b-{trial}")
                gate = threading.Barrier(2)

                def claim(slot):
                    gate.wait(timeout=2)
                    return self.call(slot, "poll")

                left, right = (pool.submit(claim, slot) for slot in STUDIOS)
                self.assertEqual(left.result(timeout=2)["job"], first)
                self.assertEqual(right.result(timeout=2)["action"], "wait")
                self.assertEqual(self.get(first)["slots"], [a])
                self.assertEqual(self.get(second)["slots"], [])
                self.assertEqual(self.get(pair)["slots"], [])
                for job in (pair, first, second):
                    self.scheduler.cancel("operator", job)
                self.reconcile(a)

    def test_pair_start_barrier_and_failure(self):
        a, b = STUDIOS
        self.observe(a)
        job = self.submit(size="pair")
        self.assertEqual(self.call(a, "poll")["action"], "wait")
        self.observe(b)
        left = self.fields(self.call(a, "poll"))
        right = self.fields(self.call(b, "poll"))
        self.assertEqual(self.get(job)["slots"], list(STUDIOS))
        self.call(a, "ready", **left)
        self.assertEqual(self.call(a, "poll")["action"], "prepare")
        with self.assertRaisesRegex(Rejected, "fenced"):
            self.call(a, "ready", **right)
        self.call(b, "ready", **right)
        self.assertEqual(self.call(a, "poll")["action"], "start")
        with self.assertRaisesRegex(Rejected, "usage_authority"):
            self.call(b, "finish", **right, result="ok", usage={})
        self.call(b, "finish", **right, result="failed")
        self.assertEqual(self.get(job)["state"], "stopping")
        with self.assertRaisesRegex(Rejected, "fenced"):
            self.call(a, "finish", **left, result="ok")
        self.reconcile(a)
        self.assertEqual(self.get(job)["slots"], [b])
        self.reconcile(b)
        self.assertEqual(self.get(job)["state"], "failed")

    def test_pair_requires_both_successes_and_estimates_never_accrue_cost(self):
        for node in STUDIOS:
            self.observe(node)
        job = self.submit(size="pair")
        left, right = [self.fields(self.call(node, "poll")) for node in STUDIOS]
        self.call(STUDIOS[0], "ready", **left)
        self.call(STUDIOS[1], "ready", **right)
        self.call(STUDIOS[0], "finish", **left, result="ok",
                  usage={"output": {"kind": "estimated", "value": 0}})
        self.assertEqual(self.get(job)["state"], "running")
        self.call(STUDIOS[1], "finish", **right, result="ok")
        final = self.get(job)
        self.assertEqual(final["state"], "succeeded")
        self.assertEqual(final["usage"]["counts"]["input"], {"kind": "unknown"})
        self.assertEqual(final["usage"]["measured"], {})
        self.assertIsNone(final["usage"]["cost"])

    def test_stale_or_replayed_capacity_does_not_admit(self):
        a = STUDIOS[0]
        self.observe(a)
        self.now += 31
        with self.assertRaisesRegex(Rejected, "stale_capacity"):
            self.call(a, "capacity", sequence=self.seq[a], sampled_at=self.now,
                      available_bytes=1024*MIB, resident_revision=None)
        job = self.submit()
        self.assertEqual(self.call(a, "poll")["action"], "wait")
        self.assertEqual(self.get(job)["state"], "queued")

    def test_revocation_fences_running_grant_and_keeps_slot_held(self):
        a = STUDIOS[0]
        self.observe(a)
        job = self.submit()
        ticket = self.fields(self.call(a, "poll"))
        self.call(a, "ready", **ticket)
        self.enrollment.change("revoke", a, self.pins[a])
        self.scheduler.sweep()
        with self.assertRaisesRegex(Rejected, "identity"):
            self.call(a, "finish", **ticket, result="ok")
        self.assertEqual(self.get(job)["state"], "stopping")
        self.assertEqual(self.get(job)["slots"], [a])
        self.assertIsNone(self.get(job)["usage"])

    def test_cancel_and_finish_race_has_one_terminal_outcome(self):
        a = STUDIOS[0]
        self.observe(a)
        job = self.submit()
        ticket = self.fields(self.call(a, "poll"))
        self.call(a, "ready", **ticket)
        gate = threading.Barrier(2)

        def finish():
            gate.wait(timeout=2)
            try:
                self.call(a, "finish", **ticket, result="ok")
            except Rejected as error:
                self.assertEqual(error.reason, "fenced")

        def cancel():
            gate.wait(timeout=2)
            self.scheduler.cancel("operator", job)

        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(action) for action in (finish, cancel)]
            for future in futures:
                future.result(timeout=2)
        self.assertEqual(self.get(job)["slots"], [a])
        self.reconcile(a)
        terminal = [event["state"] for event in self.jobs.events("operator", job, 0)
                    if event["state"] in ("succeeded", "cancelled")]
        self.assertEqual(terminal, [self.get(job)["state"]])

    def test_measured_estimated_and_replay(self):
        a, = STUDIOS[:1]
        self.observe(a)
        job = self.submit()
        ticket = self.fields(self.call(a, "poll"))
        self.call(a, "ready", **ticket)
        usage = {"input": {"kind": "measured", "value": 10},
                 "output": {"kind": "estimated", "value": 4}}
        with self.assertRaises(Rejected):
            self.call(a, "finish", **ticket, result="ok", usage={"input": {"kind":"unknown","value":0}})
        for _ in range(2):
            self.call(a, "finish", **ticket, result="ok", usage=usage)
        result = self.get(job)
        self.assertEqual(result["usage"]["counts"], usage)
        self.assertEqual(result["usage"]["measured"], {"input": 10})
        self.assertEqual(result["usage"]["cost"]["amount"], "0.10")
        self.assertTrue(result["usage"]["cost"]["partial"])
        self.assertEqual(result["slots"], [a])
        with self.assertRaisesRegex(Rejected, "conflict"):
            self.call(a, "finish", **ticket, result="ok", usage=usage | {
                "output": {"kind": "measured", "value": 4}})
        self.reconcile(a)
        self.assertEqual(self.get(job)["state"], "succeeded")
        self.assertEqual([e["state"] for e in self.jobs.events("operator", job, 0)],
                         ["queued", "preparing", "running", "succeeded"])

    def test_restart_expiry_and_cancellation_keep_holds(self):
        a, b = STUDIOS
        self.observe(a)
        first = self.submit()
        ticket = self.fields(self.call(a, "poll"))
        self.scheduler = Scheduler(self.jobs, self.enrollment)
        with self.assertRaisesRegex(Rejected, "fenced"):
            self.call(a, "finish", **ticket, result="ok")
        self.assertEqual(self.get(first)["slots"], [a])
        self.reconcile(a)
        self.assertEqual(self.get(first)["state"], "failed")
        second = self.submit("two")
        ticket = self.fields(self.call(a, "poll"))
        self.now += 15
        with self.assertRaisesRegex(Rejected, "fenced"):
            self.call(a, "renew", **ticket)
        self.assertEqual(self.get(second)["state"], "stopping")
        self.reconcile(a)
        self.assertEqual(self.get(second)["state"], "expired")
        self.observe(b)
        third = self.submit("three")
        grant = self.fields(self.call(a, "poll"))
        self.call(a, "ready", **grant)
        self.assertEqual(self.scheduler.cancel("operator", third)["state"], "stopping")
        self.reconcile(a)
        self.assertEqual(self.get(third)["state"], "cancelled")

    def test_unload_excludes_claim_and_requires_post_cleanup_sample(self):
        a, b = STUDIOS
        for _ in range(7):
            self.observe(a, resident=RESIDENT)
            self.now += 10
        unload = self.call(a, "poll")
        self.assertEqual(unload["action"], "unload")
        job = self.submit()
        self.assertEqual(self.call(a, "poll")["challenge"], unload["challenge"])
        self.assertEqual(self.get(job)["state"], "queued")
        with self.assertRaisesRegex(Rejected, "cleanup_required"):
            self.call(a, "cleaned", sequence=self.seq[a], challenge=unload["challenge"],
                      disposition="quiescent")
        self.reconcile(a)
        self.assertEqual(self.call(a, "poll")["job"], job)
        self.assertEqual(self.get(job)["slots"], [a])

    def test_warm_preference_and_atomic_pair_failure(self):
        a, b = STUDIOS
        self.observe(a)
        self.observe(b, available=128*MIB, resident=RESIDENT)
        single = self.submit()
        self.assertEqual(self.call(a, "poll")["action"], "wait")
        self.assertEqual(self.call(b, "poll")["job"], single)
        self.scheduler.cancel("operator", single)
        self.reconcile(b)
        pair = self.submit("pair", "pair")
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TRIGGER fail_pair BEFORE INSERT ON holds WHEN NEW.slot='studio-b' "
                       "BEGIN SELECT RAISE(ABORT,'synthetic'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            self.call(a, "poll")
        self.assertEqual(self.get(pair)["slots"], [])
        self.assertEqual(self.get(pair)["state"], "queued")
