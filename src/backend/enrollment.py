"""Durable slot bindings and process-local heartbeat state."""

from contextlib import closing
import os
from pathlib import Path
import re
import secrets
import sqlite3
import stat
import threading
import time

from .inventory import FIELDS, NODES, STALE_AFTER, valid_sample

STUDIOS = ("studio-a", "studio-b")
MACHINE = re.compile(r"[a-z0-9-]{1,64}")
PIN = re.compile(r"[0-9a-f]{64}")
HEARTBEAT = FIELDS | {"session", "sequence"}

SCHEMA = """
CREATE TABLE bindings (
    node TEXT PRIMARY KEY CHECK(node IN ('studio-a', 'studio-b')),
    machine TEXT NOT NULL UNIQUE, pin TEXT NOT NULL UNIQUE,
    state TEXT NOT NULL CHECK(state IN ('active', 'revoked'))
);
CREATE TABLE retired (pin TEXT PRIMARY KEY);
CREATE TABLE audit (id INTEGER PRIMARY KEY, action TEXT, node TEXT, at INTEGER, outcome TEXT);
PRAGMA user_version = 1;
"""


class Rejected(ValueError):
    def __init__(self, reason, status=400):
        super().__init__(reason)
        self.reason = reason
        self.status = status


def elapsed():
    # CLOCK_MONOTONIC_RAW on Darwin tracks mach_continuous_time, including sleep.
    clock = time.CLOCK_MONOTONIC_RAW if os.uname().sysname == "Darwin" else time.CLOCK_BOOTTIME
    return time.clock_gettime(clock)


def private_path(path, *, directory=False):
    info = path.lstat()
    expected = stat.S_ISDIR if directory else stat.S_ISREG
    if not expected(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise ValueError("Expected a private service-owned path")


class Ledger:
    @staticmethod
    def initialize(directory):
        directory = Path(directory)
        parent = directory.parent.lstat()
        if (not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.geteuid()
                or parent.st_mode & 0o022):
            raise ValueError("Expected an operator-owned state parent without shared write access")
        directory.mkdir(mode=0o700)
        path = directory / "enrollment.sqlite"
        path.touch(mode=0o600, exist_ok=False)
        with closing(sqlite3.connect(path)) as db:
            db.executescript(SCHEMA)

    def __init__(self, directory, *, wall=time.time, clock=elapsed):
        directory = Path(directory).absolute()
        private_path(directory, directory=True)
        path = directory / "enrollment.sqlite"
        private_path(path)
        self.uri = path.as_uri() + "?mode=rw"
        self.wall, self.clock = wall, clock
        self.lock = threading.RLock()
        self.sessions = {}
        self.observations = {}
        self.budgets = {}
        self.counters = {}
        with closing(self.connect()) as db:
            if (db.execute("PRAGMA user_version").fetchone() != (1,)
                    or db.execute("PRAGMA quick_check").fetchone() != ("ok",)):
                raise ValueError("Invalid enrollment ledger")
            for table in ("bindings", "retired", "audit"):
                db.execute(f"SELECT * FROM {table} LIMIT 0")

    def connect(self):
        return sqlite3.connect(self.uri, uri=True, timeout=0.25)

    def count(self, reason):
        with self.lock:
            self.counters[reason] = min(self.counters.get(reason, 0) + 1, 2**63 - 1)

    def change(self, action, node, expected, *, machine=None, pin=None):
        if node not in STUDIOS or action not in {"approve", "rotate", "revoke"}:
            raise Rejected("invalid")
        if expected is not None and not (isinstance(expected, str) and PIN.fullmatch(expected)):
            raise Rejected("invalid")
        if action != "revoke" and not (isinstance(pin, str) and PIN.fullmatch(pin)):
            raise Rejected("invalid")
        with self.lock, closing(self.connect()) as db:
            with db:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute(
                    "SELECT machine, pin, state FROM bindings WHERE node=?", (node,)
                ).fetchone()
                prior = row[1] if row else None
                if prior != expected or (action == "approve" and row and row[2] != "revoked"):
                    raise Rejected("conflict", 409)
                if action != "approve":
                    if not row or row[2] != "active":
                        raise Rejected("conflict", 409)
                    if machine is not None and machine != row[0]:
                        raise Rejected("conflict", 409)
                    machine = row[0]
                if not (isinstance(machine, str) and MACHINE.fullmatch(machine)):
                    raise Rejected("invalid")
                if action in {"rotate", "revoke"}:
                    db.execute("INSERT INTO retired VALUES (?)", (prior,))
                if action == "revoke":
                    db.execute("UPDATE bindings SET state='revoked' WHERE node=?", (node,))
                else:
                    if db.execute("SELECT 1 FROM retired WHERE pin=?", (pin,)).fetchone():
                        raise Rejected("conflict", 409)
                    try:
                        db.execute(
                            "INSERT INTO bindings VALUES (?, ?, ?, 'active') "
                            "ON CONFLICT(node) DO UPDATE SET machine=excluded.machine, "
                            "pin=excluded.pin, state='active'", (node, machine, pin)
                        )
                    except sqlite3.IntegrityError:
                        raise Rejected("conflict", 409) from None
                now = int(self.wall())
                db.execute("INSERT INTO audit(action,node,at,outcome) VALUES (?,?,?,'ok')",
                           (action, node, now))
                db.execute("DELETE FROM audit WHERE at < ? OR id <= "
                           "(SELECT max(id)-10000 FROM audit)", (now - 30 * 86400,))
            self.sessions.pop(node, None)
            self.observations.pop(node, None)
            self.budgets.pop(node, None)

    def verify_binding(self, node, pin):
        with closing(self.connect()) as db:
            active = db.execute("SELECT 1 FROM bindings WHERE node=? AND pin=? AND state='active'",
                                (node, pin)).fetchone()
        if not active:
            raise Rejected("identity", 403)
    def authorize(self, node, pin, route):
        self.verify_binding(node, pin)
        now = self.clock()
        key = node, route
        recent = [at for at in self.budgets.get(key, ()) if now - at < 10]
        if len(recent) >= {"session": 4, "heartbeat": 12, "scheduling": 30, "inference": 100}[route]:
            raise Rejected("limited", 429)
        self.budgets[key] = recent + [now]

    def open_session(self, node, pin):
        with self.lock:
            self.authorize(node, pin, "session")
            token = secrets.token_hex(16)
            self.sessions[node] = (token, 0, 0)
            return token

    def accept(self, node, pin, data):
        with self.lock:
            self.authorize(node, pin, "heartbeat")
            now = int(self.wall())
            if data.keys() != HEARTBEAT:
                raise Rejected("invalid")
            sample = {field: data[field] for field in FIELDS}
            if not valid_sample(sample, node, now + 5) or sample["sampled_at"] < now - STALE_AFTER:
                raise Rejected("invalid")
            session, highest, last_time = self.sessions.get(node, (None, 0, 0))
            if session is None or data["session"] != session:
                raise Rejected("session", 409)
            sequence = data["sequence"]
            if type(sequence) is not int or not 1 <= sequence < 2**63:
                raise Rejected("invalid")
            if sequence <= highest:
                raise Rejected("sequence", 409)
            if sample["sampled_at"] < last_time:
                raise Rejected("invalid")
            age = max(0, now - sample["sampled_at"])
            self.sessions[node] = (session, sequence, sample["sampled_at"])
            self.observations[node] = (sample, self.clock() + STALE_AFTER - age)

    def snapshot(self):
        with self.lock, closing(self.connect()) as db:
            bindings = dict(db.execute("SELECT node, state FROM bindings"))
            now = self.clock()
            nodes = {}
            for node in STUDIOS:
                enrollment = bindings.get(node, "not_enrolled")
                sample, deadline = self.observations.get(node, (None, 0))
                state = "awaiting"
                if enrollment == "active" and sample:
                    state = "reporting" if now <= deadline else "stale"
                else:
                    sample = None
                nodes[node] = dict(enrollment=enrollment, state=state, observation=sample)
            return nodes

    def status(self):
        with self.lock:
            return {"slots": {node: record["enrollment"] for node, record in self.snapshot().items()},
                    "rejections": dict(self.counters)}
