"""Owner-scoped content and quota reservations in the native job transaction."""

from contextlib import closing, contextmanager, nullcontext
import hashlib
import hmac
import json
import os
import secrets
import sqlite3

from agent.chat_titles import subject_title
from agent.text_policy import require_approved

from .enrollment import Rejected, private_path
from .job_ledger import KEY, encoded, identifier

PROMPT_BYTES = 16 * 1024
ANSWER_BYTES = 64 * 1024
TITLE_BYTES = 80 * 4
DEFAULT_QUOTA = 64 * 1024 * 1024
PLACEHOLDER = "Untitled conversation"
SCHEMA = """
CREATE TABLE IF NOT EXISTS content.conversations (
    id TEXT PRIMARY KEY, owner TEXT NOT NULL, request_key TEXT NOT NULL,
    title TEXT NOT NULL, title_policy TEXT, activity INTEGER NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0, UNIQUE(owner, request_key)
);
CREATE TABLE IF NOT EXISTS content.turns (
    job TEXT PRIMARY KEY, conversation TEXT NOT NULL REFERENCES conversations(id),
    owner TEXT NOT NULL, incarnation TEXT NOT NULL, request_key TEXT NOT NULL,
    digest TEXT NOT NULL, prompt TEXT NOT NULL,
    reserved INTEGER NOT NULL CHECK(reserved >= 0),
    state TEXT NOT NULL, UNIQUE(owner, incarnation, request_key)
);
CREATE UNIQUE INDEX IF NOT EXISTS content.one_active_turn ON turns(conversation) WHERE state='active';
CREATE TABLE IF NOT EXISTS content.inventory_context (
    job TEXT PRIMARY KEY REFERENCES turns(job), text TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS content.pending_titles (
    job TEXT PRIMARY KEY REFERENCES turns(job), text TEXT NOT NULL, policy TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS content.prompt_snapshots (
    job TEXT PRIMARY KEY REFERENCES turns(job), payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS content.draft_frames (
    job TEXT NOT NULL REFERENCES turns(job), seq INTEGER NOT NULL,
    data BLOB NOT NULL, PRIMARY KEY(job,seq)
);
CREATE TABLE IF NOT EXISTS content.segments (
    job TEXT NOT NULL REFERENCES turns(job), seq INTEGER NOT NULL,
    text TEXT NOT NULL, digest TEXT NOT NULL, policy TEXT NOT NULL,
    PRIMARY KEY(job,seq)
);
"""


def valid_key(value):
    if not isinstance(value, str) or KEY.fullmatch(value) is None:
        raise Rejected("invalid")
    return value


class ConversationStore:
    def __init__(self, jobs, digest_key, *, quota=DEFAULT_QUOTA, catalog=None):
        if len(digest_key) < 32:
            raise ValueError("A private 256-bit digest key is required")
        self.jobs = jobs
        self.path = jobs.path.with_name("conversations.sqlite")
        self.key = digest_key
        self.quota = quota
        self.catalog = catalog
        descriptor = os.open(self.path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        os.close(descriptor)
        private_path(self.path)
        with closing(self.jobs.connect()) as db:
            self.attach(db)
            db.executescript(SCHEMA)

    def attach(self, db):
        db.execute("ATTACH DATABASE ? AS content", (self.path.as_uri() + "?mode=rw",))
        db.execute("PRAGMA main.synchronous=FULL")
        db.execute("PRAGMA content.synchronous=FULL")
        db.execute("PRAGMA content.secure_delete=ON")
        if any(db.execute(f"PRAGMA {name}.journal_mode").fetchone()[0] != "delete"
               for name in ("main", "content")):
            raise ValueError("Chat requires rollback journals in both databases")

    @contextmanager
    def transaction(self, *, write=True):
        with closing(self.jobs.connect()) as db, db:
            self.attach(db)
            db.execute("BEGIN IMMEDIATE" if write else "BEGIN")
            if write:
                self.reconcile(db)
            yield db

    @staticmethod
    def owned(db, owner, conversation):
        row = db.execute("SELECT * FROM content.conversations WHERE id=? AND owner=? AND deleted=0",
                         (identifier(conversation), owner)).fetchone()
        if row is None:
            raise Rejected("unknown_conversation", 404)
        return row

    def reconcile(self, db):
        """Release inactive reservations before admitting more content."""
        incarnation = self.jobs.incarnation(db)
        db.execute("""
            UPDATE content.conversations AS c
            SET title=p.text, title_policy=p.policy, activity=?
            FROM content.pending_titles AS p
            JOIN content.turns AS t ON t.job=p.job
            JOIN main.jobs AS j ON j.id=p.job
            WHERE c.id=t.conversation AND c.deleted=0 AND t.state='active'
            AND t.incarnation=? AND j.state='succeeded'
        """, (int(self.jobs.wall()), incarnation))
        db.execute("""
            UPDATE content.turns AS t
            SET reserved=0, state=CASE
                WHEN t.incarnation=? AND j.state='succeeded' THEN 'completed'
                ELSE 'interrupted' END
            FROM (SELECT t2.job, jobs.state FROM content.turns AS t2
                  LEFT JOIN main.jobs AS jobs ON jobs.id=t2.job
                  WHERE t2.state='active') AS j
            WHERE t.job=j.job AND (t.incarnation!=? OR j.state IS NULL
                OR j.state NOT IN ('queued','preparing','running'))
        """, (incarnation, incarnation))
        for table in ("draft_frames", "pending_titles", "prompt_snapshots"):
            db.execute(f"DELETE FROM content.{table} WHERE job IN "
                       "(SELECT job FROM content.turns WHERE state!='active')")
        db.execute("DELETE FROM content.segments WHERE job IN "
                   "(SELECT job FROM content.turns WHERE state='interrupted')")

    def remaining(self, db, owner):
        titles = db.execute("""
            SELECT coalesce(sum(length(cast(title AS blob))),0) FROM content.conversations
            WHERE owner=? AND deleted=0
        """, (owner,)).fetchone()[0]
        turns = db.execute("""
            SELECT coalesce(sum(length(cast(prompt AS blob))+reserved),0)
            FROM content.turns WHERE owner=?
        """, (owner,)).fetchone()[0]
        answers = db.execute("""
            SELECT coalesce(sum(length(cast(s.text AS blob))),0)
            FROM content.segments s JOIN content.turns t ON t.job=s.job WHERE t.owner=?
        """, (owner,)).fetchone()[0]
        context = db.execute("""
            SELECT coalesce(sum(length(cast(i.text AS blob))),0)
            FROM content.inventory_context i JOIN content.turns t ON t.job=i.job WHERE t.owner=?
        """, (owner,)).fetchone()[0]
        return self.quota - titles - turns - answers - context

    def create(self, owner, request_key):
        valid_key(request_key)
        with self.transaction() as db:
            prior = db.execute("SELECT id,deleted FROM content.conversations "
                               "WHERE owner=? AND request_key=?", (owner, request_key)).fetchone()
            if prior:
                if prior["deleted"]:
                    raise Rejected("unknown_conversation", 404)
                return prior["id"]
            if (self.remaining(db, owner) < len(PLACEHOLDER)
                    or db.execute("SELECT count(*) FROM content.conversations WHERE owner=?",
                                  (owner,)).fetchone()[0] >= 10000):
                raise Rejected("quota", 429)
            conversation = secrets.token_hex(16)
            db.execute("INSERT INTO content.conversations(id,owner,request_key,title,activity) "
                       "VALUES (?,?,?,?,?)",
                       (conversation, owner, request_key, PLACEHOLDER, int(self.jobs.wall())))
            return conversation

    def submit(self, owner, conversation, incarnation, key, parent, alias, prompt, inventory,
               *, profile=None, tokens=512, deadline=120, inventory_context=None, browser=False):
        valid_key(key)
        if parent is not None:
            identifier(parent)
        if alias not in ("general-chat", "coding") or type(inventory) is not bool:
            raise Rejected("invalid")
        if not isinstance(prompt, str) or not prompt.strip():
            raise Rejected("invalid")
        try:
            size = len(prompt.encode("utf-8"))
        except UnicodeError as error:
            raise Rejected("invalid") from error
        if size > PROMPT_BYTES:
            raise Rejected("too_large", 413)
        request_parts = [conversation, parent, alias, prompt, inventory, tokens, deadline]
        if browser:
            request_parts.append("browser")
        request = encoded(request_parts)
        digest = hmac.new(self.key, request.encode(), hashlib.sha256).hexdigest()
        with self.transaction() as db:
            if identifier(incarnation) != self.jobs.incarnation(db):
                raise Rejected("ledger_changed", 409)
            row = self.owned(db, owner, conversation)
            prior = db.execute("SELECT job,conversation,digest FROM content.turns "
                               "WHERE owner=? AND incarnation=? AND request_key=?",
                               (owner, incarnation, key)).fetchone()
            if prior:
                if not hmac.compare_digest(prior["digest"], digest):
                    raise Rejected("conflict", 409)
                return {"job": prior["job"], "conversation": prior["conversation"]}
            last = db.execute("SELECT job,state FROM content.turns WHERE conversation=? "
                              "ORDER BY rowid DESC LIMIT 1", (conversation,)).fetchone()
            if (last["job"] if last else None) != parent or (last and last["state"] == "active"):
                raise Rejected("conversation_changed", 409)
            if inventory and (alias != "general-chat" or not isinstance(inventory_context, str)
                              or len(inventory_context.encode()) > 4096):
                raise Rejected("inventory_unavailable", 409)
            context_size = len(inventory_context.encode()) if inventory else 0
            reserve = ANSWER_BYTES + TITLE_BYTES - len(row["title"].encode())
            if self.remaining(db, owner) < size + reserve + context_size:
                raise Rejected("quota", 429)
            if self.catalog is not None:
                candidate = self.catalog.active(db, alias)
                if candidate is None:
                    raise Rejected("unqualified", 409)
                profile, tokens = candidate["revision"], candidate["output"]
            # Payload and digest stay in the attached private store. The ledger's
            # key is independent of a user-chosen key or a later ledger incarnation.
            intent = encoded(dict(profile=profile or alias, alias=alias, tokens=tokens,
                                  deadline=deadline, resource_class="inference", project=None,
                                  inventory=inventory))
            receipt = self.jobs.enqueue(db, owner, secrets.token_hex(16), intent, deadline)
            if browser:
                db.execute("INSERT INTO main.chat_attachments VALUES (?,?,NULL)",
                           (receipt["id"], self.jobs.wall() + 15))
            db.execute("INSERT INTO content.turns VALUES (?,?,?,?,?,?,?,?,'active')",
                       (receipt["id"], conversation, owner, incarnation, key, digest, prompt, reserve))
            if inventory:
                db.execute("INSERT INTO content.inventory_context VALUES (?,?)",
                           (receipt["id"], inventory_context))
            db.execute("UPDATE content.conversations SET activity=? WHERE id=?",
                       (int(self.jobs.wall()), conversation))
            return {"job": receipt["id"], "conversation": conversation}

    def delete(self, owner, conversation):
        with self.transaction() as db:
            self.owned(db, owner, conversation)
            # Fence publication before freeing quota. Keep executor holds for
            # independent cleanup and retain metadata for idempotency.
            active = db.execute("SELECT job FROM content.turns WHERE conversation=? AND state='active'",
                                (conversation,)).fetchall()
            for (job,) in active:
                state = db.execute("SELECT state FROM main.jobs WHERE id=?", (job,)).fetchone()
                if state and state[0] in ("queued", "preparing", "running"):
                    held = db.execute("SELECT 1 FROM main.holds WHERE job=?", (job,)).fetchone()
                    db.execute("UPDATE main.holds SET kind='cleanup',grant=NULL WHERE job=?", (job,))
                    self.jobs.transition(db, job, "stopping" if held else "cancelled",
                                         "conversation_deleted", outcome="cancelled" if held else None)
            for table in ("segments", "draft_frames", "inventory_context", "pending_titles", "prompt_snapshots"):
                db.execute(f"DELETE FROM content.{table} WHERE job IN "
                           "(SELECT job FROM content.turns WHERE conversation=?)", (conversation,))
            db.execute("UPDATE content.turns SET prompt='',reserved=0,state='deleted' "
                       "WHERE conversation=?", (conversation,))
            db.execute("UPDATE content.conversations SET title='',title_policy=NULL,deleted=1 WHERE id=?",
                       (conversation,))


    def publish(self, job, answer, policy, checker, authorize, *, lock=None, transcript=None):
        """Publish a complete answer after rechecking the caller's current grant."""
        if not isinstance(answer, str) or not isinstance(policy, str) or not policy:
            raise Rejected("invalid")
        try:
            raw = answer.encode()
        except UnicodeError as error:
            raise Rejected("invalid") from error
        if not raw or len(raw) > ANSWER_BYTES:
            raise Rejected("too_large", 413)
        with lock or nullcontext(), self.transaction(write=False) as db:
            row = self.publishable(db, job, authorize)
            prompt = row["prompt"]
            needs_title = row["title"] == PLACEHOLDER or row["title_policy"] != policy
        # A full-answer decision avoids publishing a prefix while its meaning
        # still depends on text the runtime has yet to produce.
        request = prompt if transcript is None else transcript
        require_approved(checker, "answer", encoded({"request": request, "answer": answer}))
        # Keep an approved subject across follow-ups within the same policy.
        title = subject_title(prompt, answer) if needs_title else None
        if title:
            try:
                require_approved(checker, "title", title)
            except Rejected:
                title = PLACEHOLDER
        checksum = hashlib.sha256(raw).hexdigest()
        with lock or nullcontext(), self.transaction() as db:
            row = self.publishable(db, job, authorize)
            prior = db.execute("SELECT digest,policy FROM content.segments "
                               "WHERE job=? AND seq=1", (job,)).fetchone()
            if prior:
                if tuple(prior) != (checksum, policy):
                    raise Rejected("conflict", 409)
                return
            title_growth = len(title.encode()) - len(row["title"].encode()) if title else 0
            remaining = row["reserved"] - len(raw)
            if remaining < max(0, title_growth):
                raise Rejected("quota", 429)
            db.execute("INSERT INTO content.segments VALUES (?,1,?,?,?)",
                       (job, answer, checksum, policy))
            db.execute("UPDATE content.turns SET reserved=? WHERE job=?", (remaining, job))
            if title:
                db.execute("INSERT INTO content.pending_titles VALUES (?,?,?)", (job, title, policy))

    def publishable(self, db, job, authorize):
        row = db.execute("""
            SELECT t.*, c.title, c.title_policy FROM content.turns AS t
            JOIN content.conversations AS c ON c.id=t.conversation
            JOIN main.jobs AS j ON j.id=t.job
            WHERE t.job=? AND c.deleted=0 AND t.state='active' AND j.state='running'
        """, (identifier(job),)).fetchone()
        if row is None or row["incarnation"] != self.jobs.incarnation(db):
            raise Rejected("fenced", 409)
        authorize(db, row)
        return row

    def read(self, owner, conversation, policy):
        with self.transaction() as db:
            row = self.owned(db, owner, conversation)
            title = row["title"] if row["title_policy"] == policy else PLACEHOLDER
            turns = db.execute("""
                SELECT t.job, t.prompt,
                       CASE WHEN t.incarnation=? THEN coalesce(j.state,t.state) ELSE t.state END AS state,
                       CASE WHEN t.state='completed' THEN coalesce(s.text,'') ELSE '' END AS answer,
                       j.intent, j.usage
                FROM (SELECT rowid, * FROM content.turns WHERE conversation=? AND owner=?
                      ORDER BY rowid DESC LIMIT 8) AS t
                LEFT JOIN content.segments AS s ON s.job=t.job AND s.policy=?
                LEFT JOIN main.jobs j ON j.id=t.job
                ORDER BY t.rowid
            """, (self.jobs.incarnation(db), conversation, owner, policy))
            items = []
            for row in turns:
                turn = dict(row)
                intent = json.loads(turn.pop("intent") or "{}")
                turn["revision"] = intent.get("profile")
                turn["usage"] = json.loads(turn["usage"]) if turn["usage"] else None
                items.append(turn)
            return {"id": conversation, "title": title, "turns": items}

    def history(self, owner, policy, before=None):
        with self.transaction(write=False) as db:
            cursor = (2**63 - 1, "f" * 32)
            if before is not None:
                row = self.owned(db, owner, before)
                cursor = (row["activity"], row["id"])
            rows = db.execute("""
                SELECT id,title,title_policy,activity FROM content.conversations
                WHERE owner=? AND deleted=0 AND (activity,id)<(?,?)
                ORDER BY activity DESC,id DESC LIMIT 51
            """, (owner, *cursor)).fetchall()
            result = [{"id": row["id"], "title": row["title"] if row["title_policy"] == policy
                       else PLACEHOLDER, "activity": row["activity"]} for row in rows[:50]]
            return {"conversations": result, "next": result[-1]["id"] if len(rows) > 50 else None}


    def touch_attachment(self, owner, conversation, job, ticket):
        """Claim or renew the one browser attachment for an owned turn."""
        with self.transaction() as db:
            self.owned(db, owner, conversation)
            turn = db.execute("SELECT 1 FROM content.turns WHERE job=? AND conversation=?",
                              (identifier(job), conversation)).fetchone()
            if not turn:
                raise Rejected("unknown_job", 404)
            row = self.jobs.owned(db, owner, job)
            if row["state"] not in ("queued", "preparing", "running"):
                return None
            attachment = db.execute("SELECT * FROM main.chat_attachments WHERE job=?", (job,)).fetchone()
            now = self.jobs.wall()
            if not attachment or now >= attachment["expires"]:
                raise Rejected("stream_expired", 409)
            if ticket != attachment["ticket"]:
                raise Rejected("already_attached", 409)
            token = ticket or secrets.token_hex(16)
            db.execute("UPDATE main.chat_attachments SET expires=?,ticket=? WHERE job=?",
                       (now + 15, token, job))
            return token
