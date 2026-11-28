"""Capacity rules for model qualification before a measured peak is known."""

from dataclasses import dataclass
import hashlib
import json
import re
import secrets

from .enrollment import Rejected, STUDIOS
from .job_ledger import EXECUTORS, encoded, identifier, integer

from .pair_trial import PAIR_ONLY, digest, paired_rdma, transport_observation

LARGE_ALIAS = "large-moe"
LARGE_DEADLINE = 900
ALIASES = ("general-chat", "coding", "paired-coding", LARGE_ALIAS)
MINI_CEILING = 6_000_000_000


@dataclass(frozen=True)
class Capacity:
    sampled_at: float
    headroom_bytes: int
    pressure: str
    footprint_bytes: int | None = None
    peak_bytes: int | None = None


@dataclass(frozen=True)
class TrialBudget:
    slot: str
    workload_bytes: int
    host_floor_bytes: int
    stale_after: int
    duration: int

    def __post_init__(self):
        limits = (self.workload_bytes, self.host_floor_bytes, self.stale_after, self.duration)
        if self.slot not in EXECUTORS or any(type(value) is not int or value <= 0 for value in limits):
            raise ValueError("Invalid trial budget")
        if self.slot == "fios-core" and self.workload_bytes > MINI_CEILING:
            raise ValueError("Trial exceeds the Mini workload ceiling")

    def validate_capacity(self, capacity, now):
        if (capacity is None or not 0 <= now - capacity.sampled_at <= self.stale_after
                or type(capacity.headroom_bytes) is not int or capacity.headroom_bytes < 0):
            raise Rejected("trial_capacity_unavailable", 503)
        if capacity.pressure != "normal":
            raise Rejected("trial_pressure", 503)

    def admit(self, capacity, *, now):
        self.validate_capacity(capacity, now)
        if capacity.headroom_bytes < self.workload_bytes + self.host_floor_bytes:
            raise Rejected("trial_headroom", 409)

    def check(self, capacity, *, now, completed=False):
        self.validate_capacity(capacity, now)
        if capacity.headroom_bytes < self.host_floor_bytes:
            raise Rejected("trial_headroom", 409)
        readings = (capacity.footprint_bytes, capacity.peak_bytes)
        if any(type(value) is not int or value < 0 for value in readings if value is not None):
            raise Rejected("trial_capacity_unavailable", 503)
        if capacity.footprint_bytes is None or (completed and capacity.peak_bytes is None):
            raise Rejected("trial_capacity_unavailable", 503)
        if any(value is not None and value >= self.workload_bytes for value in readings):
            raise Rejected("trial_budget", 409)


@dataclass(frozen=True)
class Profile:
    """Canonical candidate description. Qualification evidence is separate."""

    revision: str
    manifest: str

    @classmethod
    def parse(cls, document):
        digests = {"artifact", "engine", "template", "policy", "evaluation"}
        fields = digests | {"alias", "host_class", "license", "context", "output", "settings"}
        if not isinstance(document, dict):
            raise Rejected("invalid_profile")
        alias = document.get("alias")
        large = alias == LARGE_ALIAS
        paired = large or alias == "paired-coding"
        if paired:
            fields.add("devices")
        if large:
            fields.add("placement")
        if document.keys() != fields or (large and document["placement"] != PAIR_ONLY):
            raise Rejected("invalid_profile")
        if paired:
            devices = document["devices"]
            if (not isinstance(devices, dict) or devices.keys() != set(STUDIOS)
                    or len({digest(value) for value in devices.values()}) != 2):
                raise Rejected("invalid_profile")
        host_classes = {"general-chat": "m4-pro-mini", "coding": "m3-ultra-studio",
                        "paired-coding": "m3-ultra-pair", LARGE_ALIAS: "m3-ultra-pair"}
        if not isinstance(alias, str) or alias not in host_classes or (
                host_classes[alias] != document["host_class"]):
            raise Rejected("invalid_profile")
        for name in digests:
            value = document[name]
            if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
                raise Rejected("invalid_profile")
        license_id = document["license"]
        if not isinstance(license_id, str) or not re.fullmatch(r"[A-Za-z0-9 .+_-]{1,80}", license_id):
            raise Rejected("invalid_profile")
        total = integer(document["context"], 2, 1_000_000)
        integer(document["output"], 1, total - 1)
        if large and (total > 8192 or document["output"] > 1024):
            raise Rejected("invalid_profile")
        settings = document["settings"]
        allowed_settings = ({"temperature"}, {"temperature", "no_thinking"}) if paired else ({"temperature"},)
        if (not isinstance(settings, dict) or settings.keys() not in allowed_settings
                or ("no_thinking" in settings and type(settings["no_thinking"]) is not bool)):
            raise Rejected("invalid_profile")
        temperature = settings["temperature"]
        if type(temperature) not in (int, float) or not 0 <= temperature <= 2:
            raise Rejected("invalid_profile")
        manifest = encoded(document)
        return cls(hashlib.sha256(manifest.encode("ascii")).hexdigest(), manifest)

    def document(self):
        return json.loads(self.manifest)


CATALOG = """
CREATE TABLE IF NOT EXISTS model_trials (
    sequence INTEGER PRIMARY KEY, revision TEXT NOT NULL, manifest TEXT NOT NULL,
    slot TEXT NOT NULL, peak_bytes INTEGER NOT NULL, passed INTEGER NOT NULL,
    synthetic INTEGER NOT NULL, observed_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS model_trials_revision ON model_trials(revision,synthetic,slot,sequence);
CREATE TABLE IF NOT EXISTS model_trial_reports (
    trial INTEGER PRIMARY KEY REFERENCES model_trials(sequence), report TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS synthetic_pair_trials (
    revision TEXT PRIMARY KEY, manifest TEXT NOT NULL, peaks TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS qualified_pairs (
    revision TEXT PRIMARY KEY, manifest TEXT NOT NULL, peaks TEXT NOT NULL, report TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS chat_attachments (
    job TEXT PRIMARY KEY REFERENCES jobs(id), expires REAL NOT NULL, ticket TEXT
);
CREATE TABLE IF NOT EXISTS large_candidates (
    revision TEXT PRIMARY KEY, artifact TEXT NOT NULL, manifest TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS large_candidates_artifact ON large_candidates(artifact);
CREATE TABLE IF NOT EXISTS large_stage_decisions (
    sequence INTEGER PRIMARY KEY, candidate TEXT NOT NULL REFERENCES large_candidates(revision),
    incarnation TEXT NOT NULL, stage TEXT NOT NULL, decision TEXT NOT NULL,
    decided_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, evidence TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS large_suites (
    revision TEXT PRIMARY KEY, document TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS large_policy_checks (
    candidate TEXT NOT NULL, incarnation TEXT NOT NULL, case_name TEXT NOT NULL, decision INTEGER NOT NULL,
    PRIMARY KEY(candidate,incarnation,case_name)
);
CREATE TABLE IF NOT EXISTS large_rehearsal_observations (
    job TEXT PRIMARY KEY REFERENCES jobs(id), incarnation TEXT NOT NULL,
    candidate TEXT NOT NULL, suite TEXT NOT NULL, case_name TEXT NOT NULL, visible_ms INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS large_qualifications (
    candidate TEXT PRIMARY KEY, incarnation TEXT NOT NULL, comparable TEXT NOT NULL,
    peaks TEXT NOT NULL, evidence TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS large_review_verdicts (
    job TEXT PRIMARY KEY REFERENCES jobs(id), blind TEXT NOT NULL UNIQUE,
    digest TEXT NOT NULL, kind TEXT NOT NULL, verdict TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS model_aliases (
    alias TEXT NOT NULL, synthetic INTEGER NOT NULL, revision TEXT NOT NULL,
    PRIMARY KEY(alias,synthetic)
);
"""


class Catalog:
    """Store qualification evidence produced by the trusted trial runner."""

    def __init__(self, jobs, *, synthetic=False, rehearsal=False):
        self.jobs = jobs
        self.synthetic = synthetic
        self.rehearsal_enabled = rehearsal
        self.rehearsal = None
        with jobs.transaction() as db:
            self.initialize_tables(db)

    @staticmethod
    def initialize_tables(db):
        for statement in CATALOG.split(";"):
            if statement.strip():
                db.execute(statement)

    def register_large_suite(self, document):
        from .moe_suite import freeze_suite

        revision, suite = freeze_suite(document)
        with self.jobs.transaction() as db:
            db.execute("INSERT OR IGNORE INTO large_suites VALUES (?,?)", (revision, encoded(suite)))
        return revision

    def register_large(self, profile):
        manifest = profile.document()
        if manifest["alias"] != LARGE_ALIAS:
            raise Rejected("invalid_profile")
        with self.jobs.transaction() as db:
            # Registering the classification after legacy qualification would
            # leave an already-issued lease able to execute the same artifact.
            for table in ("model_trials", "qualified_pairs", "synthetic_pair_trials"):
                if db.execute(f"SELECT 1 FROM {table} WHERE json_extract(manifest,'$.artifact')=?",
                              (manifest["artifact"],)).fetchone():
                    raise Rejected("artifact_already_qualified", 409)
            db.execute("INSERT OR IGNORE INTO large_candidates VALUES (?,?,?)",
                       (profile.revision, manifest["artifact"], profile.manifest))

    def large_basis(self, db, candidate, comparable):
        row = db.execute("SELECT manifest FROM large_candidates WHERE revision=?",
                         (digest(candidate),)).fetchone()
        if row is None:
            raise Rejected("unregistered_candidate", 409)
        manifest = json.loads(row["manifest"])
        basis = db.execute("SELECT manifest,report FROM qualified_pairs WHERE revision=?",
                           (digest(comparable),)).fetchone()
        if (self.synthetic or basis is None
                or json.loads(basis["manifest"])["devices"] != manifest["devices"]):
            raise Rejected("comparable_pair_unverified", 409)
        # Require the actual trial jobs and cleaned hardware receipts.
        prior = Profile.parse(json.loads(basis["manifest"]))
        report = json.loads(basis["report"])
        self.joint_trial(db, report["baseline"], prior, paired=False)
        self.joint_trial(db, report["paired"], prior, paired=True)
        return manifest

    def open_rehearsal(self, request):
        from .moe_suite import NATIVE_CASES, POLICY_CASES, verify_native_case

        if not self.rehearsal_enabled or self.synthetic:
            raise Rejected("rehearsal_unavailable", 409)
        fields = {"candidate", "comparable", "approval", "native"}
        if (not isinstance(request, dict) or request.keys() != fields
                or not isinstance(request["native"], dict)
                or request["native"].keys() != NATIVE_CASES):
            raise Rejected("invalid_rehearsal")
        candidate = digest(request["candidate"])
        jobs = {case: identifier(job) for case, job in request["native"].items()}
        if len(set(jobs.values())) != len(jobs):
            raise Rejected("duplicate_case_job", 409)
        with self.jobs.transaction(write=False) as db:
            manifest = self.large_basis(db, candidate, request["comparable"])
            # The TCP negative uses the bounded comparable reference workload
            # and the same paired_rdma predicate used for the full candidate.
            basis_report, = db.execute("SELECT report FROM qualified_pairs WHERE revision=?",
                                       (request["comparable"],)).fetchone()
            if json.loads(basis_report)["checks"].get("tcp_rejected") is not True:
                raise Rejected("tcp_control_unverified", 409)
            authority = self.stage_authority(db, candidate, request["approval"], "full", starting=False)
            if authority["comparable"] != request["comparable"]:
                raise Rejected("comparable_pair_unverified", 409)
            suite = db.execute("SELECT document FROM large_suites WHERE revision=?",
                               (manifest["evaluation"],)).fetchone()
            if not suite or json.loads(suite["document"])["policy"] != manifest["policy"]:
                raise Rejected("suite_policy_mismatch", 409)
            profile = Profile.parse(manifest)
            decisions = {row["case_name"]: bool(row["decision"]) for row in db.execute(
                "SELECT case_name,decision FROM large_policy_checks WHERE candidate=? AND incarnation=?",
                (candidate, self.jobs.incarnation(db)))}
            if decisions != POLICY_CASES:
                raise Rejected("missing_real_policy_checks", 409)
            for case, job in jobs.items():
                verify_native_case(db, profile, case, job, self.joint_trial)
            self.rehearsal = dict(
                id=secrets.token_hex(16), incarnation=self.jobs.incarnation(db), candidate=candidate,
                comparable=request["comparable"], approval=request["approval"], native=jobs,
                expires=self.jobs.wall() + 4 * 3600)
            return {"rehearsal": self.rehearsal["id"]}

    def verify_policy_fixture(self, request, checker, policy_revision):
        from .moe_suite import POLICY_CASES

        if (not self.rehearsal_enabled or self.synthetic or not isinstance(request, dict)
                or request.keys() != {"candidate", "comparable", "case", "purpose", "text"}
                or not isinstance(request["case"], str) or request["case"] not in POLICY_CASES
                or request["purpose"] not in ("input", "answer")
                or not isinstance(request["text"], str)
                or not 0 < len(request["text"].encode()) <= 16 * 1024):
            raise Rejected("invalid_policy_fixture")
        candidate, case = request["candidate"], request["case"]
        fixture = encoded({"purpose": request["purpose"], "text": request["text"]})
        checksum = hashlib.sha256(fixture.encode("ascii")).hexdigest()
        with self.jobs.transaction(write=False) as db:
            profile = self.large_basis(db, candidate, request["comparable"])
            suite = db.execute("SELECT document FROM large_suites WHERE revision=?",
                               (profile["evaluation"],)).fetchone()
            incarnation = self.jobs.incarnation(db)
            if (not suite or profile["policy"] != policy_revision
                    or json.loads(suite["document"])["fixtures"][case] != checksum):
                raise Rejected("unregistered_policy_fixture", 409)
        try:
            decision = checker(request["purpose"], request["text"], policy_revision)
        except Exception:
            raise Rejected("publication_unavailable", 503) from None
        with self.jobs.transaction() as db:
            if self.jobs.incarnation(db) != incarnation:
                raise Rejected("ledger_changed", 409)
            # A fresh mismatch invalidates a previously passing check.
            if decision is POLICY_CASES[case]:
                db.execute("INSERT OR REPLACE INTO large_policy_checks VALUES (?,?,?,?)",
                           (candidate, incarnation, case, decision))
                passed = True
            else:
                db.execute("DELETE FROM large_policy_checks WHERE candidate=? AND incarnation=? AND case_name=?",
                           (candidate, incarnation, case))
                passed = False
        return {"passed": passed}

    def rehearsal_profile(self, db):
        rehearsal = self.rehearsal
        if (not rehearsal or rehearsal["incarnation"] != self.jobs.incarnation(db)
                or self.jobs.wall() >= rehearsal["expires"]):
            return None
        try:
            manifest = self.large_basis(db, rehearsal["candidate"], rehearsal["comparable"])
            approval = self.stage_authority(db, rehearsal["candidate"], rehearsal["approval"], "full",
                                            starting=False)
        except Rejected:
            return None
        from .pair_trial import LARGE_FLOOR

        budgets = {slot: dict(ceiling=row["peak_bytes"], floor=LARGE_FLOOR)
                   for slot, row in approval["budgets"].items()}
        return dict(manifest, revision=rehearsal["candidate"], rehearsal=rehearsal["id"],
                    budgets=budgets, peaks={slot: sum(budget.values()) for slot, budget in budgets.items()})

    def rehearsal_case(self, db, profile, prompt):
        from .moe_suite import TIMED

        suite = db.execute("SELECT document FROM large_suites WHERE revision=?",
                           (profile["evaluation"],)).fetchone()
        fixtures = json.loads(suite["document"])["fixtures"]
        submitted = db.execute(
            "SELECT jobs.id,state,json_extract(intent,'$.case') AS case_name FROM jobs "
            "WHERE json_extract(intent,'$.rehearsal')=? ORDER BY position",
            (profile["rehearsal"],)).fetchall()
        if any(row["state"] in ("failed", "cancelled", "expired", "denied") for row in submitted):
            raise Rejected("rehearsal_restart_required", 409)
        for row in submitted:
            if row["state"] != "succeeded" or db.execute("SELECT 1 FROM holds WHERE job=?",
                                                         (row["id"],)).fetchone():
                raise Rejected("rehearsal_case_busy", 409)
        if tuple(row["case_name"] for row in submitted) != TIMED[:len(submitted)]:
            raise Rejected("invalid_rehearsal_order", 409)
        case = TIMED[len(submitted)] if len(submitted) < len(TIMED) else None
        if case is None or hashlib.sha256(prompt.encode()).hexdigest() != fixtures[case]:
            raise Rejected("unregistered_rehearsal_case", 409)
        return case

    def rehearsal_job(self, db, job):
        from .moe_measurements import rank_phases
        from .moe_suite import TIMED

        profile = self.rehearsal_profile(db)
        if not profile:
            raise Rejected("rehearsal_unavailable", 409)
        row = db.execute("SELECT * FROM jobs WHERE id=?", (identifier(job),)).fetchone()
        if (not row or row["state"] != "succeeded" or row["owner"] != "local-moe-rehearsal"
                or db.execute("SELECT 1 FROM holds WHERE job=?", (job,)).fetchone()):
            raise Rejected("rehearsal_job_unavailable", 409)
        intent = json.loads(row["intent"])
        if (intent.get("rehearsal") != profile["rehearsal"] or intent.get("suite") != profile["evaluation"]
                or intent.get("profile") != profile["revision"] or intent.get("case") not in TIMED
                or row["reporter"] != STUDIOS[0]
                or not db.execute("SELECT 1 FROM content.segments WHERE job=? AND policy=?",
                                  (job, profile["policy"])).fetchone()):
            raise Rejected("rehearsal_job_mismatch", 409)
        receipts = json.loads(row["receipts"])
        if set(receipts) != set(STUDIOS):
            raise Rejected("invalid_trial_receipts", 409)
        observations = []
        for slot in STUDIOS:
            receipt = receipts[slot]
            if receipt["result"] != "ok":
                raise Rejected("invalid_trial_receipts", 409)
            observations.append(transport_observation(
                receipt.get("transport_evidence"), candidate=profile["revision"],
                device=profile["devices"][slot], attempt=job))
            rank_phases(receipt.get("phase_observation"), attempt=job,
                        ceiling=profile["budgets"][slot]["ceiling"], deadline_ms=LARGE_DEADLINE * 1000)
        if not paired_rdma(*observations):
            raise Rejected("transport_mismatch", 409)
        return profile, intent["case"], receipts

    def record_rehearsal_observation(self, db, data):
        from .moe_suite import timed_limits

        fields = {"job", "candidate", "suite", "case", "visible_ms"}
        if not isinstance(data, dict) or data.keys() != fields:
            raise Rejected("invalid_rehearsal_observation")
        profile, case, receipts = self.rehearsal_job(db, data["job"])
        if (data["candidate"], data["suite"], data["case"]) != (
                profile["revision"], profile["evaluation"], case):
            raise Rejected("rehearsal_job_mismatch", 409)
        timed_limits(case, receipts[STUDIOS[0]]["trial_measurement"], data["visible_ms"])
        values = (data["job"], self.jobs.incarnation(db), profile["revision"],
                  profile["evaluation"], case, data["visible_ms"])
        prior = db.execute("SELECT * FROM large_rehearsal_observations WHERE job=?",
                           (data["job"],)).fetchone()
        if prior:
            if tuple(prior) != values:
                raise Rejected("conflict", 409)
            return
        db.execute("INSERT INTO large_rehearsal_observations VALUES (?,?,?,?,?,?)", values)

    def record_large_qualification(self, db, timed):
        from .moe_suite import TIMED, verify_native_case

        profile = self.rehearsal_profile(db)
        if not profile or not isinstance(timed, dict) or timed.keys() != set(TIMED):
            raise Rejected("invalid_rehearsal_report", 409)
        native = self.rehearsal["native"]
        jobs = [identifier(job) for job in (*native.values(), *timed.values())]
        if len(set(jobs)) != len(jobs):
            raise Rejected("duplicate_case_job", 409)
        candidate = Profile.parse({key: value for key, value in profile.items()
                                   if key not in ("revision", "rehearsal", "budgets", "peaks")})
        incarnation = self.jobs.incarnation(db)
        peaks = dict.fromkeys(STUDIOS, 0)
        for case, job in native.items():
            for slot, peak in verify_native_case(db, candidate, case, job, self.joint_trial).items():
                peaks[slot] = max(peaks[slot], peak)
        for case, job in timed.items():
            _, observed_case, receipts = self.rehearsal_job(db, job)
            evidence = db.execute("SELECT * FROM large_rehearsal_observations WHERE job=? AND incarnation=?",
                                  (job, incarnation)).fetchone()
            if (not evidence or observed_case != case or evidence["case_name"] != case
                    or evidence["candidate"] != candidate.revision
                    or evidence["suite"] != profile["evaluation"]):
                raise Rejected("missing_rehearsal_observation", 409)
            for slot, receipt in receipts.items():
                peak = receipt["trial_measurement"]["peak_bytes"] + profile["budgets"][slot]["floor"]
                peaks[slot] = max(peaks[slot], peak)
        report = encoded(dict(native=native, timed=timed, budgets=profile["budgets"]))
        db.execute("INSERT INTO large_qualifications VALUES (?,?,?,?,?) "
                   "ON CONFLICT(candidate) DO UPDATE SET incarnation=excluded.incarnation, "
                   "comparable=excluded.comparable, peaks=excluded.peaks, evidence=excluded.evidence",
                   (candidate.revision, incarnation, self.rehearsal["comparable"], encoded(peaks), report))
        return candidate.revision

    def evaluate_large_resources(self, candidate, comparable, budgets, observations):
        """Evaluate reviewed estimates on the admin path without granting a transfer."""
        from .moe_preflight import check_host_budgets

        with self.jobs.transaction(write=False) as db:
            self.large_basis(db, candidate, comparable)
        refusal = check_host_budgets(budgets, observations, now=self.jobs.wall())
        return {"candidate": candidate, "comparable": comparable,
                "resources": "refused" if refusal else "within_estimate", "refusal": refusal}

    def decide_large_stage(self, request):
        from .moe_measurements import rank_phases
        from .moe_preflight import check_host_budgets, estimate_single_host, probe_files

        fields = {"candidate", "comparable", "budgets", "observations", "stage", "incarnation"}
        if not isinstance(request, dict) or request.get("stage") not in ("probe", "full"):
            raise Rejected("invalid_stage")
        stage = request["stage"]
        if request.keys() != fields | ({"files"} if stage == "probe" else {"probe_job", "pack_bytes"}):
            raise Rejected("invalid_stage")
        candidate, comparable = request["candidate"], request["comparable"]
        with self.jobs.transaction() as db:
            incarnation = self.jobs.incarnation(db)
            if identifier(request["incarnation"]) != incarnation:
                raise Rejected("ledger_changed", 409)
            manifest = self.large_basis(db, candidate, comparable)
            now = int(self.jobs.wall())
            budgets, observations = request["budgets"], request["observations"]
            refusal = check_host_budgets(budgets, observations, now=now)
            evidence = dict(comparable=comparable, artifact=manifest["artifact"],
                            budgets=budgets, refusal=refusal)
            if stage == "probe":
                total = probe_files(request["files"])
                if refusal is None and any(budgets[slot]["disk_bytes"] < total for slot in STUDIOS):
                    raise Rejected("invalid_budgets")
                evidence["files"] = request["files"]
                file_digests = {name: item["sha256"] for name, item in request["files"].items()}
                evidence["probe_digest"] = hashlib.sha256(encoded(file_digests).encode("ascii")).hexdigest()
            else:
                pack_bytes = integer(request["pack_bytes"], 1, 2**60)
                if refusal is None and any(budgets[slot]["disk_bytes"] < pack_bytes for slot in STUDIOS):
                    raise Rejected("invalid_budgets")
                probe = identifier(request["probe_job"])
                review, receipts = self.joint_trial(db, probe, Profile.parse(manifest), paired=True)
                intent = json.loads(db.execute("SELECT intent FROM jobs WHERE id=?", (probe,)).fetchone()[0])
                approval = db.execute(
                    "SELECT evidence FROM large_stage_decisions WHERE sequence=? AND candidate=? "
                    "AND incarnation=? AND stage='probe' AND decision='approved'",
                    (intent.get("stage_approval"), candidate, incarnation)).fetchone()
                # A matching candidate alone is insufficient. The attempt must
                # refer to the stage decision under which the probe was started.
                if (review.get("stage") != "probe" or review.get("artifact") != manifest["artifact"]
                        or review.get("placement") != PAIR_ONLY or approval is None
                        or json.loads(approval["evidence"])["comparable"] != comparable):
                    raise Rejected("invalid_probe_evidence", 409)
                for slot in STUDIOS:
                    rank_phases(receipts[slot].get("phase_observation"), attempt=probe,
                                ceiling=review["budgets"][slot]["ceiling"],
                                deadline_ms=review["deadline"] * 1000)
                evidence.update(probe_job=probe, pack_bytes=pack_bytes,
                                single_host=estimate_single_host(pack_bytes, budgets))
            decision = "refused" if refusal else "approved"
            expires = now if refusal else min(item["sampled_at"] for item in observations.values()) + 30
            row = db.execute(
                "INSERT INTO large_stage_decisions "
                "(candidate,incarnation,stage,decision,decided_at,expires_at,evidence) VALUES (?,?,?,?,?,?,?)",
                (candidate, incarnation, stage, decision, now, expires, encoded(evidence)))
            result = dict(decision=decision, approval=row.lastrowid if not refusal else None,
                          stage=stage, expires_at=expires, refusal=refusal)
            if stage == "full":
                result["single_host"] = evidence["single_host"]
            return result

    def large_stage_authority(self, candidate, approval, stage):
        with self.jobs.transaction(write=False) as db:
            return self.stage_authority(db, candidate, approval, stage, starting=True)

    def stage_authority(self, db, candidate, approval, stage, *, starting):
        if stage not in ("probe", "full"):
            raise Rejected("invalid_stage")
        row = db.execute(
            "SELECT * FROM large_stage_decisions WHERE candidate=? AND stage=? "
            "AND incarnation=? ORDER BY sequence DESC LIMIT 1",
            (digest(candidate), stage, self.jobs.incarnation(db))).fetchone()
        if (not row or row["sequence"] != integer(approval, 1, 2**63 - 1)
                or row["decision"] != "approved" or (starting and self.jobs.wall() >= row["expires_at"])):
            raise Rejected("stage_approval_unavailable", 409)
        evidence = json.loads(row["evidence"])
        manifest = self.large_basis(db, candidate, evidence["comparable"])
        return dict(stage=stage, approval=approval, expires_at=row["expires_at"],
                    devices=manifest["devices"], **evidence)

    @staticmethod
    def pair_only_artifact(db, manifest):
        return db.execute("SELECT 1 FROM large_candidates WHERE artifact=?",
                          (manifest["artifact"],)).fetchone() is not None

    @classmethod
    def reject_pair_only_artifact(cls, db, manifest):
        if cls.pair_only_artifact(db, manifest):
            raise Rejected("pair_only_artifact", 409)

    def check_trial_placement(self, db, recipe, approval=None, *, starting=True):
        registered = db.execute("SELECT artifact,manifest FROM large_candidates WHERE revision=?",
                                (recipe["candidate"],)).fetchone()
        if registered and recipe.get("placement") != PAIR_ONLY:
            raise Rejected("pair_only_artifact", 409)
        if recipe.get("placement") == PAIR_ONLY:
            if not registered or registered["artifact"] != recipe["artifact"]:
                raise Rejected("unregistered_candidate", 409)
            if approval is None or self.synthetic:
                raise Rejected("large_trial_unavailable", 409)
            stage = self.stage_authority(db, recipe["candidate"], approval, recipe["stage"],
                                         starting=starting)
            profile = json.loads(registered["manifest"])
            if recipe["stage"] == "full":
                from .moe_suite import verify_recipe_case

                suite = db.execute("SELECT document FROM large_suites WHERE revision=?",
                                   (profile["evaluation"],)).fetchone()
                if not suite:
                    raise Rejected("unregistered_moe_suite", 409)
                document = json.loads(suite["document"])
                if document["policy"] != profile["policy"]:
                    raise Rejected("suite_policy_mismatch", 409)
                verify_recipe_case(document, recipe)
            if (recipe["devices"] != stage["devices"] or recipe["artifact"] != stage["artifact"]
                    or recipe["tokens"] > profile["output"] or any(recipe["budgets"][slot]["ceiling"] > stage["budgets"][slot]["peak_bytes"]
                           for slot in STUDIOS)):
                raise Rejected("stage_recipe_mismatch", 409)
        elif approval is not None:
            raise Rejected("invalid_stage")

    def record(self, profile, evidence):
        if (not isinstance(evidence, dict)
                or evidence.keys() not in ({"slot", "peak_bytes", "passed", "synthetic"},
                                           {"slot", "peak_bytes", "passed", "synthetic", "report"})
                or type(evidence["passed"]) is not bool or type(evidence["synthetic"]) is not bool):
            raise Rejected("invalid_evidence")
        manifest = profile.document()
        slot = evidence["slot"]
        if manifest["alias"] in ("paired-coding", LARGE_ALIAS):
            raise Rejected("requires_joint_evidence", 409)
        eligible = ("fios-core",) if manifest["alias"] == "general-chat" else EXECUTORS[1:]
        if slot not in eligible:
            raise Rejected("invalid_evidence")
        limit = MINI_CEILING - 1 if slot == "fios-core" else 2**63 - 1
        if not evidence["passed"]:
            limit = 2**63 - 1
        peak = integer(evidence["peak_bytes"], 1, limit)
        report = evidence.get("report")
        if not evidence["synthetic"]:
            self.validate_report(manifest, report, evidence["passed"])
        elif report is not None:
            raise Rejected("invalid_evidence")
        with self.jobs.transaction() as db:
            self.reject_pair_only_artifact(db, manifest)
            record = db.execute("INSERT INTO model_trials(revision,manifest,slot,peak_bytes,passed,synthetic,"
                       "observed_at) VALUES (?,?,?,?,?,?,?)",
                       (profile.revision, profile.manifest, slot, peak, evidence["passed"],
                        evidence["synthetic"], int(self.jobs.wall())))
            if report is not None:
                db.execute("INSERT INTO model_trial_reports VALUES (?,?)",
                           (record.lastrowid, encoded(report)))

    def record_synthetic_pair(self, profile, peaks):
        """Store one joint fixture result, isolated from hardware qualification."""
        if (not self.synthetic or profile.document()["alias"] != "paired-coding"
                or not isinstance(peaks, dict) or peaks.keys() != set(STUDIOS)):
            raise Rejected("invalid_evidence")
        bounds = {slot: integer(value, 1, 2**63 - 1) for slot, value in peaks.items()}
        with self.jobs.transaction() as db:
            self.reject_pair_only_artifact(db, profile.document())
            db.execute("INSERT INTO synthetic_pair_trials VALUES (?,?,?) "
                       "ON CONFLICT(revision) DO UPDATE SET peaks=excluded.peaks",
                       (profile.revision, profile.manifest, encoded(bounds)))

    def record_joint(self, profile, report):
        """Record an operator report only when real, cleaned trial receipts corroborate it."""
        fields = {"baseline", "paired", "cold_trials", "warm_trials", "worst_latency_ms",
                  "latency_limit_ms", "checks"}
        checks = {"quality", "publication", "context", "cancellation", "cleanup",
                  "license", "rollback", "tcp_rejected", "link_loss", "rank_loss"}
        manifest = profile.document()
        if (self.synthetic or manifest["alias"] != "paired-coding"
                or not isinstance(report, dict) or report.keys() != fields
                or not isinstance(report["checks"], dict) or report["checks"].keys() != checks
                or not all(value is True for value in report["checks"].values())):
            raise Rejected("invalid_evidence")
        integer(report["cold_trials"], 1, 100)
        integer(report["warm_trials"], 5, 100)
        limit = integer(report["latency_limit_ms"], 1, 3_600_000)
        integer(report["worst_latency_ms"], 1, limit)
        baseline_id, pair_id = (identifier(report[key]) for key in ("baseline", "paired"))
        with self.jobs.transaction() as db:
            self.reject_pair_only_artifact(db, manifest)
            baseline, single = self.joint_trial(db, baseline_id, profile, paired=False)
            pair, ranks = self.joint_trial(db, pair_id, profile, paired=True)
            if (baseline["fixture"] != pair["fixture"] or baseline["engine"] != pair["engine"]
                    or baseline["tokens"] != pair["tokens"]):
                raise Rejected("nonmatching_baseline", 409)
            if max(item["trial_measurement"]["first_text_ms"] for item in [*ranks.values(), *single.values()]) > limit:
                raise Rejected("trial_latency", 409)
            peaks = {slot: ranks[slot]["trial_measurement"]["peak_bytes"] + pair["budgets"][slot]["floor"]
                     for slot in STUDIOS}
            db.execute("INSERT INTO qualified_pairs VALUES (?,?,?,?) "
                       "ON CONFLICT(revision) DO UPDATE SET peaks=excluded.peaks,report=excluded.report",
                       (profile.revision, profile.manifest, encoded(peaks), encoded(report)))

    @staticmethod
    def joint_trial(db, job, profile, *, paired):
        row = db.execute("SELECT state,intent,receipts FROM jobs WHERE id=?", (job,)).fetchone()
        if row is None or row["state"] != "succeeded" or db.execute(
                "SELECT 1 FROM holds WHERE job=?", (job,)).fetchone():
            raise Rejected("trial_not_clean", 409)
        intent, receipts = json.loads(row["intent"]), json.loads(row["receipts"])
        review = intent.get("review", {})
        devices = profile.document()["devices"]
        if (intent["resource_class"] != "pair_trial" or intent.get("hardware") is not True
                or intent["profile"] != profile.revision
                or set(receipts) != set(review.get("budgets", {}))
                or len(receipts) != (2 if paired else 1)
                or any(review["devices"].get(slot) != devices.get(slot) for slot in receipts)
                or any(entry["result"] != "ok"
                       or entry.get("trial_measurement", {}).get("fixture_passed") is not True
                       for entry in receipts.values())):
            raise Rejected("invalid_trial_receipts", 409)
        if paired:
            observations = [transport_observation(receipts[slot].get("transport_evidence"),
                                                 candidate=profile.revision, device=devices[slot],
                                                 attempt=job) for slot in STUDIOS]
            if not paired_rdma(*observations):
                raise Rejected("transport_mismatch", 409)
        return review, receipts

    @staticmethod
    def validate_report(manifest, report, passed):
        matches = {"artifact": "artifact", "policy": "policy",
                   "evaluation": "evaluation", "runtime": "engine"}
        fields = set(matches) | {"host_build", "cold_trials", "warm_trials",
                                 "latency_limit_ms", "worst_latency_ms", "checks"}
        checks = {"quality", "publication", "context", "cancellation", "cleanup", "license", "rollback"}
        if (not isinstance(report, dict) or report.keys() != fields
                or any(report[key] != manifest[field] for key, field in matches.items())
                or not isinstance(report["host_build"], str)
                or not re.fullmatch(r"[0-9A-Za-z.()-]{1,40}", report["host_build"])
                or not isinstance(report["checks"], dict) or report["checks"].keys() != checks
                or any(type(value) is not bool for value in report["checks"].values())
                or any(type(report[key]) is not int or not 0 <= report[key] <= 3_600_000
                       for key in ("cold_trials", "warm_trials", "latency_limit_ms", "worst_latency_ms"))
                or report["latency_limit_ms"] == 0
                or (passed and (report["cold_trials"] < 1 or report["warm_trials"] < 5
                                or not 0 < report["worst_latency_ms"] <= report["latency_limit_ms"]
                                or not all(report["checks"].values())))):
            raise Rejected("invalid_evidence")

    @staticmethod
    def qualified(db, revision, synthetic):
        if not synthetic:
            large = db.execute(
                "SELECT c.manifest,q.peaks,q.evidence FROM large_qualifications q JOIN large_candidates c "
                "ON q.candidate=c.revision WHERE q.candidate=? "
                "AND q.incarnation=(SELECT incarnation FROM metadata)",
                (revision,)).fetchone()
            if large:
                from .pair_trial import LARGE_FLOOR

                observed = json.loads(large["peaks"])
                budgets = json.loads(large["evidence"]).get("budgets")
                if (not isinstance(budgets, dict) or budgets.keys() != set(STUDIOS)
                        or observed.keys() != set(STUDIOS)
                        or any(budget.keys() != {"floor", "ceiling"} or budget["floor"] != LARGE_FLOOR
                               or not LARGE_FLOOR < observed[slot] < sum(budget.values())
                               for slot, budget in budgets.items())):
                    return None
                # Admission and the runtime use the reviewed ceilings. The
                # observed peaks are evidence and can recur during serving.
                peaks = {slot: sum(budget.values()) for slot, budget in budgets.items()}
                return dict(json.loads(large["manifest"]), revision=revision, peaks=peaks, budgets=budgets)
        table = "synthetic_pair_trials" if synthetic else "qualified_pairs"
        pair = db.execute(f"SELECT manifest, peaks FROM {table} WHERE revision=?", (revision,)).fetchone()
        if pair:
            profile = json.loads(pair["manifest"])
            if Catalog.pair_only_artifact(db, profile):
                return None
            return dict(profile, revision=revision, peaks=json.loads(pair["peaks"]))
        rows = db.execute("""
            SELECT t.* FROM model_trials t
            WHERE t.revision=? AND t.synthetic=? AND t.passed=1
            AND (t.synthetic=1 OR EXISTS (SELECT 1 FROM model_trial_reports r WHERE r.trial=t.sequence))
            AND t.sequence=(
                SELECT max(sequence) FROM model_trials
                WHERE revision=t.revision AND synthetic=t.synthetic AND slot=t.slot)
        """, (revision, synthetic)).fetchall()
        if not rows:
            return None
        profile = json.loads(rows[0]["manifest"])
        if Catalog.pair_only_artifact(db, profile):
            return None
        return dict(profile, revision=revision, peaks={row["slot"]: row["peak_bytes"] for row in rows})

    def active(self, db, alias):
        row = db.execute("SELECT revision FROM model_aliases WHERE alias=? AND synthetic=?",
                         (alias, self.synthetic)).fetchone()
        return self.available(db, row["revision"], self.synthetic) if row else None

    def available(self, db, revision, synthetic):
        profile = self.qualified(db, revision, synthetic)
        if profile and profile.get("placement") == PAIR_ONLY:
            basis = db.execute("SELECT comparable FROM large_qualifications WHERE candidate=?",
                               (revision,)).fetchone()
            try:
                self.large_basis(db, revision, basis["comparable"])
            except Rejected:
                return None
        return profile

    def inspect(self, db):
        return {alias: self.active(db, alias) for alias in ALIASES}

    def latest_trial(self, db, revision, slot):
        """Expose the most recent evidence for an exact hardware and model pair."""
        if (not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{64}", revision)
                or slot not in EXECUTORS):
            raise Rejected("invalid_evidence")
        row = db.execute("""
            SELECT t.revision,t.slot,t.peak_bytes,t.passed,t.observed_at,r.report
            FROM model_trials t JOIN model_trial_reports r ON r.trial=t.sequence
            WHERE t.revision=? AND t.slot=? AND t.synthetic=0
            ORDER BY t.sequence DESC LIMIT 1
        """, (revision, slot)).fetchone()
        if row is None:
            return None
        return {**dict(row), "passed": bool(row["passed"]), "report": json.loads(row["report"])}

    def change(self, alias, expected, revision, *, synthetic=False):
        if alias not in ALIASES or type(synthetic) is not bool:
            raise Rejected("invalid_profile")
        with self.jobs.transaction() as db:
            previous = db.execute("SELECT revision FROM model_aliases WHERE alias=? AND synthetic=?",
                                  (alias, synthetic)).fetchone()
            if (previous["revision"] if previous else None) != expected:
                raise Rejected("conflict", 409)
            if revision is None:
                db.execute("DELETE FROM model_aliases WHERE alias=? AND synthetic=?", (alias, synthetic))
                return
            profile = self.available(db, revision, synthetic)
            if not profile or profile["alias"] != alias:
                raise Rejected("unqualified", 409)
            db.execute("INSERT INTO model_aliases VALUES (?,?,?) "
                       "ON CONFLICT(alias,synthetic) DO UPDATE SET revision=excluded.revision",
                       (alias, synthetic, revision))
