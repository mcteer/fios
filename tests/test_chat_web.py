"""Verify browser, native capability and worker boundaries together on loopback."""

import base64
from contextlib import ExitStack
from http.client import HTTPConnection
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
from threading import Thread
import time
from uuid import uuid4
import unittest

from backend.chat_bridge import BridgeError, ChatBridge
from backend.chat_dispatch import Dispatch
from backend.conversations import ConversationStore
from backend.core import create_server
from backend.enroll import peer_uid
from backend.enrollment import Ledger, Rejected
from backend.heartbeat import Listener
from backend.job_ledger import JobLedger
from backend.model_catalog import Catalog, Profile
from backend.native_chat import browser_handler, local_handler, worker_call
from backend.scheduler import Scheduler


TRIAL_POLICY_REVISION = os.environ.get("FIOS_CHAT_TRIAL_POLICY_REVISION", "d"*64)
DEFAULT_TRIAL_PROFILE = dict(alias="general-chat", host_class="m4-pro-mini",
                     artifact="a"*64, engine="b"*64, template="c"*64,
                     policy=TRIAL_POLICY_REVISION, evaluation="e"*64, license="Apache-2.0",
                     context=1024, output=256, settings={"temperature": 0})
TRIAL_PROFILE = json.loads(os.environ["FIOS_CHAT_TRIAL_PROFILE"]) if os.environ.get(
    "FIOS_CHAT_TRIAL_PROFILE") else DEFAULT_TRIAL_PROFILE


class StreamDeadlineTests(unittest.TestCase):
    def test_live_turn_can_publish_after_the_former_stream_limit(self):
        from io import BytesIO
        from threading import Lock
        from types import SimpleNamespace
        from unittest.mock import Mock, patch

        from backend import core

        bridge = Mock()
        job = "a" * 32
        turn = dict(job=job, state="running", answer="", revision="b" * 64, usage=None)
        bridge.call.side_effect = (
            {"ticket": "ticket"}, {"turns": [turn]},
            {"ticket": None}, {"turns": [dict(turn, state="succeeded", answer="Finished")]},
        )
        handler = object.__new__(core.Handler)
        handler.server = SimpleNamespace(stream_lock=Lock(), stream_jobs=set(), chat=bridge)
        handler.wfile = BytesIO()
        handler.send_response = Mock()
        handler.send_header = Mock()
        handler.end_headers = Mock()
        clock = iter((0, 0, 126))
        with patch.object(core, "time", SimpleNamespace(monotonic=lambda: next(clock), sleep=lambda _: None)):
            handler.chat_stream("test-conversation", job, after=0)
        self.assertIn(b"Finished", handler.wfile.getvalue())
        self.assertEqual([call.args[0] for call in bridge.call.call_args_list],
                         ["stream", "conversation", "stream", "conversation"])
        self.assertEqual(handler.server.stream_jobs, set())


class ChatWebTests(unittest.TestCase):
    def setUp(self):
        resources = ExitStack()
        self.addCleanup(resources.close)
        # Keep the Unix socket path below platform sockaddr_un limits.
        root = Path(resources.enter_context(tempfile.TemporaryDirectory(dir="/tmp")))
        state = root / "state"
        Ledger.initialize(state)
        self.now = 1000
        enrollment = Ledger(state, wall=lambda: self.now, clock=lambda: self.now)
        JobLedger.initialize(state / "jobs.sqlite")
        jobs = JobLedger(state / "jobs.sqlite")
        jobs.migrate()
        catalog = Catalog(jobs, synthetic=True)
        store = ConversationStore(jobs, b"p" * 32, catalog=catalog)
        scheduler = Scheduler(jobs, enrollment, catalog=catalog)
        scheduler.dispatch = Dispatch(scheduler, store, lambda *_: True, policy_revision=TRIAL_POLICY_REVISION)
        self.catalog = catalog
        self.scheduler = scheduler
        profile = Profile.parse(TRIAL_PROFILE)
        catalog.record(profile, dict(slot="fios-core", peak_bytes=1000, passed=True, synthetic=True))
        catalog.change("general-chat", None, profile.revision, synthetic=True)

        def verify(conn):
            if peer_uid(conn) != os.geteuid():
                raise Rejected("identity", 403)

        self.worker_path = state / "worker.sock"
        local = Listener(str(self.worker_path), local_handler(scheduler, verify), family=socket.AF_UNIX)
        resources.callback(local.close)
        local.start()
        self.worker = lambda op, data: worker_call(self.worker_path, op, data, verify)
        key = b"s" * 32
        key_file = root / "bridge.key"
        key_file.write_bytes(key)
        inventory = {
            "fios-core": {"state": "reporting", "observation": {"sampled_at": 1000,
                                                               "memory_bytes": 25769803776}},
            "studio-a": {"state": "stale", "observation": {"sampled_at": 900,
                                                         "memory_bytes": 274877906944}},
            "studio-b": {"state": "awaiting", "observation": None},
        }
        native = Listener(("127.0.0.1", 0), browser_handler(scheduler, key, lambda: inventory))
        resources.callback(native.close)
        native.start()
        self.native = native.address[1]
        self.bridge = ChatBridge(self.native, key_file)
        self.root, self.key_file, self.resources = root, key_file, resources
        if os.environ.get("FIOS_CHAT_TEST_IMAGE"):
            self.run_container(root, key_file, resources)
        else:
            frontend = resources.enter_context(create_server(root, 0, chat=self.bridge))
            self.web_port = frontend.server_port
            web = Thread(target=frontend.serve_forever)
            web.start()
            resources.callback(web.join)
            resources.callback(frontend.shutdown)

    def run_container(self, root, key_file, resources):
        name = "fios-chat-test-" + uuid4().hex[:12]
        self.container = name
        key_file.chmod(0o444)
        with socket.socket() as candidate:
            candidate.bind(("127.0.0.1", 0))
            self.web_port = candidate.getsockname()[1]
        docker = ["docker", "--context", "orbstack"]
        resources.callback(subprocess.run, [*docker, "rm", "-f", name],
                           capture_output=True, timeout=15)
        subprocess.run([*docker, "run", "-d", "--name", name, "--network=host",
                        "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                        "--memory", "128m", "--pids-limit", "32",
                        "--mount", f"type=bind,src={key_file},dst=/chat-key,readonly",
                        os.environ["FIOS_CHAT_TEST_IMAGE"], "python", "-B", "-m", "backend.core",
                        "--directory", "/observations", "--port", str(self.web_port),
                        "--chat-port", str(self.native), "--chat-key", "/chat-key"], check=True,
                       timeout=20, capture_output=True)
        info = subprocess.run([*docker, "inspect", name], capture_output=True,
                              timeout=15, check=True, text=True)
        mounts = json.loads(info.stdout)[0]["Mounts"]
        self.assertEqual([(item["Destination"], item["RW"]) for item in mounts],
                         [("/chat-key", False)])
        end = time.monotonic() + 15
        while time.monotonic() < end:
            try:
                status, _, _ = self.request("GET", "/healthz")
                if status == 200:
                    return
            except OSError:
                pass
            time.sleep(0.1)
        raise RuntimeError("Isolated chat container failed to start")

    def request(self, method, route, data=None, headers=None):
        connection = HTTPConnection("127.0.0.1", self.web_port, timeout=3)
        try:
            body = json.dumps(data) if data is not None else None
            connection.request(method, route, body, headers or {})
            response = connection.getresponse()
            return response.status, response.headers, response.read()
        finally:
            connection.close()

    def test_native_worker_browser_history_and_denied_writes(self):
        status, headers, html = self.request("GET", "/chat")
        self.assertEqual(status, 200)
        self.assertIn(b"Private chat", html)
        self.assertIn("script-src 'self'", headers["Content-Security-Policy"])
        token = re.search(rb'name="chat-csrf" content="([0-9a-f]+)"', html)[1].decode()
        valid = {"Origin": f"http://127.0.0.1:{self.web_port}",
                 "Content-Type": "application/json", "Cookie": f"fios-chat={token}",
                 "X-Chat-CSRF": token}

        def post(action, data, request_headers=valid):
            status, _, body = self.request("POST", "/api/v1/chat/" + action, data, request_headers)
            return status, json.loads(body)

        self.assertEqual(post("create", {"key": "no-origin"}, {})[0], 403)
        self.assertEqual(post("create", {"key": "wrong-origin"},
                              {**valid, "Origin": "https://other.invalid"})[0], 403)
        self.assertEqual(post("create", {"key": "wrong-csrf"},
                              {**valid, "X-Chat-CSRF": "0"*64})[0], 403)
        wrong = self.bridge
        genuine = wrong.token
        try:
            wrong.token = "0"*64
            with self.assertRaisesRegex(BridgeError, "identity"):
                wrong.call("catalog", {})
        finally:
            wrong.token = genuine

        _, _, content = self.request("GET", "/api/v1/chat/catalog")
        catalog = json.loads(content)
        self.assertTrue(catalog["aliases"]["general-chat"]["available"])
        self.assertFalse(catalog["aliases"]["coding"]["available"])
        self.assertEqual(catalog["aliases"]["large-moe"],
                         dict(available=False, revision=None, reason="unqualified"))
        status, created = post("create", {"key": "one"})
        self.assertEqual(status, 200, created)
        cid = created["id"]
        status, turn = post("submit", dict(id=cid, key="turn", parent=None, alias="general-chat",
                                           incarnation=catalog["incarnation"], prompt="Explain Redwood",
                                           inventory=False))
        self.assertEqual(status, 200, turn)
        who = dict(node="fios-core", version=1, session=self.worker("session", {})["session"])
        self.worker("capacity", {**who, "sequence": 1, "sampled_at": self.now,
                                 "available_bytes": 1000, "resident_revision": None,
                                 "pressure": "normal", "memory_bytes": 10000})
        prepare = self.worker("poll", who)
        grant = {key: prepare[key] for key in ("generation", "job", "grant", "epoch")}
        self.assertEqual(turn["job"], grant["job"])
        self.worker("ready", {**who, **grant})
        self.assertEqual(self.worker("poll", who)["action"], "start")
        payload = {**grant, "session": who["session"]}
        messages = self.worker("prompt", {**payload, "cursor": 0})
        self.assertIn(b"Explain Redwood", base64.b64decode(messages["data"]))
        answer = base64.b64encode(b"Redwood is a tree. <script>alert(1)</script>").decode()
        self.worker("append", {**payload, "sequence": 0, "data": answer})
        self.worker("publish", {**payload, "frames": 1})
        self.worker("finish", {**who, **grant, "result": "ok"})

        _, _, content = self.request("GET", "/api/v1/chat/conversation/" + cid)
        state = json.loads(content)
        self.assertIn("Redwood", state["title"])
        self.assertEqual(state["turns"][0]["state"], "succeeded")
        self.assertIn("<script>", state["turns"][0]["answer"])
        status, stream_headers, stream = self.request("GET", f"/api/v1/chat/stream/{cid}/{turn['job']}")
        self.assertEqual(status, 200)
        self.assertIn("ndjson", stream_headers["Content-Type"])
        records = [json.loads(line) for line in stream.splitlines()]
        self.assertEqual([row["sequence"] for row in records], [1, 2])
        self.assertEqual(records[1]["text"], state["turns"][0]["answer"])
        self.assertEqual(records[1]["cursor"], 1)
        route = f"/api/v1/chat/stream/{cid}/{turn['job']}"
        status, _, resumed = self.request("GET", route + "?after=1")
        self.assertEqual(status, 200)
        self.assertEqual([json.loads(line)["type"] for line in resumed.splitlines()], ["state"])
        self.assertEqual(self.request("GET", route + "?after=65")[0], 400)
        self.assertNotIn(b"alert(1)", html)
        self.catalog.change("general-chat", Profile.parse(TRIAL_PROFILE).revision, None, synthetic=True)
        _, _, stored = self.request("GET", "/api/v1/chat/conversation/" + cid)
        self.assertEqual(json.loads(stored), state)
        self.assertEqual(post("delete", {"id": cid})[0], 200)
        self.assertEqual(self.request("GET", "/api/v1/chat/conversation/" + cid)[0], 404)
        self.assertEqual(self.request("GET", "/healthz")[0], 200)


    @unittest.skipUnless(os.environ.get("FIOS_CHAT_TEST_WEBKIT"), "macOS WebKit acceptance only")
    def test_chat_page_renders_in_webkit(self):
        result = subprocess.run([os.environ["FIOS_CHAT_TEST_WEBKIT"],
                                 f"http://127.0.0.1:{self.web_port}/chat"],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        print(result.stdout.strip(), flush=True)

    def test_worker_executes_and_reconciles_via_native_channel(self):
        from agent.inference_worker import InferenceWorker

        _, response_headers, page = self.request("GET", "/chat")
        token = re.search(rb'name="chat-csrf" content="([0-9a-f]+)"', page)[1].decode()
        headers = {"Origin": f"http://127.0.0.1:{self.web_port}",
                   "Content-Type": "application/json", "Cookie": response_headers["Set-Cookie"].split(";")[0],
                   "X-Chat-CSRF": token}
        catalog = json.loads(self.request("GET", "/api/v1/chat/catalog")[2])
        cid = json.loads(self.request("POST", "/api/v1/chat/create", {"key": "fake"}, headers)[2])["id"]
        submitted = self.request("POST", "/api/v1/chat/submit", dict(
            id=cid, incarnation=catalog["incarnation"], alias="general-chat", inventory=False,
            key="fixture", parent=None, prompt="Explain Redwood"), headers)
        self.assertEqual(submitted[0], 200)
        who = dict(node="fios-core", version=1, session=self.worker("session", {})["session"])
        sequences = iter(range(1, 10))
        stopped = []

        class DisposableRuntime:
            running = False

            def generate(self, revision, messages, input_limit, output_limit, deadline):
                self.running = True
                if messages[-1]["content"] != "Explain Redwood":
                    raise ValueError
                return "Redwood grows tall.", {"output": {"kind": "measured", "value": 4}}

            def stop(self):
                if self.running:
                    stopped.append(True)
                    self.running = False

            def quiescent(self):
                return not self.running

        worker = InferenceWorker(
            lambda op, data: self.worker(op, {**who, **data}),
            lambda op, data: self.worker(op, {**data, "session": who["session"]}),
            lambda revision: dict(sequence=next(sequences), sampled_at=self.now,
                                  available_bytes=1000, memory_bytes=10000,
                                  resident_revision=revision, pressure="normal"),
            DisposableRuntime())
        worker.step()
        worker.step()
        self.assertEqual(stopped, [True])
        thread = json.loads(self.request("GET", "/api/v1/chat/conversation/" + cid)[2])
        self.assertEqual(thread["turns"][-1]["answer"], "Redwood grows tall.")
        self.assertEqual(thread["turns"][-1]["usage"]["output"]["value"], 4)
        if os.environ.get("FIOS_CHAT_TEST_IMAGE"):
            replaced = self.container
            subprocess.run(["docker", "--context", "orbstack", "rm", "-f", replaced],
                           capture_output=True, check=True, timeout=15)
            self.run_container(self.root, self.key_file, self.resources)
            self.assertNotEqual(self.container, replaced)
            reopened = self.request("GET", "/api/v1/chat/conversation/" + cid)
            self.assertEqual(reopened[0], 200)
            self.assertEqual(json.loads(reopened[2]), thread)

    def test_duplicate_stream_leaves_first_attached_and_disconnect_cancels_turn(self):
        import struct

        _, response_headers, page = self.request("GET", "/chat")
        token = re.search(rb'name="chat-csrf" content="([0-9a-f]+)"', page)[1].decode()
        headers = {"Origin": f"http://127.0.0.1:{self.web_port}",
                   "Content-Type": "application/json", "Cookie": response_headers["Set-Cookie"].split(";")[0],
                   "X-Chat-CSRF": token}
        catalog = json.loads(self.request("GET", "/api/v1/chat/catalog")[2])
        cid = json.loads(self.request("POST", "/api/v1/chat/create", {"key": "disconnect"}, headers)[2])["id"]
        status, _, data = self.request("POST", "/api/v1/chat/submit", dict(
            id=cid, incarnation=catalog["incarnation"], alias="general-chat", inventory=False,
            key="turn", parent=None, prompt="Wait for a worker"), headers)
        self.assertEqual(status, 200)
        job = json.loads(data)["job"]
        route = f"/api/v1/chat/stream/{cid}/{job}"
        with socket.create_connection(("127.0.0.1", self.web_port), timeout=2) as stream:
            stream.sendall((f"GET {route} HTTP/1.1\r\nHost: 127.0.0.1:{self.web_port}\r\n\r\n").encode())
            with stream.makefile("rb") as lines:
                self.assertIn(b"200", lines.readline())
                while lines.readline() != b"\r\n":
                    pass
                self.assertEqual(json.loads(lines.readline())["state"], "queued")
                self.assertEqual(self.request("GET", route)[0], 409)
                self.assertEqual(self.request("GET", "/healthz")[0], 200)
                stream.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            thread = json.loads(self.request("GET", f"/api/v1/chat/conversation/{cid}")[2])
            if thread["turns"][0]["state"] == "cancelled":
                self.assertEqual(thread["turns"][0]["answer"], "")
                return
            time.sleep(0.05)
        self.fail("Closing the primary stream did not cancel the queued turn")


    @unittest.skipUnless(os.environ.get("FIOS_CHAT_NATIVE_TRIAL_CONFIG"), "native MLX trial only")
    def test_actual_mlx_process_serves_disposable_browser_turn(self):
        from agent.inference_worker import InferenceWorker
        from agent.native_runtime import NativeRuntime

        path = Path(os.environ["FIOS_CHAT_NATIVE_TRIAL_CONFIG"])
        runtime = NativeRuntime(path, path.parent, purpose="inference")
        self.addCleanup(runtime.stop)
        if os.environ.get("FIOS_CHAT_NATIVE_POLICY_CONFIG"):
            self.start_real_policy_worker()
        self.assertEqual(runtime.revision, Profile.parse(TRIAL_PROFILE).revision)
        _, response_headers, page = self.request("GET", "/chat")
        csrf = re.search(rb'name="chat-csrf" content="([0-9a-f]+)"', page)[1].decode()
        headers = {"Origin": f"http://127.0.0.1:{self.web_port}",
                   "Content-Type": "application/json",
                   "Cookie": response_headers["Set-Cookie"].split(";")[0], "X-Chat-CSRF": csrf}
        catalog = json.loads(self.request("GET", "/api/v1/chat/catalog")[2])
        cid = json.loads(self.request("POST", "/api/v1/chat/create", {"key": "native"}, headers)[2])["id"]
        status, _, receipt = self.request("POST", "/api/v1/chat/submit", dict(
            id=cid, incarnation=catalog["incarnation"], alias="general-chat", inventory=False,
            key="native-turn", parent=None,
            prompt="Reply with exactly the word Redwood."), headers)
        self.assertEqual(status, 200)
        job = json.loads(receipt)["job"]
        who = dict(node="fios-core", version=1, session=self.worker("session", {})["session"])
        sequences = iter(range(1, 20))
        worker = InferenceWorker(
            lambda op, data: self.worker(op, {**who, **data}),
            lambda op, data: self.worker(op, {**data, "session": who["session"]}),
            lambda revision: dict(sequence=next(sequences), sampled_at=self.now,
                                  available_bytes=1000, memory_bytes=10000,
                                  resident_revision=revision, pressure="normal"), runtime)
        worker.step()
        self.assertTrue(runtime.quiescent())
        worker.step()
        status, _, result = self.request("GET", f"/api/v1/chat/stream/{cid}/{job}")
        self.assertEqual(status, 200)
        events = [json.loads(line) for line in result.splitlines()]
        self.assertEqual(events[0]["state"], "succeeded")
        visible = "".join(event["text"] for event in events if event["type"] == "text")
        self.assertEqual(visible.strip().casefold().rstrip("."), "redwood")
        status, _, receipt = self.request("POST", "/api/v1/chat/submit", dict(
            id=cid, incarnation=catalog["incarnation"], alias="general-chat", inventory=False,
            key="native-followup", parent=job,
            prompt="What word did you give in your last answer? Reply with just that word."), headers)
        self.assertEqual(status, 200)
        followup = json.loads(receipt)["job"]
        worker.step()
        self.assertTrue(runtime.quiescent())
        worker.step()
        status, _, result = self.request("GET", f"/api/v1/chat/stream/{cid}/{followup}")
        self.assertEqual(status, 200)
        events = [json.loads(line) for line in result.splitlines()]
        self.assertEqual(events[0]["state"], "succeeded")
        visible = "".join(event["text"] for event in events if event["type"] == "text")
        self.assertEqual(visible.strip().casefold().rstrip("."), "redwood")
        stored = json.loads(self.request("GET", f"/api/v1/chat/conversation/{cid}")[2])
        self.assertIn("Redwood", stored["title"])
        self.assertEqual([turn["job"] for turn in stored["turns"]], [job, followup])

        status, _, receipt = self.request("POST", "/api/v1/chat/create", {"key": "inventory"}, headers)
        self.assertEqual(status, 200)
        inventory_conversation = json.loads(receipt)["id"]
        status, _, receipt = self.request("POST", "/api/v1/chat/submit", dict(
            id=inventory_conversation, incarnation=catalog["incarnation"], alias="general-chat",
            inventory=True, key="native-inventory", parent=None,
            prompt=("Which host is reporting, which is stale, and which has no observation? "
                    "Reply in one short sentence.")), headers)
        self.assertEqual(status, 200)
        worker.step()
        worker.step()
        inventory_job = json.loads(receipt)["job"]
        status, _, result = self.request("GET", f"/api/v1/chat/stream/{inventory_conversation}/{inventory_job}")
        self.assertEqual(status, 200)
        events = [json.loads(line) for line in result.splitlines()]
        self.assertEqual(events[0]["state"], "succeeded")
        visible = "".join(event["text"] for event in events if event["type"] == "text").casefold()
        self.assertRegex(visible, r"fios-core[^\n]*reporting")
        self.assertRegex(visible, r"studio-a[^\n]*stale")
        self.assertRegex(visible, r"studio-b[^\n]*(missing|awaiting|no observation)")
        self.assertEqual(self.request("GET", "/healthz")[0], 200)


    def start_real_policy_worker(self):
        from agent.native_runtime import NativeRuntime
        from agent.text_policy import LoopbackPolicy, require_approved
        import sys

        path = Path(os.environ["FIOS_CHAT_NATIVE_POLICY_CONFIG"])
        config = NativeRuntime(path, path.parent, purpose="policy")
        self.assertEqual(config.revision, TRIAL_POLICY_REVISION)
        with socket.socket() as candidate:
            candidate.bind(("127.0.0.1", 0))
            port = candidate.getsockname()[1]
        command = [sys.executable, "-B", "-m", "agent.policy_worker", "--config", str(path),
                   "--state", str(path.parent), "--port", str(port)]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def stop():
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=6)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)

        self.addCleanup(stop)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            self.assertIsNone(process.poll())
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            self.fail("Native policy worker did not bind its loopback port")
        check = LoopbackPolicy(port)
        with self.assertRaisesRegex(Rejected, "publication_withheld"):
            require_approved(lambda purpose, text: check(purpose, text, config.revision),
                             "input", "The submitted request asks for a sexual depiction of a child.")
        self.scheduler.dispatch.checker = check
