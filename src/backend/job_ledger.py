"""Private durable scheduler state and operator submission history."""

from contextlib import closing, contextmanager
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import tempfile
import time

from .enrollment import Rejected, STUDIOS, private_path

KEY = re.compile(r"[A-Za-z0-9_-]{1,64}")
IDENTIFIER = re.compile(r"[0-9a-f]{32}")
PROFILES = {"fake-single-v1": 1, "fake-pair-v1": 2}
RESIDENT = "fake-model-v1"
TOKEN_LIMIT = 4096
ACTIVE = ("preparing", "running")
EXECUTORS = ("fios-core", *STUDIOS)

SCHEMA = """
CREATE TABLE metadata (incarnation TEXT NOT NULL, restoring INTEGER NOT NULL DEFAULT 0);
CREATE TABLE jobs (
    position INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE,
    owner TEXT NOT NULL, request_key TEXT NOT NULL, intent TEXT NOT NULL,
    expires REAL NOT NULL, state TEXT NOT NULL, reason TEXT NOT NULL,
    outcome TEXT, generation INTEGER NOT NULL DEFAULT 0, reporter TEXT,
    receipts TEXT NOT NULL DEFAULT '{}', usage TEXT,
    UNIQUE(owner,request_key)
);
CREATE INDEX jobs_queue ON jobs(state,position);
CREATE INDEX jobs_owner ON jobs(owner,state,position);
CREATE TABLE events (
    position INTEGER PRIMARY KEY, job TEXT NOT NULL REFERENCES jobs(id),
    state TEXT NOT NULL, reason TEXT NOT NULL, at REAL NOT NULL
);
CREATE INDEX events_job ON events(job,position);
CREATE TABLE holds (
    slot TEXT PRIMARY KEY CHECK(slot IN ('studio-a','studio-b')),
    job TEXT REFERENCES jobs(id), session TEXT, grant TEXT, epoch TEXT,
    lease REAL, ready INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL,
    revision TEXT
);
PRAGMA user_version=1;
"""


def encoded(data):
    return json.dumps(data, sort_keys=True, separators=(",", ":"), allow_nan=False)


def integer(value, minimum, maximum):
    if type(value) is not int or not minimum <= value <= maximum:
        raise Rejected("invalid")
    return value


def identifier(value):
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        raise Rejected("invalid")
    return value


def usage_counts(value, limit, *, input_limit=None):
    if not isinstance(value, dict) or value.keys() - {"input", "output"}:
        raise Rejected("invalid_usage")
    result = {}
    for direction in ("input", "output"):
        count = value.get(direction, {"kind": "unknown"})
        if not isinstance(count, dict):
            raise Rejected("invalid_usage")
        kind = count.get("kind")
        if kind == "unknown" and count.keys() == {"kind"}:
            result[direction] = count
        elif kind in ("measured", "estimated") and count.keys() == {"kind", "value"}:
            bound = input_limit if direction == "input" and input_limit is not None else limit
            integer(count["value"], 0, bound)
            result[direction] = count
        else:
            raise Rejected("invalid_usage")
    return result


def usage_view(stored, *, synthetic=True):
    counts = json.loads(stored)
    measured = {direction: count["value"] for direction, count in counts.items()
                if count["kind"] == "measured"}
    partial = len(measured) < len(counts)
    # This fixed tariff applies only to the synthetic workload.
    cost = None
    if measured and synthetic:
        cost = {"amount": str(Decimal(sum(measured.values())) * Decimal("0.01")),
                "currency": "USD", "unit": "token", "tariff": "synthetic-v1",
                "partial": partial}
    return {"counts": counts, "measured": measured, "partial": partial, "cost": cost}


class JobLedger:
    @staticmethod
    def initialize(path):
        private_path(Path(path).parent, directory=True)
        Path(path).touch(mode=0o600, exist_ok=False)
        try:
            with closing(sqlite3.connect(path)) as db:
                db.executescript(SCHEMA)
                with db:
                    db.execute("INSERT INTO metadata(incarnation) VALUES (?)", (secrets.token_hex(16),))
        except BaseException:
            Path(path).unlink()
            raise

    def __init__(self, path, *, wall=time.time):
        self.path = Path(path).absolute()
        private_path(self.path.parent, directory=True)
        private_path(self.path)
        self.wall = wall
        with self.transaction(write=False) as db:
            if (db.execute("PRAGMA user_version").fetchone()[0] not in (1, 2)
                    or db.execute("PRAGMA quick_check").fetchone()[0] != "ok"
                    or db.execute("PRAGMA journal_mode").fetchone()[0] != "delete"
                    or db.execute("PRAGMA foreign_key_check").fetchone() is not None):
                raise ValueError("Invalid job ledger")
            self.incarnation(db)
            self.restoring(db)
            for table in ("jobs", "events", "holds"):
                db.execute(f"SELECT * FROM {table} LIMIT 0")

    def connect(self):
        db = sqlite3.connect(self.path.as_uri() + "?mode=rw", uri=True, timeout=0.25)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    @contextmanager
    def transaction(self, *, write=True):
        with closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE" if write else "BEGIN")
            yield db

    @staticmethod
    def incarnation(db):
        rows = db.execute("SELECT incarnation FROM metadata LIMIT 2").fetchall()
        if len(rows) != 1:
            raise ValueError("Invalid ledger incarnation")
        return identifier(rows[0][0])

    def context(self):
        with self.transaction(write=False) as db:
            return self.incarnation(db)

    @staticmethod
    def restoring(db):
        return bool(db.execute("SELECT restoring FROM metadata").fetchone()[0])

    def transition(self, db, job, state, reason, *, outcome=None):
        db.execute("UPDATE jobs SET state=?,reason=?,outcome=? WHERE id=?",
                   (state, reason, outcome, job))
        db.execute("INSERT INTO events(job,state,reason,at) VALUES (?,?,?,?)",
                   (job, state, reason, self.wall()))

    def submit(self, owner, request):
        if request.keys() != {"incarnation", "key", "profile", "tokens", "deadline"}:
            raise Rejected("invalid")
        expected = identifier(request["incarnation"])
        key, profile = request["key"], request["profile"]
        if not isinstance(key, str) or not KEY.fullmatch(key):
            raise Rejected("invalid")
        if not isinstance(profile, str) or profile not in PROFILES:
            raise Rejected("invalid_profile")
        tokens = integer(request["tokens"], 1, TOKEN_LIMIT)
        deadline = integer(request["deadline"], 1, 3600)
        intent = encoded({"profile": profile, "tokens": tokens, "deadline": deadline,
                          "resource_class": "synthetic", "project": None})
        return self.submit_intent(owner, expected, key, intent, deadline)

    def submit_intent(self, owner, expected, key, intent, deadline):
        """Deduplicate a validated intent before consuming queue capacity."""
        with self.transaction() as db:
            if expected != self.incarnation(db):
                raise Rejected("ledger_changed", 409)
            existing = db.execute("SELECT id,state,intent FROM jobs WHERE owner=? AND request_key=?",
                                  (owner, key)).fetchone()
            if existing:
                if existing["intent"] != intent:
                    raise Rejected("conflict", 409)
                return {"id": existing["id"], "state": existing["state"]}
            return self.enqueue(db, owner, key, intent, deadline)

    def enqueue(self, db, owner, key, intent, deadline):
        """Insert a validated job using the caller's write transaction."""
        if (db.execute("SELECT count(*) FROM jobs WHERE state='queued' AND owner=?",
                       (owner,)).fetchone()[0] >= 16
                or db.execute("SELECT count(*) FROM jobs WHERE state='queued'").fetchone()[0] >= 32):
            raise Rejected("queue_full", 429)
        if db.execute("SELECT count(*) FROM jobs").fetchone()[0] >= 10000:
            raise Rejected("ledger_full", 503)
        job = secrets.token_hex(16)
        db.execute("INSERT INTO jobs(id,owner,request_key,intent,expires,state,reason) "
                   "VALUES (?,?,?,?,?,'queued','waiting_capacity')",
                   (job, owner, key, intent, self.wall() + deadline))
        self.transition(db, job, "queued", "waiting_capacity")
        return {"id": job, "state": "queued"}

    @staticmethod
    def owned(db, owner, job):
        row = db.execute("SELECT * FROM jobs WHERE id=? AND owner=?", (job, owner)).fetchone()
        if row is None:
            raise Rejected("unknown_job", 404)
        return row

    @staticmethod
    def view(db, row):
        result = {name: row[name] for name in
                  ("position", "id", "owner", "expires", "state", "reason", "generation")}
        result["intent"] = json.loads(row["intent"])
        result["slots"] = [r[0] for r in db.execute(
            "SELECT slot FROM holds WHERE job=? ORDER BY slot", (row["id"],))]
        result["usage"] = (usage_view(row["usage"], synthetic=result["intent"]["resource_class"] == "synthetic")
                           if row["usage"] else None)
        return result

    def get(self, owner, job):
        with self.transaction(write=False) as db:
            return self.view(db, self.owned(db, owner, job))

    def list(self, owner, after, *, limit=50):
        with self.transaction(write=False) as db:
            rows = db.execute("SELECT * FROM jobs WHERE owner=? AND position>? ORDER BY position LIMIT ?",
                              (owner, after, limit)).fetchall()
            return [self.view(db, row) for row in rows]

    def events(self, owner, job, after):
        with self.transaction(write=False) as db:
            self.owned(db, owner, job)
            return [dict(row) for row in db.execute(
                "SELECT position,state,reason,at FROM events WHERE job=? AND position>? "
                "ORDER BY position LIMIT 50", (job, after))]

    def migrate(self):
        """Upgrade under the offline service lock, retaining all existing holds."""
        with self.transaction() as db:
            if db.execute("PRAGMA user_version").fetchone()[0] == 2:
                return
            db.execute("ALTER TABLE holds RENAME TO holds_v1")
            db.execute("""
                CREATE TABLE holds (
                    slot TEXT PRIMARY KEY CHECK(slot IN ('fios-core','studio-a','studio-b')),
                    job TEXT REFERENCES jobs(id), session TEXT, grant TEXT, epoch TEXT,
                    lease REAL, ready INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL,
                    revision TEXT
                )
            """)
            db.execute("""
                INSERT INTO holds(slot,job,session,grant,epoch,lease,ready,kind,revision)
                SELECT slot,job,session,grant,epoch,lease,ready,kind,revision FROM holds_v1
            """)
            db.execute("DROP TABLE holds_v1")
            db.execute("PRAGMA user_version=2")

    def backup(self, target):
        target = Path(target)
        private_path(target.parent, directory=True)
        target.touch(mode=0o600, exist_ok=False)
        try:
            with closing(self.connect()) as src, closing(sqlite3.connect(target)) as dst:
                src.backup(dst)
        except BaseException:
            target.unlink()
            raise

    def restore(self, snapshot):
        """Caller holds the offline service lock throughout staging and activation."""
        with self.transaction(write=False) as db:
            version = db.execute("PRAGMA user_version").fetchone()[0]
        snapshot = JobLedger(snapshot, wall=self.wall)
        with tempfile.TemporaryDirectory(prefix="job-restore-", dir=self.path.parent) as folder:
            staged = Path(folder) / self.path.name
            snapshot.backup(staged)
            candidate = JobLedger(staged, wall=self.wall)
            with candidate.transaction(write=False) as db:
                version = max(version, db.execute("PRAGMA user_version").fetchone()[0])
            executors = STUDIOS
            if version == 2:
                candidate.migrate()
                executors = EXECUTORS
            with candidate.transaction() as db:
                # v1 used a global barrier. v2's durable holds fence each
                # possible executor until that executor proves it is idle.
                db.execute("UPDATE metadata SET incarnation=?,restoring=?",
                           (secrets.token_hex(16), int(version == 1)))
                rows = db.execute("SELECT id FROM jobs WHERE state IN "
                                  "('queued','preparing','running','stopping')").fetchall()
                for (job,) in rows:
                    held = db.execute("SELECT 1 FROM holds WHERE job=?", (job,)).fetchone()
                    candidate.transition(db, job, "stopping" if held else "failed",
                                         "restore_history_unknown", outcome="failed" if held else None)
                db.execute("UPDATE holds SET kind='cleanup',grant=NULL,session=NULL,epoch=NULL")
                # A snapshot can predate an operator withdrawal or a failed trial.
                if db.execute("SELECT 1 FROM sqlite_master WHERE name='model_aliases'").fetchone():
                    db.execute("DELETE FROM model_aliases")
                db.executemany("INSERT OR IGNORE INTO holds(slot,kind) VALUES (?,'cleanup')",
                               [(slot,) for slot in executors])
            JobLedger(staged, wall=self.wall)
            os.replace(staged, self.path)
            # Make the directory entry durable before acknowledging activation.
            descriptor = os.open(self.path.parent, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
