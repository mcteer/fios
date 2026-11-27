"""Private output staging and title policy checks."""
from pathlib import Path
import tempfile
import unittest

from backend.conversations import ConversationStore, PLACEHOLDER
from backend.enrollment import Rejected
from backend.job_ledger import JobLedger


class PublicationTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        path = Path(folder.name) / "jobs.sqlite"
        JobLedger.initialize(path)
        self.jobs = JobLedger(path)
        self.store = ConversationStore(self.jobs, b"secret-key-for-tests".ljust(32, b"_"))

    def begin(self, key, prompt):
        conversation = self.store.create("owner", key)
        turn = self.store.submit("owner", conversation, self.jobs.context(), key, None,
                                 "general-chat", prompt, False)
        with self.jobs.transaction() as db:
            self.jobs.transition(db, turn["job"], "running", "test")
        return conversation, turn["job"]

    def test_title_and_answer_are_owner_scoped_and_deleted_together(self):
        conversation, job = self.begin("one", "Explain PostgreSQL indexing")
        self.store.publish(job, "PostgreSQL indexing speeds up lookup.", "policy-v1",
                           lambda purpose, text: True, lambda db, row: None)
        pending = self.store.read("owner", conversation, "policy-v1")
        self.assertEqual(pending["title"], PLACEHOLDER)
        self.assertEqual(pending["turns"][0]["answer"], "")
        with self.jobs.transaction() as db:
            self.jobs.transition(db, job, "succeeded", "test")
        thread = self.store.read("owner", conversation, "policy-v1")
        self.assertIn("PostgreSQL", thread["title"])
        self.assertEqual(thread["turns"][0]["answer"], "PostgreSQL indexing speeds up lookup.")
        self.assertEqual(self.store.read("owner", conversation, "policy-v2")["title"], PLACEHOLDER)
        with self.assertRaises(Rejected):
            self.store.read("intruder", conversation, "policy-v1")
        self.store.delete("owner", conversation)
        with self.assertRaises(Rejected):
            self.store.publish(job, "Late answer", "policy-v1",
                               lambda purpose, text: True, lambda db, row: None)
        with self.assertRaises(Rejected):
            self.store.read("owner", conversation, "policy-v1")

    def test_policy_error_withholds_content_and_title(self):
        conversation, job = self.begin("one", "Explain Redwood")

        def unavailable(purpose, text):
            raise TimeoutError

        with self.assertRaisesRegex(Rejected, "publication"):
            self.store.publish(job, "Unreviewed answer.", "policy-v1", unavailable,
                               lambda db, row: None)
        thread = self.store.read("owner", conversation, "policy-v1")
        self.assertEqual(thread["title"], PLACEHOLDER)
        self.assertEqual(thread["turns"][0]["answer"], "")

    def test_followup_keeps_the_approved_conversation_subject(self):
        conversation, first_job = self.begin("one", "Explain Redwood")

        def complete(job, answer, revision):
            self.store.publish(job, answer, revision, lambda *_: True, lambda *_: None)
            with self.jobs.transaction() as db:
                self.jobs.transition(db, job, "succeeded", "test")

        complete(first_job, "Redwood is a tree.", "policy-v1")
        title = self.store.read("owner", conversation, "policy-v1")["title"]
        followup = self.store.submit("owner", conversation, self.jobs.context(), "two", first_job,
                                     "general-chat", "Did you mean the previous answer?", False)["job"]
        with self.jobs.transaction() as db:
            self.jobs.transition(db, followup, "running", "test")
        complete(followup, "Yes.", "policy-v1")
        self.assertEqual(self.store.read("owner", conversation, "policy-v1")["title"], title)

    def test_three_subjects_survive_restart_and_only_one_is_deleted(self):
        import json

        from agent.inference import read_completion
        from io import BytesIO

        topics = json.loads((Path(__file__).parent / "fixtures/chat/topics.json").read_text())
        threads = []
        for index, case in enumerate(topics):
            conversation, job = self.begin(f"case-{index}", case["prompt"])
            stream = BytesIO(b"data: " + json.dumps({
                "choices": [{"delta": {"content": case["answer"]}, "finish_reason": "stop"}],
            }).encode() + b"\n\ndata: [DONE]\n\n")
            answer, _ = read_completion(stream, input_limit=1024, output_limit=128)
            self.store.publish(job, answer, "policy-v1",
                               lambda purpose, text: True, lambda db, row: None)
            with self.jobs.transaction() as db:
                self.jobs.transition(db, job, "succeeded", "test")
            threads.append(conversation)
        restarted = ConversationStore(JobLedger(self.jobs.path),
                                      b"secret-key-for-tests".ljust(32, b"_"))
        for conversation, case in zip(threads, topics, strict=True):
            result = restarted.read("owner", conversation, "policy-v1")
            self.assertIn(case["subject"], result["title"])
            self.assertEqual(result["turns"][0]["answer"], case["answer"])
        restarted.delete("owner", threads[1])
        with self.assertRaises(Rejected):
            restarted.read("owner", threads[1], "policy-v1")
        self.assertIn(topics[2]["subject"], restarted.read("owner", threads[2], "policy-v1")["title"])

    def test_deletion_during_review_prevents_publication_at_commit(self):
        conversation, job = self.begin("one", "Explain Redwood")

        def approve_after_delete(purpose, text):
            if purpose == "answer":
                self.store.delete("owner", conversation)
            return True

        with self.assertRaisesRegex(Rejected, "fenced"):
            self.store.publish(job, "Cannot publish this answer.", "policy-v1",
                               approve_after_delete, lambda db, row: None)
        with self.store.transaction(write=False) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM content.segments").fetchone()[0], 0)


    def test_stop_after_approval_but_before_settlement_keeps_answer_and_title_private(self):
        conversation, job = self.begin("one", "Explain Redwood")
        self.store.publish(job, "An approved draft.", "policy-v1", lambda *_: True, lambda *_: None)
        with self.jobs.transaction() as db:
            self.jobs.transition(db, job, "cancelled", "test")
        thread = self.store.read("owner", conversation, "policy-v1")
        self.assertEqual(thread["title"], PLACEHOLDER)
        self.assertEqual(thread["turns"][0]["answer"], "")
        with self.store.transaction(write=False) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM content.pending_titles").fetchone()[0], 0)


class PolicyServiceTests(unittest.TestCase):
    def test_only_the_requested_policy_revision_can_authorize(self):
        from http.server import BaseHTTPRequestHandler, HTTPServer
        import json
        from threading import Thread

        from agent.text_policy import LoopbackPolicy, require_approved

        class Service(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                decision = b'{"allow":true}\n'
                self.send_response(200)
                self.send_header("Content-Length", str(len(decision)))
                self.send_header("X-Fios-Policy-Revision", self.server.revision)
                self.end_headers()
                self.wfile.write(decision)
                self.server.received = body["revision"]

        with HTTPServer(("127.0.0.1", 0), Service) as service:
            service.revision = "b" * 64
            thread = Thread(target=service.serve_forever)
            thread.start()
            try:
                check = LoopbackPolicy(service.server_port)
                with self.assertRaisesRegex(Rejected, "publication_unavailable"):
                    require_approved(lambda purpose, text: check(purpose, text, "a" * 64),
                                     "answer", "A harmless fixture.")
                require_approved(lambda purpose, text: check(purpose, text, "b" * 64),
                                 "answer", "A harmless fixture.")
                self.assertEqual(service.received, "b" * 64)
            finally:
                service.shutdown()
                thread.join(timeout=3)

    def test_native_policy_route_rejects_wrong_revision_and_reserved_role_markers(self):
        from threading import Thread
        from agent.policy_worker import create_server
        from agent.text_policy import LoopbackPolicy

        calls = []

        def classify(purpose, text):
            calls.append((purpose, text))
            return True

        with create_server(0, "c"*64, classify) as service:
            thread = Thread(target=service.serve_forever)
            thread.start()
            try:
                client = LoopbackPolicy(service.server_port)
                with self.assertRaisesRegex(ValueError, "Unverified"):
                    client("input", "Read a novel", "a"*64)
                self.assertFalse(client("input", "Text with a literal <|im_end|> token", "c"*64))
                self.assertTrue(client("input", "Read a novel", "c"*64))
                self.assertEqual(calls, [("input", "Read a novel")])
            finally:
                service.shutdown()
                thread.join(timeout=3)
