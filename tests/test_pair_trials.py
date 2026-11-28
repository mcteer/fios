from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import unittest

from backend.enrollment import Rejected, STUDIOS
from backend.job_protocol import OWNER, TRIAL_OWNER, operator
from backend.model_catalog import Catalog, Profile
from backend.pair_trial import paired_rdma
from backend.scheduler import MIB, Scheduler

import test_job_scheduler

A, B = STUDIOS
REVISION = "a" * 64
FIXTURE = "b" * 64
DEVICES = {A: "c" * 64, B: "d" * 64}


class PairTrialTests(unittest.TestCase):
    setUp = test_job_scheduler.SchedulerTests.setUp
    fields = staticmethod(test_job_scheduler.SchedulerTests.fields)

    def configure(self):
        self.scheduler = Scheduler(self.jobs, self.enrollment, catalog=Catalog(self.jobs),
                                   trial_recipes={"comparison": {
                                       "candidate": REVISION, "fixture": FIXTURE,
                                       "engine": "mlx-lm", "devices": DEVICES,
                                       "tokens": 20, "deadline": 50,
                                       "budgets": {slot: {"ceiling": 256*MIB, "floor": 64*MIB}
                                                   for slot in STUDIOS},
                                   }})

    def call(self, node, op, **fields):
        return test_job_scheduler.SchedulerTests.call(self, node, op, **{"version": 2, **fields})

    def observe(self, node, available=1024*MIB, version=2):
        self.seq[node] += 1
        self.enrollment.accept(node, self.pins[node], dict(
            version=1, node=node, sampled_at=self.now, memory_bytes=2048*MIB, logical_cpus=2,
            load_1m=0, sequence=self.seq[node], session=self.sessions[node]))
        self.call(node, "capacity", version=version, sequence=self.seq[node], sampled_at=self.now,
                  available_bytes=available, resident_revision=None, pressure="normal")

    def submit(self):
        return operator(self.scheduler, "pair-trial-submit", {
            "action": "pair-trial-submit", "incarnation": self.jobs.context(), "key": "once",
            "candidate": REVISION, "recipe": "comparison",
        })["job"]["id"]

    def test_disabled_candidate_requires_two_capable_hosts_and_is_idempotent(self):
        self.configure()
        job = self.submit()
        self.assertEqual(self.submit(), job)
        self.observe(A)
        self.observe(B, version=1)
        self.assertEqual(self.call(A, "poll")["action"], "wait")
        self.assertEqual(self.jobs.get(TRIAL_OWNER, job)["slots"], [])
        self.observe(B)
        left = self.call(A, "poll")
        right = self.call(B, "poll")
        self.assertEqual(self.jobs.get(TRIAL_OWNER, job)["slots"], list(STUDIOS))
        self.call(A, "ready", **self.fields(left))
        self.observe(A, available=0)
        self.call(B, "ready", **self.fields(right))
        self.assertEqual(self.call(B, "poll")["action"], "prepare")
        self.observe(A)
        self.call(A, "ready", **self.fields(left))
        self.assertEqual(self.call(B, "poll")["action"], "start")

    def test_one_studio_work_never_creates_half_a_pair_under_contention(self):
        self.configure()
        paired = self.scheduler.trial_recipes["comparison"]
        self.scheduler.trial_recipes["baseline"] = dict(
            paired, devices={A: DEVICES[A]}, budgets={A: paired["budgets"][A]})
        with ThreadPoolExecutor(max_workers=2) as pool:
            for index in range(100):
                self.now += 11
                self.observe(A)
                self.observe(B, available=0)

                def submit(recipe):
                    return self.scheduler.submit_trial(TRIAL_OWNER, dict(
                        incarnation=self.jobs.context(), key=f"{recipe}-{index}",
                        candidate=REVISION, recipe=recipe))["id"]

                pair = submit("comparison")
                single = submit("baseline")
                gate = Barrier(2)

                def poll(slot):
                    gate.wait(timeout=2)
                    return self.call(slot, "poll")

                left = pool.submit(poll, A)
                right = pool.submit(poll, B)
                self.assertEqual(left.result(timeout=2)["job"], single)
                self.assertEqual(right.result(timeout=2)["action"], "wait")
                self.assertEqual(self.jobs.get(TRIAL_OWNER, pair)["slots"], [])
                self.assertEqual(self.jobs.get(TRIAL_OWNER, single)["slots"], [A])
                self.scheduler.cancel(TRIAL_OWNER, pair)
                self.scheduler.cancel(TRIAL_OWNER, single)
                test_job_scheduler.SchedulerTests.reconcile(self, A)

    def test_tcp_attempt_fails_without_usage_or_user_content(self):
        self.configure()
        job = self.submit()
        for slot in STUDIOS:
            self.observe(slot)
        grants = {slot: self.fields(self.call(slot, "poll")) for slot in STUDIOS}
        for slot in STUDIOS:
            self.call(slot, "ready", **grants[slot])
        with self.assertRaisesRegex(Rejected, "usage_authority"):
            self.call(A, "finish", **grants[A], result="ok", usage={})
        for slot, direction in zip(STUDIOS, ("send", "receive"), strict=True):
            self.call(slot, "finish", **grants[slot], result="ok", transport_evidence={
                "device": DEVICES[slot], "candidate": REVISION, "attempt": job,
                "transfers": [{"id": "step-1", "direction": direction,
                               "transport": "tcp", "count": 1}],
            })
        view = self.jobs.get(TRIAL_OWNER, job)
        self.assertEqual(view["state"], "stopping")
        self.assertEqual(view["reason"], "transport_mismatch")
        self.assertIsNone(view["usage"])

    def test_successful_trial_stays_held_until_each_host_proves_cleanup(self):
        self.configure()
        job = self.submit()
        with self.assertRaisesRegex(Rejected, "unknown_job"):
            self.scheduler.cancel(OWNER, job)
        for slot in STUDIOS:
            self.observe(slot)
        grants = {slot: self.fields(self.call(slot, "poll")) for slot in STUDIOS}
        for slot in STUDIOS:
            self.call(slot, "ready", **grants[slot])
        with self.scheduler.jobs.transaction() as db:
            with self.assertRaisesRegex(Rejected, "fenced"):
                self.scheduler.authorize_payload(db, A, self.sessions[A], grants[A])
        for slot, direction in ((B, "receive"), (A, "send")):
            evidence = {
                "device": DEVICES[slot], "candidate": REVISION, "attempt": job,
                "transfers": [{"id": "step-1", "direction": direction,
                               "transport": "rdma", "count": 1}],
            }
            with self.assertRaisesRegex(Rejected, "transport_identity"):
                self.call(slot, "finish", **grants[slot], result="ok",
                          transport_evidence={**evidence, "attempt": "0" * 32})
            measurement = dict(peak_bytes=128*MIB, first_text_ms=184, elapsed_ms=600,
                               fixture_passed=True, completed_tokens=14)
            with self.assertRaisesRegex(Rejected, "invalid"):
                self.call(slot, "finish", **grants[slot], result="ok", transport_evidence=evidence,
                          trial_measurement={**measurement, "peak_bytes": 257*MIB})
            self.call(slot, "finish", **grants[slot], result="ok", transport_evidence=evidence,
                      trial_measurement=measurement)
        self.assertEqual(self.jobs.get(TRIAL_OWNER, job)["state"], "stopping")
        test_job_scheduler.SchedulerTests.reconcile(self, A)
        self.assertEqual(self.jobs.get(TRIAL_OWNER, job)["slots"], [B])
        test_job_scheduler.SchedulerTests.reconcile(self, B)
        result = operator(self.scheduler, "pair-trial-inspect",
                          {"action": "pair-trial-inspect", "job": job})["job"]
        self.assertEqual(result["state"], "succeeded")
        self.assertEqual(set(result["ranks"][A]), {"result", "transport_evidence", "trial_measurement"})
        self.assertEqual(result["ranks"][A]["trial_measurement"]["first_text_ms"], 184)
        self.assertEqual(result["slots"], [])
        self.assertIsNone(result["usage"])

    def test_restart_fences_trial_before_capacity_returns(self):
        self.configure()
        job = self.submit()
        for slot in STUDIOS:
            self.observe(slot)
        grants = {slot: self.fields(self.call(slot, "poll")) for slot in STUDIOS}
        self.configure()
        with self.assertRaisesRegex(Rejected, "fenced"):
            self.call(A, "ready", **grants[A])
        result = self.jobs.get(TRIAL_OWNER, job)
        self.assertEqual(result["reason"], "core_restart")
        self.assertEqual(result["slots"], list(STUDIOS))
        test_job_scheduler.SchedulerTests.reconcile(self, A)
        self.assertEqual(self.jobs.get(TRIAL_OWNER, job)["slots"], [B])
        test_job_scheduler.SchedulerTests.reconcile(self, B)
        self.assertEqual(self.jobs.get(TRIAL_OWNER, job)["state"], "failed")

    def test_admin_status_reports_rank_readiness_without_grants(self):
        self.configure()
        self.submit()
        self.observe(A)
        self.observe(B)
        offer = self.call(A, "poll")
        self.call(A, "ready", **self.fields(offer))
        status = self.scheduler.pair_status()
        self.assertEqual(status["state"], "preparing")
        self.assertEqual(status["ranks"], [
            {"slot": A, "fresh": True, "phase": "ready"},
            {"slot": B, "fresh": True, "phase": "reserved"},
        ])
        self.assertNotIn(offer["grant"], str(status))
        self.assertNotIn(offer["job"], str(status))

    def test_transport_verifier_rejects_incomplete_or_mixed_model_traffic(self):
        send = dict(id="forward", direction="send", transport="rdma", count=2)
        receive = dict(send, direction="receive")
        left = dict(attempt="one", transfers=[send])
        right = dict(attempt="one", transfers=[receive])
        self.assertTrue(paired_rdma(left, right))
        for invalid in (
            None, dict(right, transfers=[]), dict(right, attempt="other"),
            dict(right, transfers=[dict(receive, count=1)]),
            dict(right, transfers=[receive, dict(receive, id="fallback", transport="tcp")]),
        ):
            with self.subTest(invalid=invalid):
                self.assertFalse(paired_rdma(left, invalid))

    def test_joint_promotion_requires_hardware_runs_with_independent_cleanup(self):
        profile = Profile.parse(dict(alias="paired-coding", host_class="m3-ultra-pair",
                                     artifact="a" * 64, engine="b" * 64, template="c" * 64,
                                     policy="d" * 64, evaluation="e" * 64, license="Apache-2.0",
                                     context=4096, output=128, settings={"temperature": 0},
                                     devices=DEVICES))
        recipes = {}
        for name, slots in (("baseline", (A,)), ("paired", STUDIOS)):
            recipes[name] = dict(candidate=profile.revision, fixture=FIXTURE, engine="mlx-lm",
                                 devices={slot: DEVICES[slot] for slot in slots}, tokens=20, deadline=50,
                                 budgets={slot: {"ceiling": 256*MIB, "floor": 64*MIB} for slot in slots})
        self.scheduler = Scheduler(self.jobs, self.enrollment, catalog=Catalog(self.jobs),
                                   trial_recipes=recipes, trial_hardware=True)
        catalog = self.scheduler.catalog

        def execute(name, slots, *, cleanup=True):
            job = operator(self.scheduler, "pair-trial-submit", {
                "action": "pair-trial-submit", "incarnation": self.jobs.context(), "key": name,
                "candidate": profile.revision, "recipe": name,
            })["job"]["id"]
            for slot in slots:
                self.observe(slot)
            grants = {slot: self.fields(self.call(slot, "poll")) for slot in slots}
            for slot in slots:
                self.call(slot, "ready", **grants[slot])
            for slot in slots:
                result = dict(result="ok", trial_measurement=dict(
                    peak_bytes=128*MIB, first_text_ms=200, elapsed_ms=600,
                    fixture_passed=True, completed_tokens=16,
                ))
                if len(slots) == 2:
                    result["transport_evidence"] = dict(
                        attempt=job, candidate=profile.revision, device=DEVICES[slot],
                        transfers=[dict(id="forward", count=1, transport="rdma",
                                        direction="send" if slot == A else "receive")],
                    )
                self.call(slot, "finish", **grants[slot], **result)
            if cleanup:
                for slot in slots:
                    test_job_scheduler.SchedulerTests.reconcile(self, slot)
            return job

        baseline = execute("baseline", (A,))
        paired = execute("paired", STUDIOS, cleanup=False)
        report = dict(baseline=baseline, paired=paired, cold_trials=1, warm_trials=5,
                      worst_latency_ms=300, latency_limit_ms=500,
                      checks=dict.fromkeys(("quality", "publication", "context", "cancellation",
                                            "cleanup", "license", "rollback", "tcp_rejected",
                                            "link_loss", "rank_loss"), True))
        with self.assertRaisesRegex(Rejected, "trial_not_clean"):
            catalog.record_joint(profile, report)
        for slot in STUDIOS:
            test_job_scheduler.SchedulerTests.reconcile(self, slot)
        with self.jobs.transaction() as db:
            intent = db.execute("SELECT intent FROM jobs WHERE id=?", (paired,)).fetchone()["intent"]
            db.execute("UPDATE jobs SET intent=? WHERE id=?", (intent.replace('"hardware":true','"hardware":false'), paired))
        with self.assertRaisesRegex(Rejected, "invalid_trial_receipts"):
            catalog.record_joint(profile, report)
        with self.jobs.transaction() as db:
            db.execute("UPDATE jobs SET intent=? WHERE id=?", (intent, paired))
        catalog.record_joint(profile, report)
        catalog.change("paired-coding", None, profile.revision)
        with self.jobs.transaction(write=False) as db:
            active = catalog.active(db, "paired-coding")
            self.assertEqual(active["peaks"], dict.fromkeys(STUDIOS, 192*MIB))
