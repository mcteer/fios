"""Placement and lease transitions. Acquire enrollment authority before the job DB."""

import json
import secrets

from .enrollment import Rejected, STUDIOS
from .job_ledger import ACTIVE, PROFILES, RESIDENT, encoded, identifier, integer, usage_counts

LEASE = 15
IDLE = 60
MIB = 1024**2


class Scheduler:
    def __init__(self, jobs, enrollment, *, catalog=None):
        self.jobs, self.enrollment = jobs, enrollment
        self.catalog = catalog
        self.dispatch = None
        self.local_session = None
        self.clock = enrollment.clock
        initial_wall, initial_elapsed = enrollment.wall(), self.clock()

        def deadline_wall():
            # A backward wall-clock adjustment cannot extend a running process's
            # deadlines. Raw wall time still validates machine timestamps.
            return max(enrollment.wall(), initial_wall + self.clock() - initial_elapsed)

        self.wall = jobs.wall = deadline_wall
        self.epoch = secrets.token_hex(16)
        self.capacity = {}
        self.challenges = {}
        self.cleaned = {}
        with self.enrollment.lock, self.jobs.transaction() as db:
            # Persist holds, but never reuse elapsed deadlines or grants after restart.
            for row in db.execute("SELECT * FROM jobs WHERE state IN ('preparing','running')").fetchall():
                self.stop(db, row, "failed", "core_restart")
            db.execute("UPDATE holds SET kind='cleanup',grant=NULL,session=NULL,epoch=NULL")

    def open_local_session(self):
        """Called by the private channel after checking the Mini worker's OS identity."""
        if self.catalog is None:
            raise Rejected("scheduling_unavailable", 503)
        with self.enrollment.lock:
            self.local_session = secrets.token_hex(16)
            self.capacity.pop("fios-core", None)
            return self.local_session

    def local_capacity(self, session, data):
        with self.enrollment.lock:
            if self.local_session is None or session != self.local_session:
                raise Rejected("session", 409)
            if data.keys() != {"sequence", "sampled_at", "available_bytes", "resident_revision",
                               "memory_bytes", "pressure"}:
                raise Rejected("invalid")
            memory = integer(data["memory_bytes"], 1, 2**63 - 1)
            return self.store_capacity("fios-core", session, data, memory)

    def session(self, slot):
        if slot == "fios-core":
            return self.local_session
        return self.enrollment.sessions.get(slot, (None, 0, 0))[0]

    def fresh(self, slot):
        evidence = self.capacity.get(slot)
        if slot == "fios-core":
            if (evidence and self.local_session == evidence["session"]
                    and self.clock() <= evidence["expires"]):
                return evidence
            return None
        heartbeat, deadline = self.enrollment.observations.get(slot, (None, 0))
        session, highest, _ = self.enrollment.sessions.get(slot, (None, 0, 0))
        now = self.clock()
        if (heartbeat and highest and evidence and evidence["session"] == session
                and now <= min(deadline, evidence["expires"])):
            return evidence
        return None

    def stop(self, db, job, outcome, reason):
        held = db.execute("SELECT 1 FROM holds WHERE job=?", (job["id"],)).fetchone()
        self.jobs.transition(db, job["id"], "stopping" if held else outcome, reason,
                             outcome=outcome if held else None)
        db.execute("UPDATE holds SET kind='cleanup',grant=NULL WHERE job=?", (job["id"],))

    def sweep(self):
        """Commit fencing independently of any subsequent rejected worker request."""
        with self.enrollment.lock, self.jobs.transaction() as db:
            now, wall = self.clock(), self.wall()
            if self.catalog is not None:
                rows = db.execute("SELECT * FROM jobs WHERE state IN ('queued','preparing','running')")
                for row in rows.fetchall():
                    intent = json.loads(row["intent"])
                    if intent["resource_class"] == "inference" and not self.inference_profile(db, intent):
                        self.stop(db, row, "failed", "profile_unavailable")
                expired_streams = db.execute("""
                    SELECT jobs.*, a.ticket FROM chat_attachments a
                    JOIN jobs ON jobs.id=a.job WHERE a.expires<=?
                    AND jobs.state IN ('queued','preparing','running')
                """, (wall,)).fetchall()
                for row in expired_streams:
                    reason = "stream_disconnected" if row["ticket"] else "stream_unattached"
                    self.stop(db, row, "cancelled", reason)
            for row in db.execute("SELECT * FROM jobs WHERE state='queued' AND expires<=?",
                                  (wall,)).fetchall():
                self.stop(db, row, "expired", "job_deadline")
            for hold in db.execute("SELECT * FROM holds WHERE kind IN ('job','unload')").fetchall():
                lost = self.session(hold["slot"]) != hold["session"]
                expired = now >= hold["lease"]
                if hold["kind"] == "unload":
                    if lost or expired:
                        db.execute("UPDATE holds SET kind='cleanup',grant=NULL WHERE slot=?",
                                   (hold["slot"],))
                    continue
                row = db.execute("SELECT * FROM jobs WHERE id=?", (hold["job"],)).fetchone()
                done = hold["slot"] in json.loads(row["receipts"])
                if row["state"] in ACTIVE and (lost or (expired and not done) or wall >= row["expires"]):
                    outcome = "failed" if lost else "expired"
                    reason = "worker_changed" if lost else "lease_or_job_deadline"
                    self.stop(db, row, outcome, reason)

    def set_capacity(self, slot, session, data):
        sample, _ = self.enrollment.observations.get(slot, (None, 0))
        if not sample or not self.enrollment.sessions[slot][1]:
            raise Rejected("missing_heartbeat", 409)
        return self.store_capacity(slot, session, data, sample["memory_bytes"])

    def store_capacity(self, slot, session, data, memory):
        seq = integer(data["sequence"], 1, 2**63 - 1)
        now, wall = self.clock(), int(self.enrollment.wall())
        sampled = integer(data["sampled_at"], max(1, wall - 30), wall + 5)
        available = integer(data["available_bytes"], 0, memory)
        revision = data["resident_revision"]
        pressure = data.get("pressure")
        if self.catalog is None:
            if revision not in (None, RESIDENT):
                raise Rejected("invalid")
        elif (pressure not in ("normal", "warning", "critical")
              or (revision is not None and (not isinstance(revision, str) or len(revision) != 64
                                             or any(char not in "0123456789abcdef" for char in revision)))):
            raise Rejected("invalid")
        prior = self.capacity.get(slot)
        same_session = prior and prior["session"] == session
        if same_session and (seq <= prior["sequence"] or sampled < prior["sampled_at"]):
            raise Rejected("stale_capacity", 409)
        same_resident = (same_session and prior["revision"] == revision
                         and now <= prior["expires"])
        self.capacity[slot] = dict(session=session, sequence=seq, available=available,
                                   revision=revision, pressure=pressure, sampled_at=sampled, received=now,
                                   expires=now + 30 - max(0, wall - sampled),
                                   idle=prior["idle"] if same_resident else now)
        return {}

    def inference_profile(self, db, intent):
        if self.catalog is None:
            return None
        profile = self.catalog.active(db, intent["alias"])
        expected_policy = self.dispatch.policy_revision if self.dispatch else None
        if (profile and profile["revision"] == intent["profile"] and profile["output"] == intent["tokens"]
                and (expected_policy is None or expected_policy == profile["policy"])):
            return profile
        return None

    def eligible(self, db, intent, *, check_holds=True):
        held = {row[0] for row in db.execute("SELECT slot FROM holds")} if check_holds else set()
        if intent["resource_class"] == "inference":
            profile = self.inference_profile(db, intent)
            if not profile:
                return []
            fit = []
            for slot, peak in profile["peaks"].items():
                cap = self.fresh(slot)
                if slot not in held and cap and cap["pressure"] == "normal" and cap["available"] >= peak:
                    fit.append((cap["revision"] != profile["revision"], slot))
            return [min(fit)[1]] if fit else []
        if self.catalog is not None:
            return []
        fit = []
        for slot in STUDIOS:
            cap = self.fresh(slot)
            if slot in held or cap is None:
                continue
            warm = cap["revision"] == RESIDENT
            demand = (64 + 32 + (0 if warm else 256)) * MIB + intent["tokens"] * 4096
            if cap["available"] >= demand:
                fit.append((not warm, slot))
        count = PROFILES[intent["profile"]]
        return [slot for _, slot in sorted(fit)[:count]] if len(fit) >= count else []

    def describe(self, owner, *, job=None, after=0):
        """Compute queue reasons against one snapshot of evidence and holds."""
        with self.enrollment.lock, self.jobs.transaction(write=False) as db:
            rows = ([self.jobs.owned(db, owner, job)] if job else db.execute(
                "SELECT * FROM jobs WHERE owner=? AND position>? ORDER BY position LIMIT 8",
                (owner, after)))
            views = []
            for row in rows:
                view = self.jobs.view(db, row)
                if view["state"] == "queued":
                    intent = view["intent"]
                    if self.jobs.restoring(db):
                        view["reason"] = "restore_quarantine"
                    elif self.eligible(db, intent):
                        view["reason"] = "waiting_worker_poll"
                    elif self.eligible(db, intent, check_holds=False):
                        view["reason"] = "waiting_slots"
                views.append(view)
            return views

    def allocate(self, db, caller):
        # Only grant for the chosen slot's poll. An ineligible caller cannot move
        # the queue or create a reservation on another worker's behalf.
        rows = db.execute("SELECT * FROM jobs WHERE state='queued' AND expires>? ORDER BY position",
                          (self.wall(),)).fetchall()
        for row in rows:
            intent = json.loads(row["intent"])
            slots = self.eligible(db, intent)
            if caller not in slots:
                # A younger job may use a different eligible slot.
                continue
            job = row["id"]
            db.execute("UPDATE jobs SET generation=generation+1,reporter=? WHERE id=?",
                       (slots[0], job))
            lease = self.clock() + LEASE
            db.executemany("INSERT INTO holds(slot,job,session,grant,epoch,lease,kind) "
                           "VALUES (?,?,?,?,?,?,'job')",
                           [(slot, job, self.session(slot), secrets.token_hex(16), self.epoch, lease)
                            for slot in slots])
            self.jobs.transition(db, job, "preparing", "reserved")
            return

    def poll(self, db, slot, session):
        hold = db.execute("SELECT * FROM holds WHERE slot=?", (slot,)).fetchone()
        if hold is None and self.fresh(slot) and not self.jobs.restoring(db):
            self.allocate(db, slot)
            hold = db.execute("SELECT * FROM holds WHERE slot=?", (slot,)).fetchone()
            cap = self.fresh(slot)
            if hold is None and cap["revision"] and self.clock() - cap["idle"] >= IDLE:
                db.execute("INSERT INTO holds(slot,session,grant,epoch,lease,kind,revision) "
                           "VALUES (?,?,?,?,?,'unload',?)",
                           (slot, session, secrets.token_hex(16), self.epoch,
                            self.clock() + LEASE, cap["revision"]))
                hold = db.execute("SELECT * FROM holds WHERE slot=?", (slot,)).fetchone()
        if hold is None:
            return {"action": "wait", "delay": 2}
        if hold["kind"] == "cleanup":
            return {"action": "stop", "challenge": self.challenge(slot, session)}
        if hold["kind"] == "unload":
            return {"action": "unload", "revision": hold["revision"],
                    "challenge": self.challenge(slot, session),
                    "remaining": max(0, hold["lease"] - self.clock())}
        row = db.execute("SELECT * FROM jobs WHERE id=?", (hold["job"],)).fetchone()
        if slot in json.loads(row["receipts"]):
            return {"action": "wait", "delay": 2}
        result = {"action": "start" if row["state"] == "running" else "prepare",
                  "job": row["id"], "generation": row["generation"], "grant": hold["grant"],
                "epoch": self.epoch, "profile": json.loads(row["intent"])["profile"],
                "reporter": row["reporter"] == slot,
                "remaining": max(0, min(hold["lease"] - self.clock(),
                                        row["expires"] - self.wall()))}
        if self.catalog is not None:
            result["job_remaining"] = max(0, row["expires"] - self.wall())
        return result

    def challenge(self, slot, session):
        challenge = self.challenges.get(slot)
        if challenge is None or challenge["session"] != session:
            capacity = self.capacity.get(slot, {})
            challenge = dict(session=session, token=secrets.token_hex(16),
                             received=self.clock(), wall=int(self.enrollment.wall()),
                             floor=capacity.get("sequence", 0) if capacity.get("session") == session else 0)
            self.challenges[slot] = challenge
        return challenge["token"]

    def cleanup(self, db, slot, session, data):
        token = identifier(data["challenge"])
        sequence = integer(data["sequence"], 1, 2**63 - 1)
        if data["disposition"] != "quiescent":
            raise Rejected("invalid")
        if self.cleaned.get(slot) == (session, token, sequence):
            return {}
        held = db.execute("SELECT * FROM holds WHERE slot=?", (slot,)).fetchone()
        challenge = self.challenges.get(slot)
        cap = self.fresh(slot)
        if (not held or held["kind"] not in ("cleanup", "unload")
                or not challenge or challenge["token"] != token or challenge["session"] != session
                or not cap or sequence != cap["sequence"] or sequence <= challenge["floor"]
                or cap["received"] < challenge["received"] or cap["sampled_at"] < challenge["wall"]
                or (held["kind"] == "unload" and cap["revision"] is not None)):
            raise Rejected("cleanup_required", 409)
        db.execute("DELETE FROM holds WHERE slot=?", (slot,))
        # A restored snapshot cannot identify newer work on either slot. Admit
        # nothing until both independently establish that their executor is clean.
        if self.jobs.restoring(db) and not db.execute("SELECT 1 FROM holds").fetchone():
            db.execute("UPDATE metadata SET restoring=0")
        if held["job"] and not db.execute("SELECT 1 FROM holds WHERE job=?", (held["job"],)).fetchone():
            job = db.execute("SELECT * FROM jobs WHERE id=?", (held["job"],)).fetchone()
            if job["state"] == "stopping":
                self.jobs.transition(db, job["id"], job["outcome"], job["reason"])
        return {"clean_ack": (session, token, sequence)}

    def require_grant(self, hold, row, session, grant):
        if (not hold or hold["kind"] != "job" or hold["session"] != session
                or hold["grant"] != grant or hold["epoch"] != self.epoch
                or self.clock() >= hold["lease"] or self.wall() >= row["expires"]
                or row["state"] not in ACTIVE):
            raise Rejected("fenced", 409)

    def authorize_payload(self, db, slot, session, data):
        job = identifier(data["job"])
        row = db.execute("SELECT * FROM jobs WHERE id=?", (job,)).fetchone()
        if (not row or row["state"] != "running" or data["epoch"] != self.epoch
                or integer(data["generation"], 1, 2**63 - 1) != row["generation"]
                or session != self.session(slot)):
            raise Rejected("fenced", 409)
        intent = json.loads(row["intent"])
        if intent["resource_class"] != "inference":
            raise Rejected("fenced", 409)
        profile = self.inference_profile(db, intent)
        if not profile or slot not in profile["peaks"]:
            raise Rejected("fenced", 409)
        hold = db.execute("SELECT * FROM holds WHERE slot=? AND job=?", (slot, job)).fetchone()
        self.require_grant(hold, row, session, identifier(data["grant"]))
        return profile

    def assignment(self, db, operation, slot, session, data):
        job, grant = identifier(data["job"]), identifier(data["grant"])
        generation = integer(data["generation"], 1, 2**63 - 1)
        if data["epoch"] != self.epoch:
            raise Rejected("fenced", 409)
        row = db.execute("SELECT * FROM jobs WHERE id=?", (job,)).fetchone()
        if row is None or row["generation"] != generation:
            raise Rejected("fenced", 409)
        intent = json.loads(row["intent"])
        profile = None
        if intent["resource_class"] == "inference":
            profile = self.inference_profile(db, intent)
            if not profile or slot not in profile["peaks"]:
                raise Rejected("fenced", 409)
        receipts = json.loads(row["receipts"])
        hold = db.execute("SELECT * FROM holds WHERE slot=? AND job=?", (slot, job)).fetchone()
        settlement = None
        if operation == "finish":
            allowed = ("ok", "failed", "withheld") if profile else ("ok", "failed")
            if data["result"] not in allowed:
                raise Rejected("invalid")
            if "usage" in data and row["reporter"] != slot:
                raise Rejected("usage_authority", 403)
            input_limit = profile["context"] - profile["output"] if profile else None
            counts = usage_counts(data.get("usage", {}), intent["tokens"], input_limit=input_limit)
            settlement = dict(session=session, grant=grant, epoch=self.epoch,
                              result=data["result"], usage=counts)
            if slot in receipts:
                if receipts[slot] != settlement:
                    raise Rejected("conflict", 409)
                return {"accepted": True}
        self.require_grant(hold, row, session, grant)
        if operation in ("ready", "renew"):
            capacity = self.fresh(slot)
            if not capacity or (profile and capacity["pressure"] != "normal"):
                raise Rejected("stale_capacity", 409)
            if profile and operation == "ready" and capacity["available"] < profile["peaks"][slot]:
                raise Rejected("stale_capacity", 409)
        if operation == "ready":
            db.execute("UPDATE holds SET ready=1 WHERE slot=?", (slot,))
            peers = db.execute("SELECT slot,ready,lease FROM holds WHERE job=?", (job,)).fetchall()
            if row["state"] == "preparing" and all(
                    peer["ready"] and self.fresh(peer["slot"]) and self.clock() < peer["lease"]
                    for peer in peers):
                self.jobs.transition(db, job, "running", "all_ready")
        elif operation == "renew":
            if slot in receipts:
                raise Rejected("fenced", 409)
            db.execute("UPDATE holds SET lease=? WHERE slot=?", (self.clock() + LEASE, slot))
            return {"remaining": min(LEASE, row["expires"] - self.wall())}
        else:
            if row["state"] != "running":
                raise Rejected("not_started", 409)
            if profile and settlement["result"] == "ok":
                if (self.dispatch is None or not db.execute(
                        "SELECT 1 FROM content.segments WHERE job=? AND policy=?",
                        (job, profile["policy"])).fetchone()):
                    raise Rejected("unpublished", 409)
            receipts[slot] = settlement
            db.execute("UPDATE jobs SET receipts=? WHERE id=?", (encoded(receipts), job))
            if row["reporter"] == slot:
                db.execute("UPDATE jobs SET usage=? WHERE id=?", (encoded(settlement["usage"]), job))
            if settlement["result"] == "failed":
                self.stop(db, row, "failed", "worker_failed")
            elif settlement["result"] == "withheld":
                self.stop(db, row, "denied", "publication_withheld")
            elif len(receipts) == (1 if profile else PROFILES[intent["profile"]]):
                self.jobs.transition(db, job, "succeeded", "completed")
                if profile:
                    self.dispatch.conversations.reconcile(db)
                db.execute("UPDATE holds SET kind='cleanup',grant=NULL WHERE job=?", (job,))
            return {"accepted": True}
        return {}

    def cancel(self, owner, job):
        with self.enrollment.lock:
            self.sweep()
            with self.jobs.transaction() as db:
                row = self.jobs.owned(db, owner, job)
                if row["state"] in (*ACTIVE, "queued"):
                    self.stop(db, row, "cancelled", "operator_cancelled")
                return self.jobs.view(db, self.jobs.owned(db, owner, job))
