from contextlib import closing
from datetime import datetime, timezone
from email.message import Message
import http.client
import json
import os
from pathlib import Path
import tempfile
import threading
import time
import tomllib
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from backend import core, host_agent
from backend.inventory import NODES, read_node


class FoundationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.node = "fios-core"
        self.now = int(time.time())
        self.sample = dict(version=1, node=self.node, sampled_at=self.now,
                           memory_bytes=24 * 1024**3, logical_cpus=12, load_1m=1.5)

    def test_agent_to_dashboard(self):
        host_agent.publish(self.directory, self.sample)
        item = read_node(self.directory, self.node, self.now)
        self.assertEqual(item["state"], "reporting")
        self.assertEqual(item["observation"], self.sample)
        self.assertEqual(read_node(self.directory, self.node, self.now + 30)["state"], "reporting")
        self.assertEqual(read_node(self.directory, self.node, self.now + 31)["state"], "stale")
        self.assertEqual(read_node(self.directory, self.node, self.now - 1)["state"], "invalid")
        self.assertEqual(read_node(self.directory, "studio-a", self.now)["state"], "awaiting")

    def test_new_export_is_readable_under_a_private_umask(self):
        export = self.directory / "private" / "observations"
        old = os.umask(0o077)
        try:
            host_agent.publish(export, self.sample)
        finally:
            os.umask(old)
        self.assertEqual(export.parent.stat().st_mode & 0o077, 0)
        self.assertTrue(export.stat().st_mode & 0o001)
        self.assertTrue((export / "fios-core.json").stat().st_mode & 0o004)

    def test_bad_observations_fail_closed(self):
        path = self.directory / "fios-core.json"
        for data in (b"{", b" " * 5000, b"{}",
                     json.dumps(dict(self.sample, node="studio-b")).encode(),
                     json.dumps(dict(self.sample, version=True)).encode(),
                     json.dumps(dict(self.sample, load_1m=float("nan"))).encode(),
                     json.dumps(dict(self.sample, logical_cpus=-1)).encode(),
                     json.dumps(dict(self.sample, extra="private")).encode()):
            with self.subTest(data=data[:60]):
                path.write_bytes(data)
                result = read_node(self.directory, self.node, self.now)
                self.assertEqual((result["state"], result["observation"]), ("invalid", None))
        path.unlink()
        path.symlink_to(self.directory / "other")
        self.assertEqual(read_node(self.directory, self.node, self.now)["state"], "invalid")
        path.unlink()
        os.mkfifo(path)
        self.assertEqual(read_node(self.directory, self.node, self.now)["state"], "invalid")

    def test_admin_permission_is_explicit(self):
        self.assertTrue(core.permitted("admin", "inventory.read"))
        for role, operation in (("user", "inventory.read"), ("unknown", "inventory.read"),
                                ("admin", "execute")):
            self.assertFalse(core.permitted(role, operation))

    def test_bootstrap_identity_requires_local_transport(self):
        headers = Message()
        headers["Host"] = "127.0.0.1:8741"
        self.assertIsNone(core.local_role("192.0.2.1", headers, 8741))
        self.assertEqual(core.local_role("127.0.0.1", headers, 8741), "admin")
        headers["Host"] = "localhost:8741"
        self.assertIsNone(core.local_role("127.0.0.1", headers, 8741))

    def test_project_presets(self):
        path = Path(__file__).resolve().parents[1] / "src" / "agent" / "authoring.toml"
        with path.open("rb") as stream:
            presets = tomllib.load(stream)
        self.assertEqual(set(presets["modes"]), {"campaign", "one_shot", "session"})
        for ratio, (width, height) in presets["image"]["ratios"].items():
            a, b = map(int, ratio.split(":"))
            self.assertEqual(width * b, height * a)
            self.assertTrue(width > 0 and height > 0 and width % 16 == height % 16 == 0)
        self.assertIn("orc", presets["image"]["species"])
        self.assertIn("elf", presets["image"]["species"])

    def start_http_server(self):
        server = core.create_server(self.directory, port=0, snapshot_port=0)
        self.addCleanup(server.server_close)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        port = server.server_port

        def request(path, method="GET", body=None, **headers):
            with closing(http.client.HTTPConnection("127.0.0.1", port, timeout=3)) as conn:
                conn.request(method, path, body=body, headers=headers)
                response = conn.getresponse()
                return response.status, response.read()

        return request

    def test_overview_freshness_labels_and_counts(self):
        request = self.start_http_server()

        def overview(at):
            with patch.object(core, "time", SimpleNamespace(time=lambda: at)):
                status, body = request("/")
            self.assertEqual(status, 200)
            self.assertEqual(body.count(b"<article>"), 3)
            return body

        body = overview(self.now)
        self.assertIn(b"0 of 3 hosts reporting", body)
        self.assertEqual(body.count(b">Awaiting sample</span>"), 1)
        self.assertEqual(body.count(b">Telemetry unavailable</span>"), 2)
        self.assertNotIn(b"<dt>Observed</dt>", body)

        host_agent.publish(self.directory, self.sample)
        observed = datetime.fromtimestamp(self.now, timezone.utc)
        measurements = (
            b"<dt>Physical memory</dt><dd>24.0 GiB</dd>",
            b"<dt>Logical CPUs</dt><dd>12</dd>",
            b"<dt>Load average (1 min)</dt><dd>1.50</dd>",
            f"<dt>Observed</dt><dd>{observed:%Y-%m-%d %H:%M:%S} UTC</dd>".encode(),
        )
        for age, label, count in ((30, b"Reporting", b"1"), (31, b"Stale sample", b"0")):
            with self.subTest(age=age):
                body = overview(self.now + age)
                self.assertIn(count + b" of 3 hosts reporting", body)
                self.assertEqual(body.count(b">" + label + b"</span>"), 1)
                self.assertEqual(body.count(b">Telemetry unavailable</span>"), 2)
                for measurement in measurements:
                    self.assertIn(measurement, body)

        (self.directory / "fios-core.json").write_bytes(b"{")
        body = overview(self.now)
        self.assertIn(b"0 of 3 hosts reporting", body)
        self.assertEqual(body.count(b">Invalid sample</span>"), 1)
        self.assertEqual(body.count(b">Telemetry unavailable</span>"), 2)
        self.assertNotIn(b"<dl>", body)

    def test_http_entry_points(self):
        host_agent.publish(self.directory, self.sample)
        request = self.start_http_server()
        status, body = request("/api/v1/cluster")
        self.assertEqual(status, 200)
        self.assertEqual([n["id"] for n in json.loads(body)["nodes"]], list(NODES))
        self.assertIn(b"1.50", request("/")[1])
        self.assertEqual(request("/style.css")[0], 200)
        self.assertEqual(request("/healthz")[0], 200)
        self.assertEqual(request("/.env.local")[0], 404)

    def test_denied_reads_and_writes_leave_observations_intact(self):
        host_agent.publish(self.directory, self.sample)
        observation = self.directory / "fios-core.json"
        original = observation.read_bytes()
        request = self.start_http_server()

        for headers in ({"Host": "elsewhere.test"}, {"Origin": "https://elsewhere.test"},
                        {"X-Forwarded-For": "127.0.0.1"}, {"Sec-Fetch-Site": "cross-site"},
                        {"Authorization": "Bearer invalid"}, {"X-Fios-Role": "admin"}):
            for route in ("/", "/api/v1/cluster"):
                with self.subTest(headers=headers, route=route):
                    self.assertEqual(request(route, **headers),
                                     (403, b"Local operator access required\n"))
                    self.assertEqual(observation.read_bytes(), original)

        replacement = json.dumps(dict(self.sample, logical_cpus=6))
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            with self.subTest(method=method):
                self.assertEqual(request("/api/v1/cluster", method, body=replacement),
                                 (405, b"Read-only service\n"))
                self.assertEqual({p.name: p.read_bytes() for p in self.directory.iterdir()},
                                 {observation.name: original})
