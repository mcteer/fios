"""Test single-host placement against promoted revisions and actual leases."""

from pathlib import Path
import tempfile
import unittest

from backend.conversations import ConversationStore
from backend.enrollment import Ledger, Rejected
from backend.job_ledger import JobLedger
from backend.model_catalog import Catalog, Profile
from backend.scheduler import Scheduler


class DispatchTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name) / "state"
        Ledger.initialize(root)
        self.clock = 1000
        enrollment = Ledger(root, wall=lambda: self.clock, clock=lambda: self.clock)
        JobLedger.initialize(root / "jobs.sqlite")
        self.jobs = JobLedger(root / "jobs.sqlite")
        self.jobs.migrate()
        self.catalog = Catalog(self.jobs, synthetic=True)
        self.store = ConversationStore(self.jobs, b"s" * 32)
        self.scheduler = Scheduler(self.jobs, enrollment, catalog=self.catalog)
        self.profile = Profile.parse(dict(alias="general-chat", host_class="m4-pro-mini",
                                          artifact="a"*64, engine="b"*64, template="c"*64,
                                          policy="d"*64, evaluation="e"*64, license="Apache-2.0",
                                          context=4096, output=128, settings={"temperature": 0}))
        self.session = self.scheduler.open_local_session()
        self.conversation = self.store.create("owner", "first")

    def trial(self, slot="fios-core"):
        evidence = dict(slot=slot, peak_bytes=1000, passed=True, synthetic=True)
        self.catalog.record(self.profile, evidence)
        with self.assertRaisesRegex(Rejected, "unqualified"):
            self.catalog.change("general-chat", None, self.profile.revision)
        self.catalog.change("general-chat", None, self.profile.revision, synthetic=True)

    def observe(self, sequence, available=1000):
        self.scheduler.local_capacity(self.session, dict(
            sequence=sequence, sampled_at=self.clock, available_bytes=available,
            resident_revision=None, pressure="normal", memory_bytes=10000))

    def poll(self):
        self.scheduler.sweep()
        with self.jobs.transaction() as db:
            return self.scheduler.poll(db, "fios-core", self.session)

    def submit(self):
        with self.jobs.transaction(write=False) as db:
            candidate = self.catalog.active(db, "general-chat")
        if candidate is None:
            raise Rejected("unqualified", 409)
        return self.store.submit("owner", self.conversation, self.jobs.context(), "once", None,
                                 "general-chat", "Explain indexing", False,
                                 profile=candidate["revision"], tokens=candidate["output"])["job"]

    def test_mini_requires_qualified_evidence_and_exact_headroom(self):
        self.observe(1, 999)
        with self.assertRaisesRegex(Rejected, "unqualified"):
            self.submit()
        self.trial()
        job = self.submit()
        self.assertEqual(self.poll()["action"], "wait")
        self.observe(2)
        assignment = self.poll()
        self.assertEqual(assignment["job"], job)
        self.assertEqual(self.jobs.get("owner", job)["slots"], ["fios-core"])
        grant = {name: assignment[name] for name in ("job", "grant", "epoch", "generation")}
        with self.jobs.transaction() as db:
            self.scheduler.assignment(db, "ready", "fios-core", self.session, grant)
        self.assertEqual(self.poll()["action"], "start")
        self.catalog.change("general-chat", self.profile.revision, None, synthetic=True)
        self.assertEqual(self.poll()["action"], "stop")
        self.assertEqual(self.jobs.get("owner", job)["slots"], ["fios-core"])
        with self.assertRaisesRegex(Rejected, "fenced"):
            with self.jobs.transaction() as db:
                self.scheduler.assignment(db, "renew", "fios-core", self.session, grant)

    def test_payload_only_after_start_and_result_requires_publication(self):
        import base64

        from backend.chat_dispatch import Dispatch
        from backend.job_protocol import local

        self.scheduler.dispatch = Dispatch(self.scheduler, self.store, lambda *_: True)
        self.trial()
        self.observe(1)
        job = self.submit()
        assignment = self.poll()
        grant = {name: assignment[name] for name in ("job", "grant", "epoch", "generation")}
        process = dict(version=1, node="fios-core", session=self.session, **grant)

        def payload(operation, **fields):
            return self.scheduler.dispatch.handle(operation, "fios-core", self.session,
                                                  {**grant, **fields}, authorize_peer=lambda: None)

        with self.assertRaisesRegex(Rejected, "fenced"):
            payload("prompt", cursor=0)
        local(self.scheduler, "ready", process)
        page = payload("prompt", cursor=0)
        self.assertIn(b"Explain indexing", base64.b64decode(page["data"]))
        self.assertIsNone(page["cursor"])
        with self.assertRaisesRegex(Rejected, "unpublished"):
            local(self.scheduler, "finish", {**process, "result": "ok"})
        answer = base64.b64encode(b"An index lets SQLite skip rows.").decode()
        with self.assertRaisesRegex(Rejected, "frame_gap"):
            payload("append", sequence=1, data=answer)
        payload("append", sequence=0, data=answer)
        payload("append", sequence=0, data=answer)
        payload("publish", frames=1)
        receipt = local(self.scheduler, "finish", {**process, "result": "ok"})
        self.assertTrue(receipt["accepted"])
        thread = self.store.read("owner", self.conversation, "d"*64)
        self.assertEqual(thread["turns"][0]["job"], job)
        self.assertEqual(thread["turns"][0]["answer"], "An index lets SQLite skip rows.")
        with self.assertRaisesRegex(Rejected, "fenced"):
            payload("append", sequence=0, data=answer)

    def test_browser_turn_without_an_attachment_expires_before_the_job_deadline(self):
        self.trial()
        turn = self.store.submit("owner", self.conversation, self.jobs.context(), "web", None,
                                 "general-chat", "Explain indexing", False,
                                 profile=self.profile.revision, tokens=128, browser=True)
        self.clock += 15
        self.scheduler.sweep()
        self.assertEqual(self.jobs.get("owner", turn["job"])["reason"], "stream_unattached")

    def test_answer_policy_receives_the_frozen_prior_exchange(self):
        import base64
        import json

        from backend.chat_dispatch import Dispatch
        from backend.job_protocol import local

        recorded = []

        def checker(purpose, text, _revision):
            if purpose != "answer":
                return True
            request = json.loads(text)["request"]
            recorded.append(request)
            return not (len(request) > 1 and "fixture inventory" in request[0]["content"])

        self.scheduler.dispatch = Dispatch(self.scheduler, self.store, checker)
        self.trial()
        self.observe(1)
        first = self.store.submit("owner", self.conversation, self.jobs.context(), "context-one", None,
                                  "general-chat", "Remember the fixture inventory", False,
                                  profile=self.profile.revision, tokens=128)

        def complete(answer):
            assignment = self.poll()
            grant = {field: assignment[field] for field in ("job", "grant", "epoch", "generation")}
            fields = dict(version=1, node="fios-core", session=self.session, **grant)
            local(self.scheduler, "ready", fields)

            def transfer(op, data):
                return self.scheduler.dispatch.handle(op, "fios-core", self.session,
                                                      {**grant, **data}, authorize_peer=lambda: None)
            transfer("prompt", {"cursor": 0})
            transfer("append", {"sequence": 0, "data": base64.b64encode(answer.encode()).decode()})
            return fields, transfer

        fields, first_transfer = complete("Fixture saved.")
        first_transfer("publish", {"frames": 1})
        local(self.scheduler, "finish", {**fields, "result": "ok"})
        challenge = self.poll()["challenge"]
        self.observe(2)
        local(self.scheduler, "cleaned", dict(version=1, node="fios-core", session=self.session,
                                              challenge=challenge, sequence=2, disposition="quiescent"))
        self.store.submit("owner", self.conversation, self.jobs.context(), "context-two", first["job"],
                          "general-chat", "Can you share that?", False,
                          profile=self.profile.revision, tokens=128)
        _, second_transfer = complete("Here it is.")
        with self.assertRaisesRegex(Rejected, "publication_withheld"):
            second_transfer("publish", {"frames": 1})
        self.assertEqual([item["role"] for item in recorded[-1]], ["user", "assistant", "user"])
        self.assertEqual(recorded[-1][-1]["content"], "Can you share that?")
