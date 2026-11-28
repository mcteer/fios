"""Capacity rules for model qualification before a measured peak is known."""

from dataclasses import dataclass
import hashlib
import json
import re

from .enrollment import Rejected, STUDIOS
from .job_ledger import EXECUTORS, encoded, identifier, integer

from .pair_trial import digest, paired_rdma, transport_observation

ALIASES = ("general-chat", "coding", "paired-coding")
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
        paired = alias == "paired-coding"
        if document.keys() != (fields | {"devices"} if paired else fields):
            raise Rejected("invalid_profile")
        if paired:
            devices = document["devices"]
            if (not isinstance(devices, dict) or devices.keys() != set(STUDIOS)
                    or len({digest(value) for value in devices.values()}) != 2):
                raise Rejected("invalid_profile")
        host_classes = {"general-chat": "m4-pro-mini", "coding": "m3-ultra-studio",
                        "paired-coding": "m3-ultra-pair"}
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
CREATE TABLE IF NOT EXISTS model_aliases (
    alias TEXT NOT NULL, synthetic INTEGER NOT NULL, revision TEXT NOT NULL,
    PRIMARY KEY(alias,synthetic)
);
"""


class Catalog:
    """Store qualification evidence produced by the trusted trial runner."""

    def __init__(self, jobs, *, synthetic=False):
        self.jobs = jobs
        self.synthetic = synthetic
        with jobs.transaction() as db:
            for statement in CATALOG.split(";"):
                if statement.strip():
                    db.execute(statement)

    def record(self, profile, evidence):
        if (not isinstance(evidence, dict)
                or evidence.keys() not in ({"slot", "peak_bytes", "passed", "synthetic"},
                                           {"slot", "peak_bytes", "passed", "synthetic", "report"})
                or type(evidence["passed"]) is not bool or type(evidence["synthetic"]) is not bool):
            raise Rejected("invalid_evidence")
        manifest = profile.document()
        slot = evidence["slot"]
        if manifest["alias"] == "paired-coding":
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
        table = "synthetic_pair_trials" if synthetic else "qualified_pairs"
        pair = db.execute(f"SELECT manifest, peaks FROM {table} WHERE revision=?", (revision,)).fetchone()
        if pair:
            return dict(json.loads(pair["manifest"]), revision=revision, peaks=json.loads(pair["peaks"]))
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
        return dict(profile, revision=revision, peaks={row["slot"]: row["peak_bytes"] for row in rows})

    def active(self, db, alias):
        row = db.execute("SELECT revision FROM model_aliases WHERE alias=? AND synthetic=?",
                         (alias, self.synthetic)).fetchone()
        return self.qualified(db, row["revision"], self.synthetic) if row else None

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
            profile = self.qualified(db, revision, synthetic)
            if not profile or profile["alias"] != alias:
                raise Rejected("unqualified", 409)
            db.execute("INSERT INTO model_aliases VALUES (?,?,?) "
                       "ON CONFLICT(alias,synthetic) DO UPDATE SET revision=excluded.revision",
                       (alias, synthetic, revision))
