import base64
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from threading import Barrier
import unittest

from backend.enrollment import Rejected, STUDIOS
from backend.job_protocol import OWNER, TRIAL_OWNER, operator
from backend.model_catalog import Catalog, Profile
from backend.pair_trial import GIB, paired_rdma
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

    def observe(self, node, available=1024*MIB, version=2, memory=2048*MIB, large_revision=None):
        self.seq[node] += 1
        self.enrollment.accept(node, self.pins[node], dict(
            version=1, node=node, sampled_at=self.now, memory_bytes=memory, logical_cpus=2,
            load_1m=0, sequence=self.seq[node], session=self.sessions[node]))
        self.call(node, "capacity", version=version, sequence=self.seq[node], sampled_at=self.now,
                  available_bytes=available, resident_revision=None, pressure="normal",
                  **({"large_revision": large_revision, "single_capable": True} if version == 3 else {}))

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


        # A real-shaped comparable report is assembled through the worker
        # protocol above. Stage checks must still keep probe and full separate.
        from backend.moe_suite import CASES

        browser_prompt = "A short private fixture."
        frozen = dict.fromkeys(CASES, FIXTURE)
        frozen["cold"] = sha256(browser_prompt.encode()).hexdigest()
        suite = catalog.register_large_suite(dict(
            fixtures=frozen, rubric="8" * 64, policy=profile.document()["policy"]))
        large = Profile.parse(dict(profile.document(), alias="large-moe", evaluation=suite,
                                   artifact="0" * 64, placement="studio_pair_only"))
        catalog.register_large(large)
        plan = dict(candidate=large.revision, comparable=profile.revision,
                    incarnation=self.jobs.context(),
                    budgets={slot: dict(disk_bytes=2 * GIB, peak_bytes=GIB) for slot in STUDIOS},
                    observations={slot: dict(sampled_at=self.now, disk_free=8 * GIB,
                                             headroom=64 * GIB, pressure="normal") for slot in STUDIOS})
        files = {"probe.safetensors": {"bytes": 100, "sha256": "f" * 64}}
        approval = catalog.decide_large_stage(dict(plan, stage="probe", files=files))
        self.assertEqual(approval["decision"], "approved")
        self.assertEqual(catalog.large_stage_authority(
            large.revision, approval["approval"], "probe")["files"], files)
        with self.assertRaisesRegex(Rejected, "stage_approval_unavailable"):
            catalog.large_stage_authority(large.revision, approval["approval"], "full")
        with self.assertRaisesRegex(Rejected, "invalid_trial_receipts"):
            catalog.decide_large_stage(dict(plan, stage="full", probe_job=paired, pack_bytes=GIB))
        self.scheduler.trial_recipes["large-probe"] = dict(
            recipes["paired"], candidate=large.revision, stage="probe",
            artifact=large.document()["artifact"], placement="studio_pair_only",
            budgets={slot: dict(ceiling=GIB, floor=32 * GIB) for slot in STUDIOS})
        envelope = dict(action="large-trial-submit", incarnation=self.jobs.context(), key="probe",
                        candidate=large.revision, recipe="large-probe", approval=approval["approval"])
        job = operator(self.scheduler, "large-trial-submit", envelope)["job"]["id"]
        self.observe(A, 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
        self.observe(B, 64 * GIB, version=2, memory=256 * GIB)
        self.assertEqual(self.call(A, "poll", version=3)["action"], "wait")
        self.assertEqual(self.jobs.get(TRIAL_OWNER, job)["slots"], [])
        self.observe(B, 64 * GIB, version=3, memory=256 * GIB, large_revision=profile.revision)
        self.assertEqual(self.call(A, "poll", version=3)["action"], "wait")
        self.observe(B, 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
        self.assertEqual(self.call(A, "poll", version=2)["action"], "wait")
        grants = {}
        for rank, slot in enumerate(STUDIOS):
            offer = self.call(slot, "poll", version=3)
            self.assertEqual((offer["trial"]["rank"], offer["trial"]["world_size"]), (rank, 2))
            self.assertEqual(offer["trial"]["approval"], approval["approval"])
            grants[slot] = self.fields(offer)
        for slot in STUDIOS:
            self.call(slot, "ready", version=3, **grants[slot])

        from backend.moe_measurements import PHASES

        phases = [dict(phase=phase, first_ms=index * 100, last_ms=(index + 1) * 100,
                       max_gap_ms=100, min_headroom_bytes=32 * GIB, peak_footprint_bytes=128 * MIB,
                       max_swap_growth_bytes=0, worst_pressure="normal")
                  for index, phase in enumerate(PHASES)]
        for slot in STUDIOS:
            finish = dict(grants[slot], result="ok", trial_measurement=dict(
                peak_bytes=128*MIB, first_text_ms=200, elapsed_ms=600, fixture_passed=True,
                completed_tokens=16, timing=dict(input_tokens=128, prefill_ms=120, decode_ms=300)),
                transport_evidence=dict(
                attempt=job, candidate=large.revision, device=DEVICES[slot],
                transfers=[dict(id="forward", count=1, transport="rdma",
                                direction="send" if slot == A else "receive")]))
            with self.assertRaisesRegex(Rejected, "invalid_phase_evidence"):
                self.call(slot, "finish", version=3, **finish)
            self.call(slot, "finish", version=3, phase_observation=dict(attempt=job, phases=phases),
                      **finish)
        with self.assertRaisesRegex(Rejected, "trial_not_clean"):
            catalog.decide_large_stage(dict(plan, stage="full", probe_job=job, pack_bytes=GIB))
        for slot in STUDIOS:
            test_job_scheduler.SchedulerTests.reconcile(self, slot)
        full = catalog.decide_large_stage(dict(plan, stage="full", probe_job=job, pack_bytes=GIB))
        self.assertEqual(full["decision"], "approved")

        self.now += 11
        self.scheduler.trial_recipes["large-review"] = dict(
            self.scheduler.trial_recipes["large-probe"], stage="full", review="campaign", case="campaign-1")
        reviewed = operator(self.scheduler, "large-trial-submit", dict(
            envelope, key="review", recipe="large-review", approval=full["approval"]))["job"]["id"]
        for slot in STUDIOS:
            self.observe(slot, 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
        review_grants = {slot: self.fields(self.call(slot, "poll", version=3)) for slot in STUDIOS}
        for slot in STUDIOS:
            self.call(slot, "ready", version=3, **review_grants[slot])

        output = b"Visit the orchard, then return to the tide bell."
        frame = dict(sequence=0, data=base64.b64encode(output).decode())
        proof = dict(frames=1, digest=sha256(output).hexdigest())
        with self.assertRaisesRegex(Rejected, "review_authority"):
            self.call(B, "review-append", version=3, **review_grants[B], **frame)
        self.call(A, "review-append", version=3, **review_grants[A], **frame)
        self.call(A, "review-append", version=3, **review_grants[A], **frame)
        arguments = {}
        for slot, direction in zip(STUDIOS, ("send", "receive"), strict=True):
            arguments[slot] = dict(review_grants[slot], result="ok",
                                   phase_observation=dict(attempt=reviewed, phases=phases),
                                   trial_measurement=finish["trial_measurement"],
                                   transport_evidence=dict(
                                       attempt=reviewed, candidate=large.revision, device=DEVICES[slot],
                                       transfers=[dict(id="forward", count=1, transport="rdma",
                                                       direction=direction)]))
            if slot == A:
                arguments[slot]["review_output"] = proof
            self.call(slot, "finish", version=3, **arguments[slot])
        sample = self.scheduler.reviews.samples[reviewed]
        with self.jobs.transaction(write=False) as db:
            with self.assertRaisesRegex(Rejected, "review_output_unavailable"):
                self.scheduler.reviews.page(db, sample.blind, 0)
        for slot in STUDIOS:
            test_job_scheduler.SchedulerTests.reconcile(self, slot)
        grade = dict(canon_fidelity=4, narrative_clarity=5, session_usability=4)
        with self.jobs.transaction() as db:
            self.assertEqual(base64.b64decode(self.scheduler.reviews.page(db, sample.blind, 0)["data"]),
                             output)
            with self.assertRaisesRegex(Rejected, "review_output_mismatch"):
                self.scheduler.reviews.grade(db, sample.blind, "0" * 64, grade)
            self.assertEqual(self.scheduler.reviews.grade(db, sample.blind, proof["digest"], grade), reviewed)
        del self.scheduler.reviews.samples[reviewed]
        self.call(A, "finish", version=3, **arguments[A])
        with self.jobs.transaction(write=False) as db:
            self.assertEqual(self.scheduler.reviews.grade(db, sample.blind, proof["digest"], grade), reviewed)
            with self.assertRaisesRegex(Rejected, "conflict"):
                self.scheduler.reviews.grade(db, sample.blind, proof["digest"], dict(grade, canon_fidelity=5))
            self.assertEqual(db.execute("SELECT digest FROM large_review_verdicts WHERE job=?",
                                        (reviewed,)).fetchone()["digest"], proof["digest"])
            with self.assertRaisesRegex(Rejected, "review_output_unavailable"):
                self.scheduler.reviews.page(db, sample.blind, 0)
        self.exercise_rehearsal(catalog, large, profile.revision, full, phases, browser_prompt)
        self.now += 30
        self.assertEqual(operator(self.scheduler, "large-trial-submit", envelope)["job"]["id"], job)
        with self.assertRaisesRegex(Rejected, "stage_approval_unavailable"):
            catalog.large_stage_authority(large.revision, approval["approval"], "probe")

        # Exercise the v3 reservation transaction concurrently with an older
        # single-Studio recipe. Each competing poll belongs to its own slot.
        with ThreadPoolExecutor(max_workers=2) as pool:
            for index in range(100):
                self.now += 11
                for observation in plan["observations"].values():
                    observation["sampled_at"] = self.now
                refreshed = catalog.decide_large_stage(dict(plan, stage="probe", files=files))
                candidate = operator(self.scheduler, "large-trial-submit", dict(
                    envelope, key=f"large-{index}", approval=refreshed["approval"]))["job"]["id"]
                older = operator(self.scheduler, "pair-trial-submit", dict(
                    action="pair-trial-submit", incarnation=self.jobs.context(), key=f"single-{index}",
                    candidate=profile.revision, recipe="baseline"))["job"]["id"]

                self.observe(A, 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
                self.observe(B, 0 if index % 2 else 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
                barrier = Barrier(2)

                def poll(slot):
                    barrier.wait(timeout=2)
                    return self.call(slot, "poll", version=3)

                futures = [pool.submit(poll, slot) for slot in STUDIOS]
                for outcome in futures:
                    outcome.result(timeout=3)
                expected = [] if index % 2 else list(STUDIOS)
                self.assertEqual(self.jobs.get(TRIAL_OWNER, candidate)["slots"], expected)
                legacy_slots = [A] if index % 2 else []
                self.assertEqual(self.jobs.get(TRIAL_OWNER, older)["slots"], legacy_slots)
                self.scheduler.cancel(TRIAL_OWNER, candidate)
                self.scheduler.cancel(TRIAL_OWNER, older)
                for slot in expected + legacy_slots:
                    test_job_scheduler.SchedulerTests.reconcile(self, slot)


    def exercise_rehearsal(self, catalog, large, comparable, full, phases, prompt):
        from backend.chat_dispatch import Dispatch
        from backend.conversations import ConversationStore

        self.now += 11
        store = ConversationStore(self.jobs, b"x" * 32, catalog=catalog)
        self.scheduler.dispatch = Dispatch(self.scheduler, store, lambda *_: True,
                                          policy_revision=large.document()["policy"])
        # Stand in for the native-case and policy gates above the browser.
        # Ordinary promotion must still reject these disposable records.
        catalog.rehearsal = dict(id="a" * 32, candidate=large.revision, comparable=comparable,
                                 incarnation=self.jobs.context(), approval=full["approval"],
                                 expires=self.now + 300, native={})
        owner = "local-moe-rehearsal"
        cid = store.create(owner, "fixture")
        with self.assertRaisesRegex(Rejected, "unqualified"):
            store.submit(owner, cid, self.jobs.context(), "normal", None, "large-moe", prompt, False)
        with self.assertRaisesRegex(Rejected, "unregistered_rehearsal_case"):
            store.submit(owner, cid, self.jobs.context(), "wrong", None, "large-moe",
                         "Different fixture", False, rehearsal=True)
        job = store.submit(owner, cid, self.jobs.context(), "browser", None, "large-moe", prompt,
                           False, rehearsal=True)["job"]
        for slot in STUDIOS:
            self.observe(slot, 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
        grants = {slot: self.fields(self.call(slot, "poll", version=3)) for slot in STUDIOS}
        for slot in STUDIOS:
            self.call(slot, "ready", version=3, **grants[slot])

        def payload(operation, **fields):
            return self.scheduler.dispatch.handle(operation, A, self.sessions[A], {**grants[A], **fields},
                                                  authorize_peer=lambda: None)
        self.assertEqual(self.call(A, "poll", version=3)["action"], "start")
        for _ in range(3):
            self.now += 6
            for slot in STUDIOS:
                self.observe(slot, 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
            self.call(A, "renew", version=3, **grants[A])
            self.assertEqual(self.call(B, "poll", version=3)["action"], "prepare")
            self.call(B, "ready", version=3, **grants[B])
        payload("prompt", cursor=0)
        self.assertEqual(self.call(B, "poll", version=3)["action"], "start")
        payload("append", sequence=0, data=base64.b64encode(b"Approved fixture answer.").decode())
        payload("publish", frames=1)
        self.assertEqual(store.read(owner, cid, large.document()["policy"])["turns"][0]["answer"], "")
        for slot, direction in zip(STUDIOS, ("send", "receive"), strict=True):
            self.call(slot, "finish", version=3, **grants[slot], result="ok",
                      phase_observation=dict(attempt=job, phases=phases),
                      trial_measurement=dict(peak_bytes=128 * MIB, first_text_ms=200, elapsed_ms=600,
                                             fixture_passed=True, completed_tokens=16,
                                             timing=dict(input_tokens=128, prefill_ms=120, decode_ms=300)),
                      transport_evidence=dict(attempt=job, candidate=large.revision, device=DEVICES[slot],
                                              transfers=[dict(id="step", count=1, transport="rdma",
                                                              direction=direction)]))
        report = dict(job=job, candidate=large.revision, suite=large.document()["evaluation"],
                      case="cold", visible_ms=750)
        with store.transaction() as db:
            with self.assertRaisesRegex(Rejected, "rehearsal_job_unavailable"):
                catalog.record_rehearsal_observation(db, report)
        for slot in STUDIOS:
            test_job_scheduler.SchedulerTests.reconcile(self, slot)
        self.assertEqual(store.read(owner, cid, large.document()["policy"])["turns"][0]["answer"],
                         "Approved fixture answer.")
        with store.transaction() as db:
            with self.assertRaisesRegex(Rejected, "rehearsal_job_mismatch"):
                catalog.record_rehearsal_observation(db, dict(report, case="warm-1"))
            catalog.record_rehearsal_observation(db, report)
            catalog.record_rehearsal_observation(db, report)
            with self.assertRaisesRegex(Rejected, "conflict"):
                catalog.record_rehearsal_observation(db, dict(report, visible_ms=800))
            with self.assertRaisesRegex(Rejected, "invalid_rehearsal_report"):
                catalog.record_large_qualification(db, {"cold": job})
        with self.assertRaisesRegex(Rejected, "unqualified"):
            catalog.change("large-moe", None, large.revision)

        # Seed the disposition produced by a completed release suite so the
        # real alias and scheduler can exercise withdrawal while a turn runs.
        from backend.job_ledger import encoded

        budgets = {slot: dict(floor=32 * GIB, ceiling=GIB) for slot in STUDIOS}
        with self.jobs.transaction() as db:
            db.execute("INSERT INTO large_qualifications VALUES (?,?,?,?,?)",
                       (large.revision, self.jobs.incarnation(db), comparable,
                        encoded(dict.fromkeys(STUDIOS, 32 * GIB + 128 * MIB)),
                        encoded(dict(budgets=budgets))))
        catalog.change("large-moe", None, large.revision)
        live = store.create(OWNER, "withdraw-live")
        pending = store.submit(OWNER, live, self.jobs.context(), "withdraw-live", None,
                               "large-moe", prompt, False)["job"]
        for slot in STUDIOS:
            self.observe(slot, 64 * GIB, version=3, memory=256 * GIB, large_revision=large.revision)
        for slot in STUDIOS:
            offer = self.call(slot, "poll", version=3)
            self.assertEqual(offer["job"], pending)
            self.call(slot, "ready", version=3, **self.fields(offer))
        self.assertEqual(self.jobs.get(OWNER, pending)["state"], "running")
        catalog.change("large-moe", large.revision, None)
        self.scheduler.sweep()
        self.assertEqual(self.jobs.get(OWNER, pending)["state"], "stopping")
        self.assertEqual(store.read(OWNER, live, large.document()["policy"])["turns"][0]["answer"], "")
        catalog.change("large-moe", None, large.revision)
        for slot in STUDIOS:
            test_job_scheduler.SchedulerTests.reconcile(self, slot)
        self.assertEqual(self.jobs.get(OWNER, pending)["reason"], "profile_unavailable")
        self.assertEqual(store.read(owner, cid, large.document()["policy"])["turns"][0]["answer"],
                         "Approved fixture answer.")
