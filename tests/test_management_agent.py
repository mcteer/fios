"""Local telemetry scope for the dedicated per-host management container."""

from http.client import HTTPConnection
import json
from pathlib import Path
import tempfile
from threading import Thread
import unittest

from backend.host_agent import publish
from backend.inventory import NODES
from backend.management_agent import create_server


class ManagementAgentTests(unittest.TestCase):
    def test_each_instance_serves_only_its_native_host(self):
        now = 1_000
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / "observations"
            for node in NODES:
                publish(directory, dict(version=1, node=node, sampled_at=now, memory_bytes=1024,
                                        logical_cpus=2, load_1m=0))
            for node in NODES:
                with self.subTest(node=node), create_server(node, directory, 0,
                                                           wall=lambda: now) as server:
                    thread = Thread(target=server.serve_forever)
                    thread.start()
                    try:
                        with self.connect(server) as connection:
                            connection.request("GET", "/v1/host")
                            response = connection.getresponse()
                            self.assertEqual(response.status, 200)
                            body = json.loads(response.read())
                            self.assertEqual(body["host"]["id"], node)
                            self.assertEqual(body["host"]["state"], "reporting")
                            connection.request("GET", "/v1/host", headers={"Host": "example.invalid"})
                            response = connection.getresponse()
                            self.assertEqual(response.status, 403)
                            response.read()
                            now += 31
                            connection.request("GET", "/v1/host")
                            self.assertEqual(json.loads(connection.getresponse().read())["host"]["state"],
                                             "stale")
                    finally:
                        now = 1_000
                        server.shutdown()
                        thread.join(timeout=3)

    @staticmethod
    def connect(server):
        from contextlib import closing
        return closing(HTTPConnection("127.0.0.1", server.server_port, timeout=2))
