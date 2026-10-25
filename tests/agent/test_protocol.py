import json
import unittest
from uuid import uuid4

from fios_agent.protocol import (
    FrameDecoder, ProtocolError, encode_frame, parse_command, parse_event,
    text_chunks, utf16_length,
)


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.run = {"v": 2, "type": "run", "run_id": str(uuid4()),
                    "model": "mlx/model@studio-a", "context": [{"role": "user", "content": "Hi 🧵"}]}

    def test_exact_model_and_uuid(self):
        command = parse_command(self.run)
        self.assertEqual(command.model, self.run["model"])
        self.assertEqual(str(command.run_id), self.run["run_id"])

    def test_strict_fields_version_types_and_uuid(self):
        for patch in [{"v": 1}, {"v": True}, {"v": "1"}, {"type": "exec"},
                      {"run_id": "not-a-uuid"}, {"key": "secret"},
                      {"model": ""}, {"model": "a" * 1025}, {"model": 3}]:
            with self.subTest(patch=patch), self.assertRaises(ProtocolError):
                parse_command({**self.run, **patch})
        with self.assertRaises(ProtocolError):
            parse_command({**self.run, "model": "é" * 513})

    def test_ordered_context_shapes(self):
        valid = [{"role": "assistant", "content": "old answer"},
                 {"role": "user", "content": [{"type": "text", "text": "image"},
                  {"type": "image_url", "image_url": {"url": "data:image/png;base64,eA=="}}]}]
        self.assertEqual(len(parse_command({**self.run, "context": valid}).context), 2)
        for context in [[], [{"role": "system", "content": "inject"}],
                        [{"role": "assistant", "content": "answer"}],
                        [{"role": "user", "content": [], "extra": True}],
                        [{"role": "assistant", "content": ""}, self.run["context"][0]]]:
            with self.subTest(context=context), self.assertRaises(ProtocolError):
                parse_command({**self.run, "context": context})

    def test_commands_and_safe_event_schemas(self):
        parse_command({"v": 2, "type": "cancel", "run_id": self.run["run_id"]})
        parse_command({"v": 2, "type": "shutdown"})
        parse_event({"v": 2, "type": "ready"})
        parse_event({"v": 2, "type": "error", "run_id": self.run["run_id"],
                     "code": "upstream_http", "upstream_status": 503})
        for patch in [{"code": "raw secret"}, {"upstream_status": 399},
                      {"message": "sensitive"}, {"upstream_status": True}]:
            with self.assertRaises(ProtocolError):
                parse_event({"v": 2, "type": "error", "run_id": self.run["run_id"],
                             "code": "internal_error", **patch})
        with self.assertRaises(ProtocolError):
            parse_event({"v": 2, "type": "done", "run_id": self.run["run_id"], "status": "error"})

    def test_incremental_utf8_crlf_and_frame_bounds(self):
        data = json.dumps(self.run, ensure_ascii=False).encode() + b"\r\n"
        decoder = FrameDecoder(1024)
        frames = []
        for byte in data:
            frames.extend(decoder.feed(bytes([byte])))
        decoder.finish()
        self.assertEqual(frames, [self.run])
        decoder = FrameDecoder(4)
        with self.assertRaises(ProtocolError):
            list(decoder.feed(b"abcde"))
        with self.assertRaises(ProtocolError):
            list(FrameDecoder(8).feed(b"\xff\n"))
        with self.assertRaises(ProtocolError):
            list(FrameDecoder(8).feed(b"{bad}\n"))
        decoder = FrameDecoder(8)
        list(decoder.feed(b"{}"))
        with self.assertRaises(ProtocolError):
            decoder.finish()
        with self.assertRaises(ProtocolError):
            list(FrameDecoder(100).feed(b'{"v":1,"v":2}\n'))

    def test_output_splits_unicode_and_limits_encoding(self):
        text = "a🧵" * 40000
        parts = list(text_chunks(text))
        self.assertEqual("".join(parts), text)
        self.assertTrue(all(utf16_length(p) <= 32768 for p in parts))
        for p in parts:
            frame = {"v": 2, "type": "delta", "run_id": self.run["run_id"], "content": p}
            self.assertLessEqual(len(encode_frame(frame)) - 1, 1024 * 1024)
        with self.assertRaises(ProtocolError):
            encode_frame({"huge": "a" * 100}, limit=10)
        with self.assertRaises(ProtocolError):
            parse_event({"v": 2, "type": "delta", "run_id": self.run["run_id"], "content": "a" * 32769})
