"""Readiness/control tests only; do not claim harness inference coverage."""
import asyncio
import json
import os
import sys
import unittest
from uuid import uuid4


class WorkerFoundationTests(unittest.IsolatedAsyncioTestCase):
    async def start(self, **env):
        child = await asyncio.create_subprocess_exec(
            sys.executable, "-I", "-B", "-m", "fios_agent",
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={"PATH": os.environ.get("PATH", ""), "MLX_BASE_URL": "http://127.0.0.1:1/v1", **env},
        )
        self.addAsyncCleanup(self.cleanup, child)
        return child

    async def cleanup(self, child):
        if child.returncode is None:
            child.kill()
        await child.wait()

    async def frame(self, child):
        return json.loads(await asyncio.wait_for(child.stdout.readline(), 3))

    async def test_readiness_without_network_then_eof_shutdown(self):
        child = await self.start()
        self.assertEqual(await self.frame(child), {"v": 1, "type": "ready"})
        child.stdin.close()
        self.assertEqual(await asyncio.wait_for(child.wait(), 2), 0)
        self.assertEqual(await child.stderr.read(), b"")

    async def test_invalid_configuration_is_redacted_and_fails_before_ready(self):
        for endpoint in ["https://user:secret@example.test/v1", "file:///tmp/data", "http://localhost/v1?key=secret"]:
            child = await self.start(MLX_BASE_URL=endpoint)
            self.assertNotEqual(await asyncio.wait_for(child.wait(), 3), 0)
            self.assertEqual(await child.stdout.read(), b"")
            diagnostic = await child.stderr.read()
            self.assertNotIn(b"secret", diagnostic)
            self.assertIn(b"configuration_error", diagnostic)

    async def test_protocol_violation_has_no_echo_or_traceback(self):
        child = await self.start()
        await self.frame(child)
        child.stdin.write(b'{"v":1,"type":"exec","command":"SENSITIVE_MARKER"}\n')
        await child.stdin.drain()
        self.assertNotEqual(await asyncio.wait_for(child.wait(), 2), 0)
        diagnostic = await child.stderr.read()
        self.assertNotIn(b"SENSITIVE_MARKER", diagnostic)
        self.assertNotIn(b"Traceback", diagnostic)

    async def test_immediate_cancel_cannot_race_ahead_of_token(self):
        child = await self.start()
        await self.frame(child)
        run_id = str(uuid4())
        frames = [
            {"v": 1, "type": "run", "run_id": run_id, "model": "test/model",
             "context": [{"role": "user", "content": "hello"}]},
            {"v": 1, "type": "cancel", "run_id": str(uuid4())},
            {"v": 1, "type": "cancel", "run_id": run_id},
            {"v": 1, "type": "cancel", "run_id": run_id},
        ]
        child.stdin.write(b"".join(json.dumps(f).encode() + b"\n" for f in frames))
        await child.stdin.drain()
        self.assertEqual((await self.frame(child))["type"], "started")
        self.assertEqual(await self.frame(child), {"v": 1, "type": "done", "run_id": run_id, "status": "interrupted"})
        child.stdin.close()
        self.assertEqual(await asyncio.wait_for(child.wait(), 2), 0)

    async def test_unreachable_gateway_fails_without_content_leak(self):
        child = await self.start()
        await self.frame(child)
        run_id = str(uuid4())
        child.stdin.write(json.dumps({"v": 1, "type": "run", "run_id": run_id,
            "model": "test/model@peer", "context": [{"role": "user", "content": "SENSITIVE_MARKER"}]}).encode() + b"\n")
        await child.stdin.drain()
        self.assertEqual((await self.frame(child))["type"], "started")
        terminal = await self.frame(child)
        self.assertEqual(terminal, {"v": 1, "type": "error", "run_id": run_id, "code": "upstream_unavailable"})
        child.stdin.write(b'{"v":1,"type":"shutdown"}\n')
        await child.stdin.drain()
        self.assertEqual(await asyncio.wait_for(child.wait(), 2), 0)
        self.assertNotIn(b"SENSITIVE_MARKER", await child.stderr.read())
