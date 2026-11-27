"""End-to-end coding dispatch over a disposable two-peer mTLS enrollment."""

import base64
import json
from pathlib import Path
import ssl
import tempfile
import time
import unittest

from agent.inference_worker import InferenceWorker
from backend.chat_dispatch import Dispatch
from backend.conversations import ConversationStore
from backend.enrollment import Ledger, Rejected
from backend.heartbeat import Listener, worker_handler
from backend.job_ledger import JobLedger
from backend.machine_tls import context, fingerprint
from backend.model_catalog import Catalog, Profile
from backend.scheduler import Scheduler
from backend.worker import Reporter
from enrollment_fixtures import Signer
from fixtures.chat_coding import TASKS, evaluate


class StudioChatTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        signer = Signer(root, "chat-studio")
        server = signer.issue("fios-core", server=True)
        leaves = [signer.issue(machine) for machine in ("edge-a", "edge-b")]
        state = root / "state"
        Ledger.initialize(state)
        self.now = int(time.time())
        self.elapsed = time.monotonic()
        self.ledger = Ledger(state, wall=lambda: self.now, clock=lambda: self.elapsed)
        JobLedger.initialize(state / "jobs.sqlite")
        self.jobs = JobLedger(state / "jobs.sqlite")
        self.jobs.migrate()
        self.catalog = Catalog(self.jobs, synthetic=True)
        self.store = ConversationStore(self.jobs, b"c" * 32, catalog=self.catalog)
        self.scheduler = Scheduler(self.jobs, self.ledger, catalog=self.catalog)
        self.runtime_active = False
        self.policy_violation = False

        def policy(purpose, _text, _revision):
            if self.runtime_active and purpose in ("answer", "title"):
                self.policy_violation = True
            return True

        self.scheduler.dispatch = Dispatch(self.scheduler, self.store, policy)
        listener = Listener(("127.0.0.1", 0), worker_handler(
            self.ledger, context(signer.ca, *server, server=True), self.scheduler)).start()
        self.addCleanup(listener.close)
        self.clients = {}
        self.pins = {}
        for slot, machine, leaf in zip(("studio-a", "studio-b"), ("edge-a", "edge-b"), leaves,
                                       strict=True):
            pin = fingerprint(ssl.PEM_cert_to_DER_cert(leaf[0].read_text()))
            self.ledger.change("approve", slot, None, machine=machine, pin=pin)
            reporter = Reporter(slot, "127.0.0.1", listener.address[1], "fios-core",
                                context(signer.ca, *leaf))
            self.assertTrue(reporter.report(self.observe))
            self.clients[slot], self.pins[slot] = reporter, pin
        profile = Profile.parse(dict(alias="coding", host_class="m3-ultra-studio",
                                     artifact="a"*64, engine="b"*64, template="c"*64,
                                     policy="d"*64, evaluation="e"*64, license="Apache-2.0",
                                     context=4096, output=128, settings={"temperature": 0}))
        for slot in self.clients:
            self.catalog.record(profile, dict(slot=slot, peak_bytes=1000, passed=True, synthetic=True))
        self.catalog.change("coding", None, profile.revision, synthetic=True)
        self.cid = self.store.create("owner", "studio-test")
        self.job = self.store.submit("owner", self.cid, self.jobs.context(), "turn", None, "coding",
                                     TASKS[0].prompt, False)["job"]

    def observe(self, slot):
        return dict(version=1, node=slot, sampled_at=self.now, memory_bytes=10000,
                    logical_cpus=16, load_1m=0)

    def request(self, peer, namespace, action, data, *, session=None):
        client = self.clients[peer]
        status, raw = client.request(f"/v1/{namespace}/{action}", dict(
            data, version=1, node=peer, session=client.session if session is None else session))
        return status, json.loads(raw)

    def call(self, peer, namespace, action, data):
        status, result = self.request(peer, namespace, action, data)
        if status != 200:
            raise Rejected(result["reason"], status)
        return result

    def capacity(self, sequence):
        return dict(sequence=sequence, sampled_at=self.now, available_bytes=1000,
                    resident_revision=None, pressure="normal")

    def test_coding_runs_on_one_enrolled_studio_then_reaps_before_publication(self):
        test = self
        answer = "SELECT region, SUM(units) FROM orders GROUP BY region ORDER BY region"

        class Runtime:
            def generate(self, _revision, messages, _input_limit, _output_limit, _deadline):
                test.runtime_active = True
                test.assertEqual(messages[-1]["content"], TASKS[0].prompt)
                return answer, {"output": {"kind": "measured", "value": 18}}

            def stop(self):
                test.runtime_active = False

            def quiescent(self):
                return not test.runtime_active

        self.call("studio-b", "jobs", "capacity", self.capacity(1))
        sequence = iter(range(1, 9))
        worker = InferenceWorker(lambda op, data: self.call("studio-a", "jobs", op, data),
                                 lambda op, data: self.call("studio-a", "inference", op, data),
                                 lambda _revision: self.capacity(next(sequence)), Runtime())
        worker.step()
        state = self.jobs.get("owner", self.job)
        self.assertEqual(state["state"], "succeeded")
        self.assertEqual(state["slots"], ["studio-a"])
        self.assertFalse(self.policy_violation)
        self.assertEqual(self.call("studio-b", "jobs", "poll", {})["action"], "wait")
        thread = self.store.read("owner", self.cid, "d"*64)
        self.assertTrue(evaluate(TASKS[0], thread["turns"][0]["answer"]))
        worker.step()
        self.assertEqual(self.jobs.get("owner", self.job)["slots"], [])

    def test_wrong_peer_old_session_and_revoked_pin_cannot_fetch_prompt(self):
        self.call("studio-a", "jobs", "capacity", self.capacity(1))
        assignment = self.call("studio-a", "jobs", "poll", {})
        grant = {name: assignment[name] for name in ("job", "epoch", "grant", "generation")}
        self.call("studio-a", "jobs", "ready", grant)
        status, payload = self.request("studio-a", "inference", "prompt", {**grant, "cursor": 0})
        self.assertEqual(status, 200)
        self.assertIn(b"SQLite", base64.b64decode(payload["data"]))
        for peer, session in (("studio-b", None), ("studio-a", "0"*32)):
            status, result = self.request(peer, "inference", "prompt", {**grant, "cursor": 0},
                                          session=session)
            self.assertEqual((status, result), (409, {"reason": "fenced"}))
        self.ledger.change("revoke", "studio-a", self.pins["studio-a"])
        status, result = self.request("studio-a", "inference", "prompt", {**grant, "cursor": 0})
        self.assertEqual((status, result), (403, {"reason": "identity"}))
        self.scheduler.sweep()
        self.assertEqual(self.jobs.get("owner", self.job)["state"], "stopping")
        self.assertEqual(self.jobs.get("owner", self.job)["slots"], ["studio-a"])

    def test_policy_denial_has_a_distinct_outcome_and_does_not_call_runtime(self):
        self.scheduler.dispatch.checker = lambda *_: False
        sequence = iter(range(1, 9))

        class Runtime:
            def generate(self, *_):
                raise AssertionError("denied text reached the runtime")

            def stop(self):
                pass

            def quiescent(self):
                return True

        worker = InferenceWorker(lambda op, data: self.call("studio-a", "jobs", op, data),
                                 lambda op, data: self.call("studio-a", "inference", op, data),
                                 lambda _: self.capacity(next(sequence)), Runtime())
        worker.step()
        worker.step()
        state = self.jobs.get("owner", self.job)
        self.assertEqual(state["state"], "denied")
        self.assertEqual(state["reason"], "publication_withheld")
        self.assertEqual(self.store.read("owner", self.cid, "d"*64)["turns"][0]["answer"], "")

    def test_lost_studio_lease_hides_drafts_and_requires_cleanup_before_retry(self):
        slot = "studio-a"
        self.call(slot, "jobs", "capacity", self.capacity(1))
        offer = self.call(slot, "jobs", "poll", {})
        grant = {key: offer[key] for key in ("job", "epoch", "grant", "generation")}
        self.call(slot, "jobs", "ready", grant)
        self.assertEqual(self.call(slot, "jobs", "poll", {})["action"], "start")
        self.call(slot, "inference", "prompt", {**grant, "cursor": 0})
        draft = base64.b64encode(b"SELECT region FROM orders").decode()
        self.call(slot, "inference", "append", {**grant, "sequence": 0, "data": draft})

        # The worker stops reporting and renewing entirely before reconnecting.
        self.elapsed += 16
        self.now += 16
        self.scheduler.sweep()
        stopped = self.jobs.get("owner", self.job)
        self.assertEqual((stopped["state"], stopped["slots"]), ("stopping", [slot]))
        self.assertEqual(self.store.read("owner", self.cid, "d"*64)["turns"][0]["answer"], "")
        self.assertTrue(self.clients[slot].report(self.observe))
        self.call(slot, "jobs", "capacity", self.capacity(2))
        self.assertEqual(self.request(slot, "inference", "publish", {**grant, "frames": 1})[0], 409)
        cleanup = self.call(slot, "jobs", "poll", {})
        self.assertEqual(cleanup["action"], "stop")
        self.call(slot, "jobs", "capacity", self.capacity(3))
        self.call(slot, "jobs", "cleaned", {"challenge": cleanup["challenge"], "sequence": 3,
                                           "disposition": "quiescent"})
        expired = self.jobs.get("owner", self.job)
        self.assertEqual((expired["state"], expired["reason"], expired["slots"]),
                         ("expired", "lease_or_job_deadline", []))
        retry = self.store.submit("owner", self.cid, self.jobs.context(), "retry", self.job,
                                   "coding", TASKS[0].prompt, False)["job"]
        self.assertEqual(self.call(slot, "jobs", "poll", {})["job"], retry)
