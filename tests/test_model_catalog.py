"""Admission and stop behavior for unmeasured model trials."""
import unittest

from backend.enrollment import Rejected
from backend.model_catalog import Capacity, TrialBudget
from agent.inference import monitor_trial


class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.budget = TrialBudget("fios-core", 5000, 2000, 2, 30)

    def test_first_trial_requires_fresh_headroom_before_launch(self):
        self.budget.admit(Capacity(10, 7000, "normal"), now=10)
        for sample in (Capacity(10, 6999, "normal"), Capacity(7, 7000, "normal"),
                       Capacity(10, 7000, "critical"), None):
            with self.subTest(sample=sample), self.assertRaises(Rejected):
                self.budget.admit(sample, now=10)

    def test_over_budget_stops_and_reaps_before_return(self):
        actions = []
        samples = iter((Capacity(0, 6000, "normal", 4999), Capacity(1, 6000, "normal", 5000)))
        counter = iter((0, 1))
        with self.assertRaisesRegex(Rejected, "trial_budget"):
            monitor_trial(self.budget, deadline=30, sample=lambda: next(samples),
                          quiescent=lambda: False, wait=lambda: None,
                          stop=lambda: actions.append("stop"), reap=lambda: actions.append("reap"),
                          clock=lambda: next(counter))
        self.assertEqual(actions, ["stop", "reap"])

    def test_peak_captured_between_samples_still_fails_trial(self):
        actions = []
        with self.assertRaisesRegex(Rejected, "trial_budget"):
            monitor_trial(self.budget, deadline=30,
                          sample=lambda: Capacity(1, 6000, "normal", 100, 5001),
                          quiescent=lambda: True, wait=lambda: None,
                          stop=lambda: actions.append("stop"), reap=lambda: actions.append("reap"),
                          clock=lambda: 1)
        self.assertEqual(actions, ["stop", "reap"])


class ProfileTests(unittest.TestCase):
    def manifest(self):
        return dict(alias="general-chat", host_class="m4-pro-mini", artifact="a" * 64,
                    engine="b" * 64, template="c" * 64, policy="d" * 64, evaluation="e" * 64,
                    license="Apache-2.0", context=4096, output=512, settings={"temperature": 0})

    def test_revision_identifies_exact_immutable_manifest(self):
        from backend.model_catalog import Profile

        first = self.manifest()
        profile = Profile.parse(first)
        first["settings"]["temperature"] = 1
        next_profile = Profile.parse(first)
        self.assertNotEqual(profile.revision, next_profile.revision)
        self.assertEqual(profile.document()["settings"]["temperature"], 0)

    def test_invalid_caps_and_host_are_rejected(self):
        from backend.model_catalog import Profile

        for change in ({"output": 4096}, {"host_class": "m3-ultra-studio"}, {"artifact": "main"}):
            with self.subTest(change=change), self.assertRaises(Rejected):
                Profile.parse({**self.manifest(), **change})


class RealEvidenceTests(unittest.TestCase):
    def test_real_pass_requires_report_and_a_later_failure_closes_admission(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory

        from backend.job_ledger import JobLedger
        from backend.model_catalog import Catalog, Profile

        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "jobs.sqlite"
            JobLedger.initialize(path)
            jobs = JobLedger(path)
            catalog = Catalog(jobs)
            profile = Profile.parse(ProfileTests().manifest())
            evidence = dict(slot="fios-core", peak_bytes=1000, passed=True, synthetic=False)
            with self.assertRaisesRegex(Rejected, "invalid_evidence"):
                catalog.record(profile, evidence)
            report = dict(artifact=profile.document()["artifact"], policy=profile.document()["policy"],
                          evaluation=profile.document()["evaluation"], runtime=profile.document()["engine"],
                          host_build="27.0", cold_trials=1, warm_trials=5, latency_limit_ms=5000,
                          worst_latency_ms=4000,
                          checks=dict(quality=True, publication=True, context=True,
                                      cancellation=True, cleanup=True, license=True, rollback=True))
            failed = {**report, "checks": {**report["checks"], "publication": False}}
            with self.assertRaisesRegex(Rejected, "invalid_evidence"):
                catalog.record(profile, {**evidence, "report": failed})
            catalog.record(profile, {**evidence, "report": report})
            catalog.change("general-chat", None, profile.revision)
            with jobs.transaction(write=False) as db:
                self.assertIsNotNone(catalog.active(db, "general-chat"))
            replacement = Profile.parse({**profile.document(), "output": 256})
            catalog.record(replacement, {**evidence, "report": report})
            catalog.change("general-chat", profile.revision, replacement.revision)
            with self.assertRaisesRegex(Rejected, "conflict"):
                catalog.change("general-chat", profile.revision, None)
            catalog.change("general-chat", replacement.revision, profile.revision)
            catalog.change("general-chat", profile.revision, None)
            catalog.change("general-chat", None, profile.revision)
            catalog.record(profile, {**evidence, "passed": False, "report": failed})
            with jobs.transaction(write=False) as db:
                self.assertIsNone(catalog.active(db, "general-chat"))
                trial = catalog.latest_trial(db, profile.revision, "fios-core")
                self.assertFalse(trial["passed"])
                self.assertFalse(trial["report"]["checks"]["publication"])
                self.assertIsNone(catalog.latest_trial(db, profile.revision, "studio-a"))
            with self.assertRaisesRegex(Rejected, "unqualified"):
                catalog.change("general-chat", profile.revision, profile.revision)
