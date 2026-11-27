"""Capacity rules for model qualification before a measured peak is known."""

from dataclasses import dataclass
import hashlib
import json
import re

from .enrollment import Rejected
from .job_ledger import EXECUTORS, encoded, integer

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
        if not isinstance(document, dict) or document.keys() != fields:
            raise Rejected("invalid_profile")
        host_classes = {"general-chat": "m4-pro-mini", "coding": "m3-ultra-studio"}
        alias = document["alias"]
        if not isinstance(alias, str) or alias not in host_classes or (
                host_classes[alias] != document["host_class"]):
            raise Rejected("invalid_profile")
        for name in digests:
            digest = document[name]
            if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                raise Rejected("invalid_profile")
        license_id = document["license"]
        if not isinstance(license_id, str) or not re.fullmatch(r"[A-Za-z0-9 .+_-]{1,80}", license_id):
            raise Rejected("invalid_profile")
        total = integer(document["context"], 2, 1_000_000)
        integer(document["output"], 1, total - 1)
        settings = document["settings"]
        if not isinstance(settings, dict) or settings.keys() != {"temperature"}:
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
        return {alias: self.active(db, alias) for alias in ("general-chat", "coding")}

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
        if alias not in ("general-chat", "coding") or type(synthetic) is not bool:
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
