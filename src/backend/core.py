"""Read-only bootstrap dashboard on the trusted Mini's IPv4 loopback."""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer, ThreadingHTTPServer
from hmac import compare_digest
import json
from pathlib import Path
import re
import secrets
from threading import BoundedSemaphore, Lock
from string import Template
from urllib.parse import parse_qs, urlsplit
import time

from frontend.dashboard import STATIC, STYLE, render

from .chat_bridge import BridgeError, ChatBridge, REQUEST_LIMIT

from .inventory import OBSERVATIONS, read_node
from .local_access import local_role
from .studio_inventory import studio_nodes


def permitted(role, operation):
    return role == "admin" and operation == "inventory.read"


class Handler(BaseHTTPRequestHandler):
    server_version = "fios"

    def setup(self):
        self.request.settimeout(3)
        super().setup()

    def log_message(self, *args):
        # Request targets and headers can contain sensitive input.
        pass

    def reply(self, status, content, media="text/plain; charset=utf-8", *, csrf=None):
        self.send_response(status)
        self.send_header("Content-Type", media)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        policy = "default-src 'none'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; "
        if csrf:
            policy += "script-src 'self'; connect-src 'self'; form-action 'self'"
            self.send_header("Set-Cookie", f"fios-chat={csrf}; Path=/; SameSite=Strict; HttpOnly")
        else:
            policy += "form-action 'none'"
        self.send_header("Content-Security-Policy", policy)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        if status == 405:
            self.send_header("Allow", "GET")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(content)

    def do_GET(self):
        role = local_role(self.client_address[0], self.headers, self.server.server_port)
        if not permitted(role, "inventory.read"):
            return self.reply(403, b"Local operator access required\n")
        if self.path == "/healthz":
            return self.reply(200, b"ok\n")
        if self.server.chat and (self.path in {"/chat", "/chat.js"} or
                                 self.path.startswith("/api/v1/chat/")):
            return self.chat_get()
        if self.path == "/style.css":
            return self.reply(200, STYLE, "text/css; charset=utf-8")
        if self.path not in {"/", "/api/v1/cluster"}:
            return self.reply(404, b"Unknown resource\n")
        now = int(time.time())
        nodes = [read_node(self.server.directory, "fios-core", now)]
        nodes.extend(studio_nodes(self.server.snapshot_port))
        if self.path == "/":
            return self.reply(200, render(nodes, now, chat=self.server.chat is not None,
                                          pair=self.pair_status()), "text/html; charset=utf-8")
        body = dict(version=1, observed_at=now, nodes=nodes)
        self.reply(200, json.dumps(body, allow_nan=False).encode(), "application/json")

    def pair_status(self):
        if self.server.chat is None or not self.server.control_slots.acquire(blocking=False):
            return None
        try:
            return self.server.chat.call("pair-status", {})
        except BridgeError:
            return None
        finally:
            self.server.control_slots.release()

    def method_denied(self):
        self.reply(405, b"Read-only service\n")

    def chat_result(self, action, data):
        slots = self.server.control_slots if action in {"stop", "delete"} else self.server.chat_slots
        if not slots.acquire(blocking=False):
            return self.chat_reply(503, {"reason": "busy"})
        try:
            return self.chat_reply(200, self.server.chat.call(action, data))
        except BridgeError as error:
            return self.chat_reply(error.status, {"reason": str(error)})
        finally:
            slots.release()

    def chat_reply(self, status, data):
        self.reply(status, json.dumps(data, allow_nan=False).encode(), "application/json")

    def chat_cookie(self):
        cookies = self.headers.get_all("Cookie", [])
        values = [value.strip()[10:] for value in ";".join(cookies).split(";")
                  if value.strip().startswith("fios-chat=")]
        return values[0] if len(values) == 1 and re.fullmatch(r"[0-9a-f]{64}", values[0]) else None

    def chat_get(self):
        if self.path == "/chat":
            csrf = self.chat_cookie() or secrets.token_hex(32)
            page = Template((STATIC / "chat.html").read_text()).substitute(csrf=csrf)
            return self.reply(200, page.encode(), "text/html; charset=utf-8", csrf=csrf)
        if self.path == "/chat.js":
            return self.reply(200, (STATIC / "chat.js").read_bytes(), "application/javascript")
        try:
            target = urlsplit(self.path)
            query = parse_qs(target.query, strict_parsing=True, max_num_fields=1, keep_blank_values=True)
        except ValueError:
            return self.chat_reply(400, {"reason": "invalid"})
        prefix = "/api/v1/chat/"
        if target.path == prefix + "catalog" and not query:
            return self.chat_result("catalog", {})
        if target.path == prefix + "history" and (not query or set(query) == {"before"}):
            return self.chat_result("history", {"before": query.get("before", [None])[0]})
        stream = re.fullmatch(prefix + r"stream/([0-9a-f]{32})/([0-9a-f]{32})", target.path)
        if stream and set(query) <= {"after"}:
            after = query.get("after", ["0"])[0]
            if not re.fullmatch(r"[0-9]{1,2}", after) or int(after) > 64:
                return self.chat_reply(400, {"reason": "invalid"})
            return self.chat_stream(*stream.groups(), after=int(after))
        match = re.fullmatch(prefix + r"conversation/([0-9a-f]{32})", target.path)
        if match and not query:
            return self.chat_result("conversation", {"id": match.group(1)})
        return self.chat_reply(404, {"reason": "route"})

    def chat_stream(self, conversation, job, *, after):
        duplicate = False
        full = False
        with self.server.stream_lock:
            duplicate = job in self.server.stream_jobs
            full = len(self.server.stream_jobs) >= 2
            if not duplicate and not full:
                self.server.stream_jobs.add(job)
        if duplicate:
            return self.chat_reply(409, {"reason": "already_attached"})
        if full:
            return self.chat_reply(503, {"reason": "busy"})
        bridge = self.server.chat
        started = False
        terminal = False
        seen_answer = False
        sequence = 0
        active = {"active", "queued", "preparing", "running"}
        deadline = time.monotonic() + 125

        def send(kind, **fields):
            nonlocal sequence
            sequence += 1
            record = {"type": kind, "job": job, "sequence": sequence, **fields}
            self.wfile.write(json.dumps(record, ensure_ascii=False).encode() + b"\n")
            self.wfile.flush()

        ticket = None
        try:
            while time.monotonic() < deadline:
                attach = bridge.call("stream", {"id": conversation, "job": job, "ticket": ticket})
                ticket = attach["ticket"]
                data = bridge.call("conversation", {"id": conversation})
                turn = next((item for item in data["turns"] if item["job"] == job), None)
                if turn is None:
                    if not started:
                        return self.chat_reply(404, {"reason": "unknown_job"})
                    return
                if not started:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("X-Content-Type-Options", "nosniff")
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.close_connection = True
                    started = True
                send("state", state=turn["state"], revision=turn["revision"], usage=turn["usage"])
                # Sensitive and ambiguous content stays private until the
                # complete answer has a current publication decision.
                if not seen_answer and turn["answer"] and turn["state"] in {"succeeded", "completed"}:
                    # The publication cursor survives reconnects. State events
                    # keep their own sequence within the current connection.
                    for cursor, offset in enumerate(range(0, len(turn["answer"]), 1024), 1):
                        if cursor > after:
                            send("text", cursor=cursor, text=turn["answer"][offset:offset + 1024])
                    seen_answer = True
                if turn["state"] not in active:
                    terminal = True
                    return
                time.sleep(0.5)
        except BridgeError as error:
            if not started:
                self.chat_reply(error.status, {"reason": str(error)})
        except OSError:
            pass
        finally:
            try:
                if ticket and not terminal:
                    bridge.call("stop", {"job": job})
            except BridgeError:
                pass
            finally:
                with self.server.stream_lock:
                    self.server.stream_jobs.remove(job)

    def do_POST(self):
        prefix = "/api/v1/chat/"
        if not self.server.chat or not self.path.startswith(prefix):
            return self.method_denied()
        role = local_role(self.client_address[0], self.headers, self.server.server_port)
        origins = self.headers.get_all("Origin", [])
        if role != "admin" or origins != ["http://" + self.headers["Host"]]:
            return self.chat_reply(403, {"reason": "identity"})
        tokens = self.headers.get_all("X-Chat-CSRF", [])
        cookie = self.chat_cookie()
        if (cookie is None or len(tokens) != 1 or not re.fullmatch(r"[0-9a-f]{64}", tokens[0])
                or not compare_digest(cookie, tokens[0])):
            return self.chat_reply(403, {"reason": "csrf"})
        sizes = self.headers.get_all("Content-Length", [])
        if (self.headers.get_all("Content-Type", []) != ["application/json"]
                or "Transfer-Encoding" in self.headers or len(sizes) != 1
                or not re.fullmatch(r"[0-9]{1,8}", sizes[0])):
            return self.chat_reply(400, {"reason": "framing"})
        size = int(sizes[0])
        if size > REQUEST_LIMIT:
            return self.chat_reply(413, {"reason": "too_large"})
        action = self.path[len(prefix):]
        if action not in {"create", "delete", "stop", "submit"}:
            return self.chat_reply(404, {"reason": "route"})
        try:
            body = self.rfile.read(size)
            data = json.loads(body)
            if len(body) != size or not isinstance(data, dict):
                raise ValueError
        except (ValueError, OSError, RecursionError):
            return self.chat_reply(400, {"reason": "invalid"})
        return self.chat_result(action, data)

    do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = method_denied


class ChatHTTPServer(ThreadingHTTPServer):
    def __init__(self, address, handler):
        self.requests = BoundedSemaphore(12)
        super().__init__(address, handler)

    def process_request(self, request, address):
        if not self.requests.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.requests.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.requests.release()


def create_server(directory, port=8741, snapshot_port=8743, *, chat=None):
    server = (ChatHTTPServer if chat else HTTPServer)(("127.0.0.1", port), Handler)
    server.chat = chat
    server.chat_slots = BoundedSemaphore(4)
    server.control_slots = BoundedSemaphore(2)
    server.stream_lock = Lock()
    server.stream_jobs = set()
    server.directory = directory
    server.snapshot_port = snapshot_port
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=OBSERVATIONS)
    parser.add_argument("--port", type=int, default=8741)
    parser.add_argument("--snapshot-port", type=int, default=8743)
    parser.add_argument("--chat-port", type=int)
    parser.add_argument("--chat-key", type=Path)
    args = parser.parse_args()
    if (args.chat_key is None) != (args.chat_port is None):
        parser.error("Chat requires a port and key file")
    chat = ChatBridge(args.chat_port, args.chat_key) if args.chat_key else None
    with create_server(args.directory, args.port, args.snapshot_port, chat=chat) as server:
        print(f"fios listening on http://127.0.0.1:{server.server_port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
