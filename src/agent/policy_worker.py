"""Serve a pinned local text checker with an independent native process lifecycle."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import re
import signal
from subprocess import SubprocessError
import time

from backend.enrollment import Rejected
from backend.heartbeat import json_object
from .native_runtime import NativeRuntime
from .publication_prompt import messages_for


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        self.request.settimeout(2)
        super().setup()

    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.path != "/v1/classify":
            return self.reply(404, b"")
        sizes = self.headers.get_all("Content-Length", [])
        if (len(sizes) != 1 or not re.fullmatch(r"[0-9]{1,6}", sizes[0])
                or self.headers.get_all("Content-Type") != ["application/json"]
                or "Transfer-Encoding" in self.headers):
            return self.reply(400, b"")
        size = int(sizes[0])
        if not 0 < size <= 128 * 1024:
            return self.reply(413, b"")
        try:
            data = json_object(self.rfile.read(size))
            if data.keys() != {"purpose", "text", "revision"}:
                return self.reply(400, b"")
            purpose, text = data["purpose"], data["text"]
            if purpose not in ("input", "answer", "title") or not isinstance(text, str):
                return self.reply(400, b"")
            if data["revision"] != self.server.revision:
                return self.reply(409, b"")
            # The runtime template's role delimiters must stay in trusted
            # message structure. Treat literal reserved delimiters as uncertain.
            allow = not any(mark in text for mark in ("<|im_start|>", "<|im_end|>", "<|endoftext|>"))
            allow = allow and self.server.classify(purpose, text)
            self.reply(200, b'{"allow":true}\n' if allow is True else b'{"allow":false}\n')
        except Rejected:
            self.reply(503, b"")
        except (OSError, ValueError, RecursionError, SubprocessError):
            self.reply(503, b"")

    def reply(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Fios-Policy-Revision", self.server.revision)
        self.end_headers()
        self.wfile.write(body)


def create_server(port, revision, classify):
    if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{64}", revision):
        raise ValueError("Expected a pinned policy revision")
    server = HTTPServer(("127.0.0.1", port), Handler)
    server.revision, server.classify = revision, classify
    return server


def classify(runtime, purpose, text, *, input_limit=4096):
    messages = messages_for({"purpose": purpose, "text": text}, "framed")
    runtime.arm()
    try:
        if input_limit == 4096:
            answer, _ = runtime.generate(runtime.revision, messages, input_limit, 8,
                                          time.monotonic() + 5, preserve_context=True)
        else:
            environment = runtime.environment()
            environment["PYTHONPATH"] = str(Path(__file__).resolve().parents[1])
            child = runtime.spawn("agent.policy_rank", (str(runtime.model),), environment, capture=True)
            output, _ = child.communicate(json.dumps(messages).encode("ascii"), timeout=30)
            if child.returncode:
                reason = {65: "context_limit", 66: "policy_decision_invalid",
                          78: "policy_resource_floor"}.get(child.returncode, "policy_runtime_failed")
                raise Rejected(reason, 503)
            if len(output) > 16:
                raise Rejected("publication_unavailable", 503)
            answer = output.decode()
    finally:
        # The classifier and the Mini generator share the native executor lock.
        # Report an approval only after the policy model is fully released.
        runtime.stop()
    if not runtime.quiescent():
        raise Rejected("cleanup_required", 409)
    if answer.strip() not in ("ALLOW", "WITHHOLD"):
        raise Rejected("publication_unavailable", 503)
    return answer.strip() == "ALLOW"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--input-limit", type=int, choices=(4096, 12288), default=4096)
    args = parser.parse_args()
    runtime = NativeRuntime(args.config, args.state, purpose="policy", policy_input_limit=args.input_limit)

    def check(purpose, text):
        return classify(runtime, purpose, text, input_limit=args.input_limit)

    with create_server(args.port, runtime.revision, check) as server:
        signal.signal(signal.SIGTERM, signal.default_int_handler)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            runtime.stop()


if __name__ == "__main__":
    main()
