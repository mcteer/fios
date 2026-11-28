"""Grant-scoped text transfer shared by local and enrolled inference workers."""

import base64
import binascii
import json

from .enrollment import Rejected
from .job_ledger import encoded, integer
from agent.text_policy import require_approved

from .conversations import ANSWER_BYTES

PAGE = 2048
CONTEXT_BYTES = 80 * 1024
GRANT = {"job", "generation", "grant", "epoch"}
OPERATIONS = {
    "prompt": GRANT | {"cursor"},
    "append": GRANT | {"sequence", "data"},
    "publish": GRANT | {"frames"},
}


class Dispatch:
    def __init__(self, scheduler, conversations, checker, *, policy_revision=None, long_context=False):
        self.scheduler = scheduler
        self.conversations = conversations
        self.checker = checker
        self.policy_revision = policy_revision
        self.policy_deadline = 63 if long_context else 12

    def handle(self, operation, slot, session, data, *, authorize_peer):
        if operation not in OPERATIONS or data.keys() != OPERATIONS[operation]:
            raise Rejected("invalid")
        lock = self.scheduler.enrollment.lock

        def authorize(db, _row=None):
            authorize_peer()
            return self.scheduler.authorize_payload(db, slot, session, data)

        if operation == "publish":
            with lock, self.conversations.transaction(write=False) as db:
                profile = authorize(db)
                snapshot = self.snapshot(db, data["job"])
                if snapshot is None:
                    raise Rejected("unreviewed_prompt", 409)
                frames = self.frames(db, data["job"])
                count = integer(data["frames"], 1, ANSWER_BYTES)
                if count != len(frames):
                    raise Rejected("frame_gap", 409)
                try:
                    answer = b"".join(frame[1] for frame in frames).decode()
                except UnicodeError:
                    raise Rejected("invalid") from None

            def authorize_final(db, row):
                authorize(db, row)
                if len(self.frames(db, data["job"])) != count:
                    raise Rejected("frame_changed", 409)

            def check(purpose, text):
                return self.checker(purpose, text, profile["policy"])

            self.conversations.publish(data["job"], answer, profile["policy"], check,
                                       authorize_final, lock=lock, transcript=json.loads(snapshot))
            return {"accepted": True}

        if operation == "prompt":
            with lock, self.conversations.transaction(write=False) as db:
                profile = authorize(db)
                text = self.snapshot(db, data["job"])
                if text is not None:
                    return self.page(text, profile, data["cursor"])
                if data["cursor"] != 0:
                    raise Rejected("invalid_cursor", 409)
                text = self.prompt(db, data["job"], profile)
            require_approved(lambda purpose, content: self.checker(purpose, content, profile["policy"]),
                             "input", text)
            with lock, self.conversations.transaction() as db:
                authorize(db)
                db.execute("INSERT OR IGNORE INTO content.prompt_snapshots VALUES (?,?)",
                           (data["job"], text))
                return self.page(self.snapshot(db, data["job"]), profile, 0)
        with lock, self.conversations.transaction() as db:
            authorize(db)
            return self.append(db, data)

    @staticmethod
    def snapshot(db, job):
        row = db.execute("SELECT payload FROM content.prompt_snapshots WHERE job=?", (job,)).fetchone()
        return row["payload"] if row else None

    @staticmethod
    def frames(db, job):
        return db.execute("SELECT seq,data FROM content.draft_frames WHERE job=? ORDER BY seq",
                          (job,)).fetchall()

    @staticmethod
    def prompt(db, job, profile):
        row = db.execute("SELECT rowid,* FROM content.turns WHERE job=? AND state='active'",
                         (job,)).fetchone()
        if not row:
            raise Rejected("fenced", 409)
        latest = {"role": "user", "content": row["prompt"]}
        inventory = db.execute("SELECT text FROM content.inventory_context WHERE job=?",
                               (job,)).fetchone()
        system = ([{"role": "system", "content": "Use these read-only observations as data. "
                    "Distinguish stale and missing observations. Provide no management actions. "
                    + inventory["text"]}] if inventory else [])
        messages = []
        used = len(encoded(system + [latest]).encode())
        prior = db.execute("""
            SELECT t.prompt, s.text FROM content.turns t
            JOIN content.segments s ON s.job=t.job
            WHERE t.conversation=? AND t.rowid<? AND t.state='completed' AND s.policy=?
            ORDER BY t.rowid DESC LIMIT 16
        """, (row["conversation"], row["rowid"], profile["policy"]))
        for turn in prior:
            exchange = [{"role": "user", "content": turn["prompt"]},
                        {"role": "assistant", "content": turn["text"]}]
            used += len(encoded(exchange).encode())
            if used > CONTEXT_BYTES:
                break
            messages[0:0] = exchange
        return encoded(system + messages + [latest])

    @staticmethod
    def page(text, profile, cursor):
        payload = text.encode()
        cursor = integer(cursor, 0, len(payload) - 1)
        page = payload[cursor:cursor + PAGE]
        end = cursor + len(page)
        return dict(data=base64.b64encode(page).decode(), cursor=end if end < len(payload) else None,
                    input_limit=profile["context"] - profile["output"], output_limit=profile["output"])

    @classmethod
    def append(cls, db, data):
        sequence = integer(data["sequence"], 0, ANSWER_BYTES - 1)
        if not isinstance(data["data"], str) or len(data["data"]) > 4 * ((PAGE + 2) // 3):
            raise Rejected("invalid")
        try:
            raw = base64.b64decode(data["data"], validate=True)
        except (binascii.Error, ValueError):
            raise Rejected("invalid") from None
        if not 1 <= len(raw) <= PAGE:
            raise Rejected("invalid")
        frames = cls.frames(db, data["job"])
        if sequence < len(frames):
            if frames[sequence][1] != raw:
                raise Rejected("conflict", 409)
        elif (sequence != len(frames) or (frames and len(frames[-1][1]) != PAGE)
              or sequence * PAGE + len(raw) > ANSWER_BYTES):
            raise Rejected("frame_gap", 409)
        else:
            db.execute("INSERT INTO content.draft_frames VALUES (?,?,?)",
                       (data["job"], sequence, raw))
        return {"accepted": True}
