"""Placement and lease transitions. Acquire enrollment authority before the job DB."""

import json
import secrets

from .enrollment import Rejected, STUDIOS
from .job_ledger import ACTIVE, PROFILES, RESIDENT, encoded, identifier, integer, usage_counts
from .moe_measurements import rank_phases
from .moe_review import TrialReview
from .pair_trial import PAIR_ONLY, digest, paired_rdma, recipe_name, recipes, transport_observation, trial_measurement

LEASE = 15
IDLE = 60
MIB = 1024**2


class Scheduler:
    def __init__(self, jobs, enrollment, *, catalog=None, trial_recipes=None, trial_hardware=False):
        self.jobs, self.enrollment = jobs, enrollment
        self.catalog = catalog
        self.trial_hardware = trial_hardware
        self.trial_recipes = recipes({} if trial_recipes is None else trial_recipes)
        self.dispatch = None
        self.local_session = None
        self.clock = enrollment.clock
        initial_wall, initial_elapsed = enrollment.wall(), self.clock()

        def deadline_wall():
            # A backward wall-clock adjustment cannot extend a running process's
            # deadlines. Raw wall time still validates machine timestamps.
            return max(enrollment.wall(), initial_wall + self.clock() - initial_elapsed)

        self.wall = jobs.wall = deadline_wall
        self.reviews = TrialReview(self.clock)
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
        if outcome != "succeeded":
            self.reviews.samples.pop(job["id"], None)

    def sweep(self):
        """Commit fencing independently of any subsequent rejected worker request."""
        with self.enrollment.lock, self.jobs.transaction() as db:
            now, wall = self.clock(), self.wall()
            self.reviews.purge(db)
            if self.catalog is not None:
                rows = db.execute("SELECT * FROM jobs WHERE state IN ('queued','preparing','running')")
                for row in rows.fetchall():
                    intent = json.loads(row["intent"])
                    if intent["resource_class"] == "pair_trial":
                        if not self.trial_recipe(db, intent, starting=row["state"] != "running"):
                            self.stop(db, row, "failed", "profile_unavailable")
                    elif intent["resource_class"] == "inference" and not self.inference_profile(db, intent):
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
        large_revision = digest(data["large_revision"]) if data.get("version") == 3 else None
        single_capable = data.get("single_capable", True)
        if type(single_capable) is not bool:
            raise Rejected("invalid")
        self.capacity[slot] = dict(session=session, sequence=seq, available=available,
                                   revision=revision, pressure=pressure, sampled_at=sampled, received=now,
                                   pair_capable=data.get("version") in (2, 3), large_revision=large_revision,
                                   single_capable=single_capable,
                                   expires=now + 30 - max(0, wall - sampled),
                                   idle=prior["idle"] if same_resident else now)
        return {}

    def submit_trial(self, owner, data):
        name, candidate = recipe_name(data["recipe"]), digest(data["candidate"])
        approved = self.trial_recipes.get(name)
        if self.catalog is None or not approved or approved["candidate"] != candidate:
            raise Rejected("trial_unavailable", 409)
        approval = data.get("approval")
        if approval is not None and not self.trial_hardware:
            raise Rejected("large_trial_unavailable", 409)
        intent = dict(resource_class="pair_trial", profile=candidate,
                      recipe=name, review=approved, tokens=approved["tokens"],
                      hardware=self.trial_hardware)
        if approval is not None:
            intent["stage_approval"] = integer(approval, 1, 2**63 - 1)
        expected = identifier(data["incarnation"])
        key = recipe_name(data["key"])
        return self.jobs.submit_intent(
            owner, expected, key, encoded(intent), approved["deadline"],
            validate=lambda db: self.catalog.check_trial_placement(db, approved, approval))

    def trial_recipe(self, db, intent, *, starting=True):
        reviewed = self.trial_recipes.get(intent["recipe"])
        if reviewed != intent["review"] or not reviewed:
            return None
        try:
            self.catalog.check_trial_placement(db, reviewed, intent.get("stage_approval"), starting=starting)
        except Rejected:
            return None
        return reviewed

    def trial_capacity(self, slot, budget, *, preparing, large_revision=None):
        cap = self.fresh(slot)
        required = budget["floor"] + (budget["ceiling"] if preparing else 0)
        return (cap and cap["pair_capable"] and cap["pressure"] == "normal"
                and (large_revision is None or cap["large_revision"] == large_revision) and cap["available"] >= required)

    def inference_profile(self, db, intent):
        if self.catalog is None:
            return None
        profile = (self.catalog.rehearsal_profile(db) if "rehearsal" in intent
                   else self.catalog.active(db, intent["alias"]))
        if "rehearsal" in intent and profile and profile["rehearsal"] != intent["rehearsal"]:
            return None
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
                if (slot not in held and cap and cap["pressure"] == "normal" and cap["available"] >= peak
                        and (profile.get("placement") != PAIR_ONLY or cap["large_revision"] == profile["revision"])
                        and ("devices" in profile or cap["single_capable"])):
                    fit.append((cap["revision"] != profile["revision"], slot))
            if "devices" in profile:
                return list(STUDIOS) if (len(fit) == len(STUDIOS)
                                         and all(self.fresh(slot)["pair_capable"] for slot in STUDIOS)) else []
            return [min(fit)[1]] if fit else []
        if intent["resource_class"] == "pair_trial":
            approved = self.trial_recipe(db, intent)
            if approved and all(slot not in held and self.trial_capacity(
                                    slot, budget, preparing=True,
                                    large_revision=intent["profile"] if "stage_approval" in intent else None)
                                for slot, budget in approved["budgets"].items()):
                return sorted(approved["budgets"])
            return []
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

    def pair_status(self):
        """Return bounded operator diagnostics without conversation or lease identifiers."""
        self.sweep()
        with self.enrollment.lock, self.jobs.transaction(write=False) as db:
            active = self.catalog.active(db, "paired-coding") if self.catalog else None
            row = db.execute("""
                SELECT jobs.* FROM jobs
                WHERE json_extract(intent,'$.resource_class')='pair_trial'
                   OR json_extract(intent,'$.alias')='paired-coding'
                ORDER BY CASE WHEN state IN ('preparing','running','stopping') THEN 0
                              WHEN state='queued' THEN 1 ELSE 2 END, position DESC
                LIMIT 1
            """).fetchone()
            state, reason = ("unavailable", "unqualified") if not active else ("available", "ready")
            if active and not self.eligible(db, dict(resource_class="inference", alias="paired-coding",
                                                    profile=active["revision"], tokens=active["output"])):
                state, reason = "unavailable", "waiting_capacity"
            ranks = [{"slot": slot, "fresh": bool(self.fresh(slot)), "phase": "idle"} for slot in STUDIOS]
            if row:
                current, reason = row["state"], row["reason"]
                states = dict(queued="queued", preparing="preparing", running="running",
                              stopping="cleaning", failed="degraded", expired="degraded")
                state = states.get(current, state)
                holds = {entry["slot"]: entry for entry in
                         db.execute("SELECT slot,kind,ready FROM holds WHERE job=?", (row["id"],))}
                receipts = json.loads(row["receipts"])
                for rank in ranks:
                    slot = rank["slot"]
                    hold = holds.get(slot)
                    if hold:
                        rank["phase"] = "cleaning" if hold["kind"] == "cleanup" else (
                            "ready" if hold["ready"] else "reserved")
                    if slot in receipts:
                        transfers = receipts[slot].get("transport_evidence", {}).get("transfers", [])
                        if transfers:
                            rank["transport"] = ",".join(sorted({entry["transport"] for entry in transfers}))
            return dict(state=state, reason=reason, ranks=ranks)

    def describe(self, owner, *, job=None, after=0, diagnostics=False):
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
                if diagnostics and view["intent"]["resource_class"] == "pair_trial":
                    # Receipts also store credentials for idempotent replay.
                    # The operator view only needs results and transport evidence.
                    view["ranks"] = {
                        slot: {key: receipt[key] for key in ("result", "transport_evidence", "trial_measurement",
                                                           "phase_observation", "review_output")
                               if key in receipt}
                        for slot, receipt in json.loads(row["receipts"]).items()
                    }
                views.append(view)
            return views

    def allocate(self, db, caller, *, pair_capable=False, large_capable=False):
        # Only grant for the chosen slot's poll. An ineligible caller cannot move
        # the queue or create a reservation on another worker's behalf.
        rows = db.execute("SELECT * FROM jobs WHERE state='queued' AND expires>? ORDER BY position",
                          (self.wall(),)).fetchall()
        for row in rows:
            intent = json.loads(row["intent"])
            if intent["resource_class"] == "pair_trial" and not pair_capable:
                continue
            if ("stage_approval" in intent or intent.get("alias") == "large-moe") and not large_capable:
                continue
            slots = self.eligible(db, intent)
            if caller not in slots or (len(slots) > 1 and intent["resource_class"] == "inference"
                                       and not pair_capable):
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

    def poll(self, db, slot, session, *, pair_capable=False, large_capable=False):
        hold = db.execute("SELECT * FROM holds WHERE slot=?", (slot,)).fetchone()
        if hold is None and self.fresh(slot) and not self.jobs.restoring(db):
            self.allocate(db, slot, pair_capable=pair_capable, large_capable=large_capable)
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
        intent = json.loads(row["intent"])
        if intent["resource_class"] == "pair_trial":
            approved = self.trial_recipe(db, intent, starting=row["state"] != "running")
            if not pair_capable or not approved or ("stage_approval" in intent and not large_capable):
                raise Rejected("protocol_version", 409)
            result["trial"] = dict(recipe=intent["recipe"], fixture=approved["fixture"],
                                   engine=approved["engine"], budget=approved["budgets"][slot],
                                   device=approved["devices"][slot], tokens=approved["tokens"],
                                   world_size=len(approved["budgets"]),
                                   rank=sorted(approved["budgets"]).index(slot))
            if "stage_approval" in intent:
                authority = self.catalog.stage_authority(
                    db, intent["profile"], intent["stage_approval"], approved["stage"],
                    starting=row["state"] != "running")
                result["trial"].update(placement=PAIR_ONLY, stage=approved["stage"],
                                       artifact=approved["artifact"], approval=intent["stage_approval"],
                                       staged_artifact=authority.get("probe_digest", authority["artifact"]))
                if "review" in approved:
                    result["trial"]["review"] = approved["review"]
        if intent["resource_class"] == "inference":
            profile = self.inference_profile(db, intent)
            if profile and "devices" in profile:
                if not pair_capable:
                    raise Rejected("protocol_version", 409)
                result["pair"] = dict(rank=STUDIOS.index(slot), device=profile["devices"][slot])
                if profile.get("placement") == PAIR_ONLY:
                    if not large_capable:
                        raise Rejected("protocol_version", 409)
                    if result["action"] == "start" and not result["reporter"]:
                        # The reporter checks the complete prompt before loading.
                        # Keep the follower out of JACCL until that check finishes.
                        reviewed = self.dispatch is not None and db.execute(
                            "SELECT 1 FROM content.prompt_snapshots WHERE job=?", (row["id"],)).fetchone()
                        if not reviewed:
                            result["action"] = "prepare"
                    result["pair"].update(placement=PAIR_ONLY, stage="full", world_size=2,
                                          artifact=profile["artifact"], staged_artifact=profile["artifact"],
                                          budget=profile["budgets"][slot])
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
        if not profile or slot not in profile["peaks"] or row["reporter"] != slot:
            raise Rejected("fenced", 409)
        hold = db.execute("SELECT * FROM holds WHERE slot=? AND job=?", (slot, job)).fetchone()
        self.require_grant(hold, row, session, identifier(data["grant"]))
        if "devices" in profile:
            peer_slot = STUDIOS[1]
            peer = db.execute("SELECT * FROM holds WHERE job=? AND slot=?", (job, peer_slot)).fetchone()
            receipt = json.loads(row["receipts"]).get(peer_slot)
            if not peer or peer["kind"] != "job" or peer["session"] != self.session(peer_slot):
                raise Rejected("fenced", 409)
            if not receipt:
                self.require_grant(peer, row, self.session(peer_slot), peer["grant"])
            elif receipt["result"] != "ok":
                raise Rejected("fenced", 409)
        return profile

    def assignment(self, db, operation, slot, session, data, *, pair_capable=False, large_capable=False):
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
        paired = profile and "devices" in profile
        if paired and not pair_capable:
            raise Rejected("protocol_version", 409)
        trial = None
        large = "stage_approval" in intent or (profile and profile.get("placement") == PAIR_ONLY)
        if large and not large_capable:
            raise Rejected("protocol_version", 409)
        if intent["resource_class"] == "pair_trial":
            trial = self.trial_recipe(db, intent, starting=row["state"] != "running")
            if (not pair_capable or not trial or slot not in trial["budgets"]
                    or (large and not large_capable)):
                raise Rejected("fenced", 409)
        budget = (trial or profile)["budgets"][slot] if large else None
        receipts = json.loads(row["receipts"])
        hold = db.execute("SELECT * FROM holds WHERE slot=? AND job=?", (slot, job)).fetchone()
        settlement = None
        review = trial.get("review") if large and trial else None
        if operation == "review-append":
            if not review or row["reporter"] != slot or row["state"] != "running" or slot in receipts:
                raise Rejected("review_authority", 403)
            self.require_grant(hold, row, session, grant)
            return self.reviews.append(row, review, data["sequence"], data["data"], case=trial["case"])
        if operation == "finish":
            allowed = ("ok", "failed", "withheld") if profile else ("ok", "failed")
            if data["result"] not in allowed:
                raise Rejected("invalid")
            if "usage" in data and (trial or row["reporter"] != slot):
                raise Rejected("usage_authority", 403)
            input_limit = profile["context"] - profile["output"] if profile else None
            counts = usage_counts(data.get("usage", {}), intent["tokens"], input_limit=input_limit)
            settlement = dict(session=session, grant=grant, epoch=self.epoch,
                              result=data["result"], usage=counts)
            if "trial_measurement" in data:
                if not trial and not large:
                    raise Rejected("trial_measurement_authority", 403)
                input_limit = None
                if large:
                    manifest, = db.execute("SELECT manifest FROM large_candidates WHERE revision=?",
                                           (intent["profile"],)).fetchone()
                    profile_limits = json.loads(manifest)
                    input_limit = profile_limits["context"] - profile_limits["output"]
                settlement["trial_measurement"] = trial_measurement(
                    data["trial_measurement"], ceiling=(budget or trial["budgets"][slot])["ceiling"],
                    deadline=trial["deadline"] if trial else intent["deadline"],
                    tokens=intent["tokens"], input_limit=input_limit)
            if large and data["result"] == "ok":
                if "trial_measurement" not in settlement:
                    raise Rejected("missing_trial_measurement")
                settlement["phase_observation"] = rank_phases(
                    data.get("phase_observation"), attempt=job,
                    ceiling=budget["ceiling"], deadline_ms=(trial["deadline"] if trial else intent["deadline"]) * 1000)
            elif "phase_observation" in data:
                raise Rejected("invalid_phase_evidence")
            if "failure" in data:
                allowed_failures = {"transport_unavailable"}
                if large:
                    allowed_failures.add("unsafe_rank_resources")
                if large and trial:
                    allowed_failures.add("context_limit")
                if (not (trial or paired) or data["result"] != "failed"
                        or data["failure"] not in allowed_failures):
                    raise Rejected("invalid_failure")
                settlement["failure"] = data["failure"]
            evidence = data.get("transport_evidence")
            pair = profile if paired else trial if trial and len(trial["budgets"]) == 2 else None
            if pair and data["result"] == "ok":
                settlement["transport_evidence"] = transport_observation(
                    evidence, candidate=intent["profile"], device=pair["devices"][slot], attempt=job)
            elif "transport_evidence" in data:
                raise Rejected("invalid_transport")
            if review and row["reporter"] == slot and data["result"] == "ok":
                prior = receipts.get(slot, {}).get("review_output")
                settlement["review_output"] = self.reviews.complete(job, data.get("review_output"), prior)
            elif "review_output" in data:
                raise Rejected("review_authority", 403)
            if slot in receipts:
                if receipts[slot] != settlement:
                    raise Rejected("conflict", 409)
                return {"accepted": True}
        self.require_grant(hold, row, session, grant)
        if operation in ("ready", "renew"):
            capacity = self.fresh(slot)
            if not capacity or (profile and capacity["pressure"] != "normal"):
                raise Rejected("stale_capacity", 409)
            if trial and not self.trial_capacity(slot, trial["budgets"][slot],
                                                preparing=row["state"] == "preparing",
                                                large_revision=intent["profile"] if large else None):
                raise Rejected("stale_capacity", 409)
            if large and profile and not self.trial_capacity(slot, budget,
                    preparing=row["state"] == "preparing", large_revision=intent["profile"]):
                raise Rejected("stale_capacity", 409)
            if profile and operation == "ready" and capacity["available"] < profile["peaks"][slot]:
                raise Rejected("stale_capacity", 409)
        if operation == "ready":
            db.execute("UPDATE holds SET ready=1 WHERE slot=?", (slot,))
            if large and paired and row["state"] == "running" and slot != row["reporter"] and slot not in receipts:
                # The checked prompt can take longer than one lease. Await it
                # under repeated authenticated readiness and capacity checks.
                db.execute("UPDATE holds SET lease=? WHERE slot=?", (self.clock() + LEASE, slot))
            peers = db.execute("SELECT slot,ready,lease FROM holds WHERE job=?", (job,)).fetchall()
            if row["state"] == "preparing" and all(
                    peer["ready"] and self.fresh(peer["slot"]) and self.clock() < peer["lease"]
                    and (not paired or (
                        self.fresh(peer["slot"])["pair_capable"]
                        and self.fresh(peer["slot"])["pressure"] == "normal"
                        and self.fresh(peer["slot"])["available"] >= profile["peaks"][peer["slot"]]
                        and (not large or self.fresh(peer["slot"])["large_revision"] == intent["profile"])))
                    and (not trial or self.trial_capacity(peer["slot"], trial["budgets"][peer["slot"]],
                                                         preparing=True, large_revision=intent["profile"] if large else None))
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
            if profile and row["reporter"] == slot and settlement["result"] == "ok":
                if (self.dispatch is None or not db.execute(
                        "SELECT 1 FROM content.segments WHERE job=? AND policy=?",
                        (job, profile["policy"])).fetchone()):
                    raise Rejected("unpublished", 409)
            receipts[slot] = settlement
            db.execute("UPDATE jobs SET receipts=? WHERE id=?", (encoded(receipts), job))
            if not trial and not paired and row["reporter"] == slot:
                db.execute("UPDATE jobs SET usage=? WHERE id=?", (encoded(settlement["usage"]), job))
            if settlement["result"] == "failed":
                self.stop(db, row, "failed", settlement.get("failure", "worker_failed"))
            elif settlement["result"] == "withheld":
                self.stop(db, row, "denied", "publication_withheld")
            elif (paired and len(receipts) == 2) or (trial and len(receipts) == len(trial["budgets"])):
                self.complete_pair_work(db, row, receipts, trial=bool(trial))
            elif not trial and not paired and len(receipts) == (1 if profile else PROFILES[intent["profile"]]):
                self.jobs.transition(db, job, "succeeded", "completed")
                if profile:
                    self.dispatch.conversations.reconcile(db)
                db.execute("UPDATE holds SET kind='cleanup',grant=NULL WHERE job=?", (job,))
            return {"accepted": True}
        return {}

    def complete_pair_work(self, db, row, receipts, *, trial):
        if len(receipts) == 2 and not paired_rdma(
                *(receipts[slot]["transport_evidence"] for slot in STUDIOS)):
            self.stop(db, row, "failed", "transport_mismatch")
            return
        if trial:
            passed = all(receipt.get("trial_measurement", {}).get("fixture_passed", True)
                         for receipt in receipts.values())
            self.stop(db, row, "succeeded" if passed else "failed",
                      "trial_completed" if passed else "fixture_failed")
            return
        # The final receipt and approved content become visible in the same
        # transaction. A reporter-first result cannot settle usage by itself.
        job = row["id"]
        db.execute("UPDATE jobs SET usage=? WHERE id=?", (encoded(receipts[row["reporter"]]["usage"]), job))
        self.jobs.transition(db, job, "succeeded", "completed")
        self.dispatch.conversations.reconcile(db)
        db.execute("UPDATE holds SET kind='cleanup',grant=NULL WHERE job=?", (job,))

    def cancel(self, owner, job):
        with self.enrollment.lock:
            self.sweep()
            with self.jobs.transaction() as db:
                row = self.jobs.owned(db, owner, job)
                if row["state"] in (*ACTIVE, "queued"):
                    self.stop(db, row, "cancelled", "operator_cancelled")
                return self.jobs.view(db, self.jobs.owned(db, owner, job))
