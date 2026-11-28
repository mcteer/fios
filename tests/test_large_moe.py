"""Validate the pair-only registration and admission boundary."""

import os
import socket
import unittest

from backend.enroll import admin_handler, command
from backend.heartbeat import Listener

from backend.enrollment import Rejected, STUDIOS
from backend.job_protocol import TRIAL_OWNER
from backend.model_catalog import Profile
from backend.pair_trial import PAIR_ONLY, recipe
import test_pair_trials

GIB = 1024**3


def profile_document():
    return dict(alias="large-moe", host_class="m3-ultra-pair", placement="studio_pair_only",
                artifact="1" * 64, engine="2" * 64, template="3" * 64, policy="4" * 64,
                evaluation="5" * 64, license="Apache-2.0", context=8192, output=1024,
                settings={"temperature": 0},
                devices=dict(zip(STUDIOS, ("6" * 64, "7" * 64), strict=True)))


class LargeMoeTests(unittest.TestCase):
    setUp = test_pair_trials.PairTrialTests.setUp
    configure = test_pair_trials.PairTrialTests.configure

    def test_serving_uses_the_reviewed_ceiling_and_can_repeat_observed_peak(self):
        from backend.job_ledger import encoded

        self.configure()
        catalog = self.scheduler.catalog
        profile = Profile.parse(profile_document())
        catalog.register_large(profile)
        budgets = {slot: dict(floor=32 * GIB, ceiling=160 * GIB) for slot in STUDIOS}
        observed = dict.fromkeys(STUDIOS, 150 * GIB)
        with catalog.jobs.transaction() as db:
            db.execute("INSERT INTO large_qualifications VALUES (?,?,?,?,?)",
                       (profile.revision, catalog.jobs.incarnation(db), "a" * 64,
                        encoded(observed), encoded(dict(budgets=budgets))))
            qualified = catalog.qualified(db, profile.revision, False)
            self.assertEqual(qualified["budgets"], budgets)
            self.assertEqual(qualified["peaks"], dict.fromkeys(STUDIOS, 192 * GIB))
            db.execute("UPDATE large_qualifications SET evidence='{}' WHERE candidate=?",
                       (profile.revision,))
            self.assertIsNone(catalog.qualified(db, profile.revision, False))

    def test_operator_socket_requires_local_identity_for_registration(self):
        self.configure()
        message = dict(action="large-model-register", profile=profile_document())
        for suffix, uid in (("denied", os.geteuid() + 1), ("allowed", os.geteuid())):
            path = self.state / suffix
            listener = Listener(str(path), admin_handler(
                self.enrollment, None, None, uid, self.scheduler), family=socket.AF_UNIX).start()
            self.addCleanup(listener.close)
            result = command(path, message)
            if suffix == "denied":
                self.assertEqual(result, {"ok": False, "reason": "identity"})
            else:
                self.assertEqual(result, {"ok": True, "revision": Profile.parse(message["profile"]).revision})

    def test_manifest_requires_both_studios_and_bounded_context(self):
        document = profile_document()
        profile = Profile.parse(document)
        self.assertEqual(profile.document(), document)
        for invalid in ({"placement": "single"}, {"host_class": "m4-pro-mini"},
                        {"context": 8193}, {"output": 1025},
                        {"devices": {STUDIOS[0]: "6" * 64}}):
            with self.subTest(invalid=invalid), self.assertRaises(Rejected):
                Profile.parse({**document, **invalid})

    def test_registration_survives_catalog_reopen_and_rejects_alias_relabeling(self):
        self.configure()
        catalog = self.scheduler.catalog
        profile = Profile.parse(profile_document())
        catalog.register_large(profile)
        catalog = type(catalog)(self.jobs)
        legacy = profile.document()
        for key in ("placement", "devices"):
            del legacy[key]
        legacy.update(alias="coding", host_class="m3-ultra-studio")
        with self.assertRaisesRegex(Rejected, "pair_only_artifact"):
            catalog.record(Profile.parse(legacy),
                           dict(slot=STUDIOS[0], peak_bytes=100, passed=True, synthetic=True))
        with self.assertRaisesRegex(Rejected, "unqualified"):
            catalog.change("large-moe", None, profile.revision)

    def test_older_ledger_restore_keeps_pair_only_classification(self):
        self.configure()
        snapshot = self.jobs.path.with_name("prior.sqlite")
        self.jobs.backup(snapshot)
        profile = Profile.parse(profile_document())
        self.scheduler.catalog.register_large(profile)
        self.jobs.restore(snapshot)
        catalog = type(self.scheduler.catalog)(self.jobs)
        with self.jobs.transaction(write=False) as db:
            self.assertTrue(catalog.pair_only_artifact(db, profile.document()))

    def test_registered_candidate_cannot_run_as_legacy_trial(self):
        self.configure()
        profile = Profile.parse(profile_document())
        self.scheduler.catalog.register_large(profile)
        approved = {**self.scheduler.trial_recipes["comparison"], "candidate": profile.revision}
        self.scheduler.trial_recipes["comparison"] = approved
        with self.assertRaisesRegex(Rejected, "pair_only_artifact"):
            self.scheduler.submit_trial("operator", dict(
                incarnation=self.jobs.context(), key="legacy", candidate=profile.revision,
                recipe="comparison"))
        self.assertEqual(self.scheduler.describe("operator"), [])

    def test_queued_legacy_job_is_fenced_after_registration(self):
        self.configure()
        profile = Profile.parse(profile_document())
        previous = self.scheduler.trial_recipes["comparison"]
        self.scheduler.trial_recipes["comparison"] = {**previous, "candidate": profile.revision}
        queued = self.scheduler.submit_trial(TRIAL_OWNER, dict(
            incarnation=self.jobs.context(), key="old-recipe", candidate=profile.revision,
            recipe="comparison"))
        self.assertEqual(queued["state"], "queued")
        self.scheduler.catalog.register_large(profile)
        self.scheduler.sweep()
        view = self.jobs.get(TRIAL_OWNER, queued["id"])
        self.assertEqual((view["state"], view["slots"]), ("failed", []))

    def test_probe_recipe_rejects_one_studio_or_lower_floor(self):
        profile = Profile.parse(profile_document())
        budgets = {slot: dict(floor=32 * GIB, ceiling=2 * GIB) for slot in STUDIOS}
        document = dict(candidate=profile.revision, fixture="a" * 64, engine="mlx-lm",
                        devices=profile.document()["devices"], tokens=1024, deadline=900,
                        budgets=budgets, placement="studio_pair_only", stage="probe",
                        artifact=profile.document()["artifact"])
        self.assertEqual(recipe(document), document)
        for invalid in ({"budgets": {STUDIOS[0]: budgets[STUDIOS[0]]}},
                        {"budgets": {slot: dict(floor=1, ceiling=GIB) for slot in STUDIOS}},
                        {"tokens": 1025}, {"stage": "other"}):
            with self.subTest(invalid=invalid), self.assertRaises(Rejected):
                recipe({**document, **invalid})


    def test_metadata_does_not_authorize_executable_work(self):
        self.configure()
        profile = Profile.parse(profile_document())
        self.scheduler.catalog.register_large(profile)
        with self.assertRaisesRegex(Rejected, "comparable_pair_unverified"):
            self.scheduler.catalog.evaluate_large_resources(profile.revision, "a" * 64, {}, {})
        self.scheduler.trial_recipes["comparison"] = recipe(dict(
            candidate=profile.revision, fixture=test_pair_trials.FIXTURE, engine="mlx-lm",
            devices=profile.document()["devices"], tokens=1024, deadline=900,
            budgets={slot: dict(floor=32 * GIB, ceiling=GIB) for slot in STUDIOS},
            placement="studio_pair_only", stage="probe", artifact=profile.document()["artifact"]))
        with self.assertRaisesRegex(Rejected, "large_trial_unavailable"):
            self.scheduler.submit_trial("operator", dict(
                incarnation=self.jobs.context(), key="no-approval", candidate=profile.revision,
                recipe="comparison"))

class PreflightTests(unittest.TestCase):
    def test_estimated_single_host_fit_cannot_change_pair_placement(self):
        from backend.moe_preflight import estimate_single_host

        budgets = {slot: dict(peak_bytes=160 * GIB) for slot in STUDIOS}
        for pack, expected in ((100 * GIB, True), (208 * GIB, False)):
            with self.subTest(pack=pack):
                estimate = estimate_single_host(pack, budgets)
                self.assertEqual(estimate["fits_estimate"], expected)
                self.assertEqual(estimate["placement"], PAIR_ONLY)

    def test_refuses_one_heavy_partition_even_when_aggregate_memory_fits(self):
        from backend.moe_preflight import check_host_budgets

        left, right = STUDIOS
        budgets = {left: dict(disk_bytes=300 * GIB, peak_bytes=151 * GIB),
                   right: dict(disk_bytes=300 * GIB, peak_bytes=100 * GIB)}
        observations = {slot: dict(sampled_at=100, disk_free=300 * GIB, headroom=182 * GIB,
                                   pressure="normal") for slot in STUDIOS}
        self.assertEqual(check_host_budgets(budgets, observations, now=100),
                         {"slot": left, "reason": "insufficient_headroom"})
        observations[left]["headroom"] += GIB
        self.assertIsNone(check_host_budgets(budgets, observations, now=130))
        observations[right]["disk_free"] -= 1
        self.assertEqual(check_host_budgets(budgets, observations, now=100),
                         {"slot": right, "reason": "insufficient_disk"})
        self.assertEqual(check_host_budgets(budgets, observations, now=131),
                         {"slot": left, "reason": "stale_capacity"})



class StageDecisionTests(unittest.TestCase):
    setUp = test_pair_trials.PairTrialTests.setUp
    configure = test_pair_trials.PairTrialTests.configure

    def test_stage_decisions_require_current_ledger_and_comparable_evidence(self):
        self.configure()
        catalog = self.scheduler.catalog
        profile = Profile.parse(profile_document())
        catalog.register_large(profile)
        for stage, inputs in (
            ("probe", {"files": {"probe.safetensors": {"bytes": 10, "sha256": "b" * 64}}}),
            ("full", {"probe_job": "b" * 32, "pack_bytes": GIB}),
        ):
            request = dict(candidate=profile.revision, comparable="c" * 64, stage=stage,
                           incarnation="0" * 32, budgets={}, observations={}, **inputs)
            with self.subTest(stage=stage), self.assertRaisesRegex(Rejected, "ledger_changed"):
                catalog.decide_large_stage(request)
            request["incarnation"] = self.jobs.context()
            with self.subTest(stage=stage), self.assertRaisesRegex(Rejected, "comparable_pair_unverified"):
                catalog.decide_large_stage(request)
        with self.jobs.transaction(write=False) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM large_stage_decisions").fetchone()[0], 0)

    def test_probe_allowlist_is_bounded_and_data_only(self):
        from backend.moe_preflight import probe_files

        artifact = {"sha256": "d" * 64, "bytes": 128}
        model = {"probe.safetensors": artifact}
        self.assertEqual(probe_files({**model, "config.json": artifact}), 256)
        for invalid in ({}, {"../probe.safetensors": artifact}, {**model, "run.py": artifact},
                        {**model, "extra.safetensors": dict(artifact, bytes=GIB)},
                        {"probe.safetensors": dict(artifact, bytes=True)}):
            with self.subTest(value=invalid), self.assertRaises(Rejected):
                probe_files(invalid)

    def test_probe_directory_requires_exact_file_contents(self):
        from hashlib import sha256
        from pathlib import Path
        from tempfile import TemporaryDirectory

        from backend.moe_preflight import verify_probe_directory

        data = b"synthetic weights"
        with TemporaryDirectory() as temp:
            directory = Path(temp)
            path = directory / "probe.safetensors"
            files = {path.name: dict(sha256=sha256(data).hexdigest(), bytes=len(data))}
            path.write_bytes(data)
            verify_probe_directory(directory, files)
            path.write_bytes(b"x" * len(data))
            with self.assertRaisesRegex(Rejected, "probe_file_digest"):
                verify_probe_directory(directory, files)
            (directory / "unexpected.json").touch()
            with self.assertRaisesRegex(Rejected, "unexpected_probe_file"):
                verify_probe_directory(directory, files)


class PhaseEvidenceTests(unittest.TestCase):
    def test_worker_samples_child_and_acknowledges_each_phase(self):
        from concurrent.futures import ThreadPoolExecutor
        from types import SimpleNamespace

        from agent.rank_monitor import RankPhases, observe_rank
        from backend.moe_measurements import rank_phases

        child = SimpleNamespace(pid=37, poll=lambda: 0)
        observed = []
        def sample(memory, pid):
            observed.append((memory, pid))
            return 64 * GIB, "normal", GIB, 0
        attempt = "d" * 32
        budget = dict(memory=256 * GIB, floor=32 * GIB, ceiling=4 * GIB, baseline=0)
        monitor, rank = socket.socketpair()
        with monitor, rank, ThreadPoolExecutor(max_workers=1) as pool:
            response = pool.submit(observe_rank, monitor, child, budget, attempt, sample=sample)
            emitter = RankPhases(rank)
            for phase in ("load", "prefill", "decode"):
                emitter.phase(phase)
            emitter.exchange(b"e")
            rank_phases(response.result(timeout=1), attempt=attempt, ceiling=4 * GIB, deadline_ms=5000)
        self.assertGreaterEqual(len(observed), 4)
        self.assertEqual(set(observed), {(256 * GIB, child.pid)})

    def test_each_rank_must_cover_all_phases_with_safe_resource_bounds(self):
        from backend.moe_measurements import PHASES, rank_phases

        attempt = "c" * 32
        phases = [
            dict(phase=phase, first_ms=index * 1000, last_ms=(index + 1) * 1000,
                 max_gap_ms=1000, min_headroom_bytes=32 * GIB, peak_footprint_bytes=3 * GIB,
                 max_swap_growth_bytes=0, worst_pressure="normal")
            for index, phase in enumerate(PHASES)
        ]
        report = {"attempt": attempt, "phases": phases}
        limit = {"attempt": attempt, "ceiling": 4 * GIB, "deadline_ms": 900_000}
        self.assertEqual(rank_phases(report, **limit), report)
        for changes in ({"min_headroom_bytes": 32 * GIB - 1}, {"max_swap_growth_bytes": 1},
                        {"peak_footprint_bytes": 4 * GIB}, {"worst_pressure": "warning"},
                        {"last_ms": 6000, "first_ms": 5000}, {"max_gap_ms": 2001}):
            altered = [phases[0], {**phases[1], **changes}, phases[2]]
            with self.subTest(changes=changes), self.assertRaises(Rejected):
                rank_phases(dict(report, phases=altered), **limit)
        with self.assertRaises(Rejected):
            rank_phases(dict(report, phases=phases[1:]), **limit)
        with self.assertRaises(Rejected):
            rank_phases(dict(report, attempt="d" * 32), **limit)

    def test_native_recorder_reports_transitions_and_refuses_bad_live_samples(self):
        from agent.moe_watchdog import RankWatchdog
        from backend.moe_measurements import rank_phases

        current = [32 * GIB, "normal", GIB, 4096]
        now = 1.0
        monitor = RankWatchdog(memory=256 * GIB, floor=32 * GIB, ceiling=2 * GIB,
                               baseline=4096, sample=lambda _: current, clock=lambda: now)
        monitor.phase("load")
        now += 0.5
        monitor.phase("prefill")
        now += 0.5
        monitor.phase("decode")
        now += 0.5
        attempt = "a" * 32
        report = monitor.evidence(attempt)
        self.assertEqual(rank_phases(report, attempt=attempt, ceiling=2 * GIB, deadline_ms=2000), report)
        current[3] += 1
        with self.assertRaisesRegex(Rejected, "unsafe_rank_resources"):
            monitor.poll()
        current[3] -= 1
        now += 3
        with self.assertRaisesRegex(Rejected, "stale_rank_resources"):
            monitor.poll()


class NativePlacementTests(unittest.TestCase):
    def test_worker_checks_world_size_stage_and_staged_digest(self):
        from agent.paired_runtime import PairedRuntime

        runtime = PairedRuntime.__new__(PairedRuntime)
        runtime.rank = 1
        runtime.profile_document = profile_document()
        runtime.staged_artifact = "8" * 64
        runtime.large_stage = {"stage": "probe", "artifact": runtime.staged_artifact}
        offer = dict(placement="studio_pair_only", world_size=2, rank=1, stage="probe",
                     artifact=runtime.profile_document["artifact"], staged_artifact=runtime.staged_artifact,
                     budget=dict(floor=32 * GIB, ceiling=4 * GIB))
        runtime.check_large_offer(offer)
        for mismatch in (dict(world_size=1), dict(rank=0), dict(stage="full"),
                         dict(staged_artifact=runtime.profile_document["artifact"])):
            with self.subTest(mismatch=mismatch), self.assertRaisesRegex(Rejected, "large_trial_placement"):
                runtime.check_large_offer({**offer, **mismatch})

    def test_rank_rejects_mini_before_importing_or_loading_mlx(self):
        from pathlib import Path
        from unittest.mock import patch

        from agent.jaccl_executor import run

        with patch("socket.gethostname", return_value="fios-core"):
            with self.assertRaisesRegex(ValueError, "require their assigned Studios"):
                run(Path("/nonexistent"), dict(world_size=2, rank=0, watchdog={}))


class ProbeStagingTests(unittest.TestCase):
    def test_staging_publishes_verified_files_and_cleans_failed_copy(self):
        from hashlib import sha256
        from pathlib import Path
        import sys
        from tempfile import TemporaryDirectory
        from unittest.mock import patch

        with patch.object(sys, "path", [str(Path(__file__).parent / "macos"), *sys.path]):
            from stage_moe_probe import stage

        with TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            source.mkdir(mode=0o700)
            parent = Path(temp) / "staged"
            parent.mkdir(mode=0o700)
            artifact = source / "model.safetensors"
            artifact.write_bytes(b"probe")
            item = dict(bytes=5, sha256=sha256(b"probe").hexdigest())
            approval = dict(ok=True, stage="probe", expires_at=25, files={artifact.name: item})
            with self.assertRaisesRegex(Rejected, "stage_approval_unavailable"):
                stage(source, parent, {**approval, "stage": "full"}, clock=lambda: 0)
            artifact.write_bytes(b"wrong")
            with self.assertRaisesRegex(Rejected, "probe_file_digest"):
                stage(source, parent, approval, clock=lambda: 0)
            self.assertEqual(list(parent.iterdir()), [])
            artifact.write_bytes(b"probe")
            staged = stage(source, parent, approval, clock=lambda: 0)
            self.assertEqual((staged / artifact.name).read_bytes(), b"probe")
            self.assertEqual(list(parent.iterdir()), [staged])


class PrivateReviewTests(unittest.TestCase):
    def test_expiry_and_restart_discard_raw_draft_frames(self):
        import base64
        from contextlib import closing
        import sqlite3

        from backend.moe_review import RETENTION, TrialReview

        now = 0
        review = TrialReview(lambda: now)
        output = base64.b64encode(b"private fixture canary").decode()
        job = "a" * 32
        review.append(dict(id=job, generation=1), "campaign", 0, output)
        self.assertNotIn(job, TrialReview(lambda: now).samples)
        with closing(sqlite3.connect(":memory:")) as db:
            db.row_factory = sqlite3.Row
            db.execute("CREATE TABLE jobs (id TEXT, state TEXT, outcome TEXT, generation INTEGER)")
            db.execute("INSERT INTO jobs VALUES (?, 'running', NULL, 1)", (job,))
            now = RETENTION - 1
            review.purge(db)
            self.assertIn(job, review.samples)
            now += 1
            review.purge(db)
            self.assertNotIn(job, review.samples)


class QualificationSuiteTests(unittest.TestCase):
    def test_suite_requires_every_fixture_and_keeps_browser_cases_out_of_native_recipes(self):
        from backend.moe_suite import CASES, freeze_suite, verify_recipe_case

        document = dict(fixtures=dict.fromkeys(CASES, "a" * 64), rubric="b" * 64, policy="c" * 64)
        revision, suite = freeze_suite(document)
        self.assertEqual(len(revision), 64)
        verify_recipe_case(suite, dict(case="campaign-1", fixture="a" * 64, review="campaign"))
        for recipe, reason in (
            (dict(case="cold", fixture="a" * 64), "requires_browser_rehearsal"),
            (dict(case="campaign-1", fixture="c" * 64), "unregistered_trial_case"),
            (dict(case="campaign-1", fixture="a" * 64, review="coding"), "trial_review_mismatch"),
        ):
            with self.subTest(case=recipe["case"]), self.assertRaisesRegex(Rejected, reason):
                verify_recipe_case(suite, recipe)
        del document["fixtures"]["full-budget"]
        with self.assertRaisesRegex(Rejected, "invalid_moe_suite"):
            freeze_suite(document)

    def test_browser_boundary_checks_each_timing_source(self):
        from backend.moe_suite import timed_limits

        measurement = dict(first_text_ms=180_000, completed_tokens=32,
                           timing=dict(input_tokens=256, prefill_ms=100, decode_ms=20))
        timed_limits("cold", measurement, 240_000)
        with self.assertRaises(Rejected):
            timed_limits("warm-1", measurement, 240_001)
        with self.assertRaisesRegex(Rejected, "short_case_timing"):
            timed_limits("warm-2", dict(measurement, first_text_ms=180_001), 1000)
        full = dict(measurement, completed_tokens=1024,
                    timing=dict(input_tokens=7168, prefill_ms=400_000, decode_ms=511_500))
        timed_limits("full-budget", full, 900_000)
        full["timing"]["decode_ms"] += 1
        with self.assertRaisesRegex(Rejected, "full_budget_timing"):
            timed_limits("full-budget", full, 900_000)


class FullPackTransferTests(unittest.TestCase):
    def test_direct_shard_listener_does_not_require_reverse_dns(self):
        from http.server import BaseHTTPRequestHandler
        from pathlib import Path
        import sys
        from unittest.mock import patch

        with patch.object(sys, "path", [str(Path(__file__).parent / "macos"), *sys.path]):
            from moe_peer_transfer import TransferServer

        with patch("socket.getfqdn", side_effect=AssertionError("dedicated links have no reverse DNS")):
            with TransferServer(("127.0.0.1", 0), BaseHTTPRequestHandler) as listener:
                self.assertEqual(listener.server_name, "127.0.0.1")
                self.assertGreater(listener.server_port, 0)

    def test_full_copy_checks_end_of_file_digest_and_deadline(self):
        from hashlib import sha256
        from io import BytesIO
        from pathlib import Path
        import sys
        from unittest.mock import patch

        with patch.object(sys, "path", [str(Path(__file__).parent / "macos"), *sys.path]):
            from stage_moe_pack import copy_exact

        expected = {"bytes": 4, "sha256": sha256(b"test").hexdigest()}
        out = BytesIO()
        copy_exact(BytesIO(b"test"), out, expected, clock=lambda: 0, deadline=1)
        self.assertEqual(out.getvalue(), b"test")
        for payload, reason in ((b"te", "artifact_size"), (b"tests", "artifact_digest"),
                                (b"fail", "artifact_digest")):
            with self.subTest(payload=payload), self.assertRaisesRegex(Rejected, reason):
                copy_exact(BytesIO(payload), BytesIO(), expected, clock=lambda: 0, deadline=1)
        with self.assertRaisesRegex(Rejected, "download_deadline"):
            copy_exact(BytesIO(b"test"), BytesIO(), expected, clock=lambda: 1, deadline=1)

    def test_peer_stream_requires_current_full_authority_and_exact_bytes(self):
        from contextlib import nullcontext
        from hashlib import sha256
        from io import BytesIO
        from pathlib import Path
        import sys
        from tempfile import TemporaryDirectory
        from unittest.mock import patch

        from agent.native_runtime import manifest_digest

        with patch.object(sys, "path", [str(Path(__file__).parent / "macos"), *sys.path]):
            from stage_moe_pack import stage_file

        name = "model.safetensors"
        payload = b"verified-weight-fixture"
        checksum = sha256(payload).hexdigest()
        artifact = manifest_digest({name: checksum})
        info = dict(candidate="qwen", files={name: dict(bytes=len(payload), sha256=checksum)})
        receipt = dict(ok=True, stage="full", artifact=artifact, pack_bytes=len(payload), expires_at=10,
                       budgets={"studio-b": dict(disk_bytes=GIB, peak_bytes=GIB)})
        observed = dict(disk_free=2 * GIB, headroom=40 * GIB, pressure="normal")
        with TemporaryDirectory() as temp:
            destination = Path(temp) / "model"
            destination.mkdir(mode=0o700)
            with self.assertRaisesRegex(Rejected, "unreviewed_native_adapter"):
                stage_file("glm", dict(info, candidate="glm"), destination, receipt, name, "studio-b",
                           observed, clock=lambda: 0, peer_source=lambda: self.fail("opened unsafe source"))
            for stage, data, reason in (
                ("probe", payload, "stage_approval_unavailable"),
                ("full", bytes(len(payload)), "artifact_digest"),
            ):
                with self.assertRaisesRegex(Rejected, reason):
                    stage_file("qwen", info, destination, dict(receipt, stage=stage), name, "studio-b",
                               observed, clock=lambda: 0, peer_source=lambda: nullcontext(BytesIO(data)))
            self.assertEqual(list(Path(temp).iterdir()), [destination])
            self.assertEqual(list(destination.iterdir()), [])
            stage_file("qwen", info, destination, receipt, name, "studio-b",
                       observed, clock=lambda: 0, peer_source=lambda: nullcontext(BytesIO(payload)))
            self.assertEqual((destination / name).read_bytes(), payload)
