"""Contract tests for the pinned inference stream shape."""
import io
import unittest

from agent.inference import read_completion
from backend.enrollment import Rejected


class CompletionTests(unittest.TestCase):
    def completion(self, *frames):
        stream = io.BytesIO(b"\n\n".join(frames) + b"\n\n")
        return read_completion(stream, input_limit=1024, output_limit=128)

    def test_answer_excludes_reasoning_and_keeps_tagged_counts(self):
        text, usage = self.completion(
            b": keepalive",
            b'data: {"choices":[{"delta":{"reasoning_content":"private"}}]}',
            b'data: {"choices":[{"delta":{"content":"Hi"}}]}',
            b'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
            b'data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":3}}',
            b"data: [DONE]",
        )
        self.assertEqual(text, "Hi")
        self.assertEqual(usage, {"input": {"kind": "measured", "value": 7},
                                 "output": {"kind": "measured", "value": 3}})

    def test_lost_terminal_and_tool_output_are_fenced(self):
        for frames in (
            (b'data: {"choices":[{"delta":{"content":"Hi"}}]}',),
            (b'data: {"choices":[{"delta":{"tool_calls":[{}]}}]}', b"data: [DONE]"),
            (b'data: {"choices":[{"delta":{"content":"Hi","name":"other"},"finish_reason":"stop"}]}',
             b"data: [DONE]"),
            (b'data: {"choices":[{"delta":{"content":"Hi","tool_call_id":"1"},"finish_reason":"stop"}]}',
             b"data: [DONE]"),
            (b'data: {"choices":[{"delta":{"content":"Hi"}}]}', b"data: [DONE]"),
        ):
            with self.subTest(frames=frames), self.assertRaises(Rejected):
                self.completion(*frames)

    def test_mlx_vlm_nullable_tool_metadata_is_accepted(self):
        text, _ = self.completion(
            b'data: {"choices":[{"delta":{"role":"assistant","content":"Hi",'
            b'"reasoning":null,"reasoning_content":null,"name":null,"tool_call_id":null,"tool_calls":null}}]}',
            b'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
            b"data: [DONE]",
        )
        self.assertEqual(text, "Hi")

    def test_missing_usage_is_unknown(self):
        _, usage = self.completion(
            b'data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":"stop"}]}',
            b"data: [DONE]",
        )
        self.assertEqual(usage, {"input": {"kind": "unknown"}, "output": {"kind": "unknown"}})


class LoopbackRuntimeTests(unittest.TestCase):
    def test_fixed_route_and_text_payload(self):
        from http.server import BaseHTTPRequestHandler, HTTPServer
        import json
        from threading import Thread

        from agent.inference import generate_text

        seen = []

        class FakeRuntime(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                seen.append((self.path, payload))
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                self.wfile.write(
                    b'data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":"stop"}]}\n\n'
                    b"data: [DONE]\n\n"
                )

        with HTTPServer(("127.0.0.1", 0), FakeRuntime) as server:
            thread = Thread(target=server.serve_forever)
            thread.start()
            try:
                text, _ = generate_text(server.server_port, [{"role": "user", "content": "Hi"}],
                                        input_limit=1024, output_limit=32, timeout=2)
                self.assertEqual(text, "Hello")
                route, payload = seen[0]
                self.assertEqual(route, "/v1/chat/completions")
                self.assertEqual(payload["max_tokens"], 32)
                self.assertTrue(payload["stream"])
                self.assertEqual(payload["messages"], [{"role": "user", "content": "Hi"}])
                self.assertNotIn("model", payload)
                self.assertNotIn("tools", payload)
                with self.assertRaises(Rejected):
                    generate_text(server.server_port,
                                  [{"role": "user", "content": [{"type": "image_url"}]}],
                                  input_limit=1024, output_limit=32, timeout=2)
                self.assertEqual(len(seen), 1)
            finally:
                server.shutdown()
                thread.join(timeout=2)


class DecodeMeasurementTests(unittest.TestCase):
    def test_reasoning_only_measures_usage_without_a_publishable_answer(self):
        stream = (
            b'data: {"choices":[{"delta":{"reasoning":"private"}}]}\n\n'
            b'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n'
            b'data: {"choices":[],"usage":{"prompt_tokens":22,"completion_tokens":32}}\n\n'
            b'data: [DONE]\n\n'
        )
        with self.assertRaisesRegex(Rejected, "runtime_stream_invalid"):
            read_completion(io.BytesIO(stream), input_limit=128, output_limit=32)
        answer, usage = read_completion(io.BytesIO(stream), input_limit=128, output_limit=32,
                                        measure_only=True)
        self.assertEqual(answer, "")
        self.assertEqual(usage["output"], {"kind": "measured", "value": 32})
