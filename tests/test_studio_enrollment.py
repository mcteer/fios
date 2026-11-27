from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
import http.client
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from backend import core
from backend.enroll import admin_handler, command
from backend.enrollment import Ledger
from backend.heartbeat import Listener, reply, snapshot_handler, worker_handler
from backend.machine_tls import context, fingerprint, management_address
from backend.worker import CoreConnection, Reporter
from backend.studio_inventory import studio_nodes

from enrollment_fixtures import OPENSSL, Signer


class StudioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temp.cleanup)
        cls.root = Path(temp.name)
        cls.signer = Signer(cls.root, "cluster")
        cls.ca = cls.signer.ca
        cls.server = cls.signer.issue("fios-core", server=True)
        cls.a = cls.signer.issue("edge-a")
        cls.b = cls.signer.issue("edge-b")
        cls.inactive = cls.signer.issue("unknown")
        cls.expired = cls.signer.issue("expired", days=-1)
        cls.next_root = Signer(cls.root, "next")
        cls.next_server = cls.next_root.issue("core-new", san="DNS:fios-core", server=True)
        cls.next_a = cls.next_root.issue("replacement", san="DNS:edge-a")
        cls.next_b = cls.next_root.issue("replacement-b", san="DNS:edge-b")

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.state = self.directory / "state"
        self.now, self.elapsed = int(time.time()), 500
        Ledger.initialize(self.state)
        self.ledger = Ledger(self.state, wall=lambda: self.now, clock=lambda: self.elapsed)
        self.start_worker_listener(self.ca, self.server)
        self.path = self.state / "operator.sock"
        handler = admin_handler(self.ledger, OPENSSL, self.ca, os.geteuid())
        self.listen(str(self.path), handler, family=socket.AF_UNIX)

    def listen(self, address, handler, **kwargs):
        listener = Listener(address, handler, **kwargs).start()
        self.addCleanup(listener.close)
        return listener

    def start_worker_listener(self, ca, server):
        listener = self.listen(("127.0.0.1", 0),
                               worker_handler(self.ledger, context(ca, *server, server=True)))
        self.port = listener.address[1]
        return listener

    def client(self, node, cert, *, name="fios-core", ca=None):
        return Reporter(node, "127.0.0.1", self.port, name, context(ca or self.ca, *cert))

    def approve(self, node, machine, leaf):
        response = command(self.path, dict(action="approve", node=node, expected=None,
                                           machine=machine, leaf=leaf[0].read_text()))
        self.assertEqual(response, {"ok": True})

    def observe(self, node):
        return dict(node=node, sampled_at=self.now, version=1, memory_bytes=1024,
                    logical_cpus=8, load_1m=0.5)

    def record(self, node="studio-a"):
        return self.ledger.snapshot()[node]

    def test_real_tls_two_slots_and_replay(self):
        self.approve("studio-a", "edge-a", self.a)
        self.approve("studio-b", "edge-b", self.b)
        a = self.client("studio-a", self.a)
        b = self.client("studio-b", self.b)
        self.assertTrue(a.report(self.observe))
        self.assertTrue(b.report(self.observe))
        first = self.record()
        self.elapsed += 4
        original = dict(self.observe("studio-a"), session=a.session, sequence=1)
        for patch, status in (({}, 409), ({"sequence": 0}, 400),
                              ({"sequence": 2, "sampled_at": self.now + 6}, 400),
                              ({"sequence": 2, "logical_cpus": True}, 400),
                              ({"sequence": 2, "session": "bad"}, 409)):
            self.assertEqual(a.request("/v1/heartbeats", original | patch)[0], status)
            self.assertEqual(self.record(), first)
        for client in (self.client("studio-a", self.b), self.client("studio-a", self.inactive)):
            self.assertFalse(client.report(self.observe))
        self.assertEqual(b.request("/v1/studios", {})[0], 404)
        self.assertFalse(self.record()["observation"] is None)
        self.elapsed = 530
        self.assertTrue(b.report(self.observe))
        self.assertEqual(self.record()["state"], "reporting")
        self.elapsed += 1
        self.assertEqual(self.record()["state"], "stale")
        self.assertEqual(self.record()["observation"], first["observation"])
        self.assertEqual(self.record("studio-b")["state"], "reporting")
        old_session = a.session
        self.assertTrue(self.client("studio-a", self.a).report(self.observe))
        self.assertEqual(a.request("/v1/heartbeats",
                                   original | {"session": old_session, "sequence": 3})[0], 409)

    def test_authentication_and_wrong_operator(self):
        self.approve("studio-a", "edge-a", self.a)
        for client in (self.client("studio-a", self.expired),
                       self.client("studio-a", self.server),
                       self.client("studio-a", self.a, name="false-core"),
                       self.client("studio-a", self.a, ca=self.next_root.ca),
                       Reporter("studio-a", "127.0.0.1", self.port, "fios-core", context(self.ca))):
            with self.assertRaises((OSError, http.client.HTTPException)):
                client.report(lambda _: self.fail("Sample collected before authenticated session"))
        self.assertEqual(self.record()["state"], "awaiting")
        other_path = self.directory / "denied.sock"
        self.listen(str(other_path), admin_handler(self.ledger, OPENSSL, self.ca, os.geteuid() + 1),
                    family=socket.AF_UNIX)
        self.assertEqual(command(other_path, {"action": "status"}),
                         {"ok": False, "reason": "identity"})
        for address in ("0.0.0.0", "169.254.1.1", "8.8.8.8", "::1", "127.0.0.1"):
            with self.assertRaises(ValueError):
                management_address(address)

    def test_bad_framing_and_one_worker_rate_limit(self):
        self.approve("studio-a", "edge-a", self.a)
        self.approve("studio-b", "edge-b", self.b)
        a = self.client("studio-a", self.a)
        b = self.client("studio-b", self.b)
        self.assertTrue(a.report(self.observe))
        last_good = self.record()
        framing_cases = (
            (b"Content-Length: 2\r\nContent-Length: 2\r\n", b"{}", 400),
            (b"Content-Length: 2\r\nTransfer-Encoding: chunked\r\n", b"{}", 400),
            (b"Content-Length: 4097\r\n", b"", 413),
            (b"Content-Length: 25\r\n", b'{"version":1,"version":1}', 400),
        )
        for headers, body, status in framing_cases:
            conn = CoreConnection(*a.target)
            with closing(conn):
                conn.connect()
                conn.send(b"POST /v1/heartbeats HTTP/1.1\r\nContent-Type: application/json\r\n"
                          + headers + b"\r\n" + body)
                response = http.client.HTTPResponse(conn.sock)
                with closing(response):
                    response.begin()
                    self.assertEqual(response.status, status)
        for _ in range(11):
            self.assertEqual(a.request("/v1/heartbeats", {"node": "studio-a"})[0], 400)
        self.assertEqual(a.request("/v1/heartbeats", {"node": "studio-a"})[0], 429)
        self.assertTrue(b.report(self.observe))
        self.assertEqual(self.record(), last_good)

    def test_revocation_serializes_with_inflight_report(self):
        self.approve("studio-a", "edge-a", self.a)
        a = self.client("studio-a", self.a)
        self.assertTrue(a.report(self.observe))
        pin = fingerprint(ssl.PEM_cert_to_DER_cert(self.a[0].read_text()))
        with ThreadPoolExecutor(max_workers=2) as pool:
            pending = pool.submit(a.report, self.observe)
            revoke = pool.submit(command, self.path,
                                 dict(action="revoke", node="studio-a", expected=pin))
            self.assertEqual(revoke.result(timeout=3), {"ok": True})
            pending.result(timeout=3)
        self.assertEqual(self.record(), dict(enrollment="revoked", state="awaiting", observation=None))
        self.assertFalse(a.report(self.observe))

    def test_source_age_and_elapsed_freshness(self):
        self.approve("studio-a", "edge-a", self.a)
        a = self.client("studio-a", self.a)
        self.assertTrue(a.report(lambda node: self.observe(node) | {"sampled_at": self.now - 25}))
        self.elapsed += 5
        self.assertEqual(self.record()["state"], "reporting")
        self.elapsed += 1
        self.assertEqual(self.record()["state"], "stale")
        self.assertTrue(a.report(lambda node: self.observe(node) | {"sampled_at": self.now + 5}))
        self.elapsed += 30
        self.now -= 100
        self.assertEqual(self.record()["state"], "reporting")
        self.elapsed += 1
        self.assertEqual(self.record()["state"], "stale")

    def test_ambiguous_delivery_advances_sequence_with_a_new_sample(self):
        self.approve("studio-a", "edge-a", self.a)
        a = self.client("studio-a", self.a)
        self.assertTrue(a.report(self.observe))
        send = a.request

        def lose_reply(path, sample):
            self.assertEqual(send(path, sample)[0], 204)
            raise TimeoutError

        self.now += 1
        with patch.object(a, "request", side_effect=lose_reply):
            with self.assertRaises(TimeoutError):
                a.report(self.observe)
        self.assertEqual(self.record()["observation"]["sampled_at"], self.now)
        self.now += 1
        self.assertTrue(a.report(self.observe))
        self.assertEqual(self.record()["observation"]["sampled_at"], self.now)

    def test_partial_native_snapshot_fails_closed(self):
        def partial(conn, _peer, deadline):
            conn.recv(1024)
            reply(conn, deadline, 200, {"studio-a": self.record()})

        service = self.listen(("127.0.0.1", 0), partial)
        self.assertEqual([row["enrollment"] for row in studio_nodes(service.address[1])],
                         ["unknown", "unknown"])

    def test_emergency_root_cutoff_denies_a_still_pinned_leaf(self):
        self.approve("studio-a", "edge-a", self.a)
        self.assertTrue(self.client("studio-a", self.a).report(self.observe))
        before = self.record()
        self.start_worker_listener(self.next_root.ca, self.next_server)
        client = self.client("studio-a", self.a, ca=self.next_root.ca)
        with self.assertRaises((OSError, ValueError, http.client.HTTPException)):
            client.report(lambda _: self.fail("An old leaf received a new session"))
        self.assertEqual(self.record(), before)

    def test_valid_tls_leaf_rotation_revocation_and_root_retirement(self):
        self.approve("studio-a", "edge-a", self.a)
        self.approve("studio-b", "edge-b", self.b)
        a = self.client("studio-a", self.a)
        b = self.client("studio-b", self.b)
        self.assertTrue(a.report(self.observe))
        self.assertTrue(b.report(self.observe))
        bundle = self.directory / "rollover.crt"
        bundle.write_bytes(self.ca.read_bytes() + self.next_root.ca.read_bytes())
        self.start_worker_listener(bundle, self.next_server)
        rotate_path = self.directory / "rotate.sock"
        self.listen(str(rotate_path), admin_handler(self.ledger, OPENSSL, bundle, os.geteuid()),
                    family=socket.AF_UNIX)
        for node, machine, old, new in (("studio-a", "edge-a", self.a, self.next_a),
                                         ("studio-b", "edge-b", self.b, self.next_b)):
            pin = fingerprint(ssl.PEM_cert_to_DER_cert(old[0].read_text()))
            old_worker = self.client(node, old, ca=bundle)
            self.assertTrue(old_worker.report(self.observe))
            self.assertEqual(command(rotate_path, dict(action="rotate", node=node, expected=pin,
                                                        machine=machine, leaf=new[0].read_text())),
                             {"ok": True})
            self.assertFalse(old_worker.report(self.observe))
            self.assertTrue(self.client(node, new, ca=bundle).report(self.observe))
            if node == "studio-a":
                self.assertTrue(b.report(self.observe))
        self.start_worker_listener(self.next_root.ca, self.next_server)
        with self.assertRaises((OSError, http.client.HTTPException)):
            self.client("studio-a", self.a, ca=self.next_root.ca).report(self.observe)
        with self.assertRaises((OSError, http.client.HTTPException)):
            self.client("studio-a", self.next_a).report(self.observe)
        pin = fingerprint(ssl.PEM_cert_to_DER_cert(self.next_a[0].read_text()))
        self.assertEqual(command(rotate_path, dict(action="revoke", node="studio-a", expected=pin)),
                         {"ok": True})
        self.assertEqual(self.record()["enrollment"], "revoked")
        self.ledger = Ledger(self.state)
        self.start_worker_listener(self.next_root.ca, self.next_server)
        self.assertFalse(self.client("studio-a", self.next_a, ca=self.next_root.ca).report(self.observe))
        self.assertEqual(self.record("studio-b")["state"], "awaiting")
        self.assertTrue(self.client("studio-b", self.next_b, ca=self.next_root.ca).report(self.observe))

    def test_snapshot_and_forged_file(self):
        (self.directory / "studio-b.json").write_text(json.dumps(self.observe("studio-b")))
        self.approve("studio-a", "edge-a", self.a)
        self.assertTrue(self.client("studio-a", self.a).report(self.observe))
        native = self.listen(("127.0.0.1", 0), snapshot_handler(self.ledger, lambda: native.address[1]))
        server = core.create_server(self.directory, port=0, snapshot_port=native.address[1])
        self.addCleanup(server.server_close)

        def read(path):
            with closing(http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)) as conn:
                conn.request("GET", path)
                server.handle_request()
                return conn.getresponse().read()

        nodes = json.loads(read("/api/v1/cluster"))["nodes"]
        self.assertEqual([node["state"] for node in nodes], ["awaiting", "reporting", "awaiting"])
        html = read("/")
        self.assertIn(b"Not enrolled", html)
        self.assertIn(b"1 of 3 hosts reporting", html)

    def test_cli_initialization_requires_new_directory(self):
        run = [sys.executable, "-B", "-m", "backend.enroll", "init", "--state-dir"]
        target = self.directory / "new-ledger"
        subprocess.run([*run, str(target)], check=True, capture_output=True, timeout=5)
        duplicate = subprocess.run([*run, str(target)], capture_output=True, timeout=5)
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertEqual(Ledger(target).snapshot()["studio-a"]["enrollment"], "not_enrolled")
