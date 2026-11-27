"""Bounded worker transport and native read-only inventory."""

from concurrent.futures import ThreadPoolExecutor
from email.message import Message
from http import HTTPStatus
import json
import re
import socket
import sqlite3
import ssl
import threading
import time

from .core import local_role
from .enrollment import Rejected, STUDIOS
from .machine_tls import fingerprint
from .wire import FrameTooLarge, read_exact, read_until, timeout

HEADER_LIMIT = 8192
BODY_LIMIT = 4096
SNAPSHOT_LIMIT = 8192
TOKEN = re.compile(rb"[!#$%&'*+.^_`|~0-9A-Za-z-]+")
ROUTES = {"/v1/sessions", "/v1/heartbeats"}


def unique_object(pairs):
    data = dict(pairs)
    if len(pairs) != len(data):
        raise ValueError("Duplicate JSON keys")
    return data


def json_object(raw):
    data = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
    if not isinstance(data, dict):
        raise ValueError("Expected a JSON object")
    return data


def read_request(connection, deadline):
    raw, remainder = read_until(connection, b"\r\n\r\n", HEADER_LIMIT, deadline)
    first, *header_lines = raw.split(b"\r\n")
    method, target, version = first.decode("ascii").split(" ")
    if version not in {"HTTP/1.0", "HTTP/1.1"}:
        raise ValueError("Bad HTTP version")
    headers = Message()
    for line in header_lines:
        key, separator, value = line.partition(b":")
        if not separator or not TOKEN.fullmatch(key) or any(c < 32 and c != 9 or c > 126 for c in value):
            raise ValueError("Bad header")
        headers[key.decode("ascii")] = value.decode("ascii").strip()
    return method, target, headers, remainder


def reply(connection, deadline, code, data=None):
    body = b"" if data is None else json.dumps(data, allow_nan=False).encode("ascii")
    response = (f"HTTP/1.1 {code} {HTTPStatus(code).phrase}\r\nConnection: close\r\n"
                f"Cache-Control: no-store\r\nContent-Type: application/json\r\n"
                f"Content-Length: {len(body)}\r\n\r\n").encode("ascii")
    timeout(connection, deadline)
    connection.sendall(response + body)


class Listener:
    """An accept loop with no unbounded executor queue."""

    def __init__(self, address, handle, *, capacity=8, family=socket.AF_INET,
                 per_peer=None, overload=None):
        self.socket = socket.socket(family, socket.SOCK_STREAM)
        try:
            if family == socket.AF_INET:
                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.socket.bind(address)
            self.socket.listen(8)
            self.socket.settimeout(0.25)
        except BaseException:
            self.socket.close()
            raise
        self.address = self.socket.getsockname()
        self.stop = threading.Event()
        self.slots = threading.BoundedSemaphore(capacity)
        self.per_peer = per_peer
        self.overload = overload
        self.peers = {}
        self.peer_lock = threading.Lock()
        self.pool = ThreadPoolExecutor(max_workers=capacity)
        self.handle = handle
        self.thread = threading.Thread(target=self.serve)

    def serve(self):
        while not self.stop.is_set():
            try:
                conn, peer = self.socket.accept()
            except TimeoutError:
                continue
            except OSError:
                if self.stop.is_set():
                    return
                raise
            if self.reserve(peer):
                self.pool.submit(self.run, conn, peer, time.monotonic() + 3)
            else:
                conn.close()
                if self.overload:
                    self.overload()

    def reserve(self, peer):
        with self.peer_lock:
            if self.per_peer is not None and self.peers.get(peer[0], 0) >= self.per_peer:
                return False
            if not self.slots.acquire(blocking=False):
                return False
            if self.per_peer is not None:
                self.peers[peer[0]] = self.peers.get(peer[0], 0) + 1
            return True

    def run(self, conn, peer, deadline):
        try:
            with conn:
                self.handle(conn, peer, deadline)
        except (OSError, ValueError):
            pass
        finally:
            with self.peer_lock:
                if self.per_peer is not None:
                    if self.peers[peer[0]] == 1:
                        del self.peers[peer[0]]
                    else:
                        self.peers[peer[0]] -= 1
                self.slots.release()

    def start(self):
        self.thread.start()
        return self

    def close(self):
        self.stop.set()
        self.socket.close()
        if self.thread.ident is not None:
            self.thread.join()
        self.pool.shutdown()


def worker_handler(ledger, context):
    def handle(raw, _peer, deadline):
        timeout(raw, deadline)
        try:
            conn = context.wrap_socket(raw, server_side=True)
        except (ssl.SSLError, OSError):
            ledger.count("tls")
            return
        with conn:
            try:
                method, target, headers, remaining = read_request(conn, deadline)
                if target not in ROUTES:
                    raise Rejected("route", 404)
                if method != "POST":
                    raise Rejected("method", 405)
                sizes = headers.get_all("Content-Length", [])
                if ("Transfer-Encoding" in headers or len(sizes) != 1
                        or not re.fullmatch(r"[0-9]{1,18}", sizes[0])
                        or headers.get_all("Content-Type", []) != ["application/json"]):
                    raise Rejected("framing")
                size = int(sizes[0])
                if size > BODY_LIMIT:
                    raise Rejected("size", 413)
                data = json_object(read_exact(conn, remaining, size, deadline))
                node = data.get("node")
                if node not in STUDIOS:
                    raise Rejected("identity", 403)
                expires = ssl.cert_time_to_seconds(conn.getpeercert()["notAfter"])
                if time.time() >= expires:
                    raise Rejected("identity", 403)
                pin = fingerprint(conn.getpeercert(binary_form=True))
                if target == "/v1/sessions":
                    if data.keys() != {"version", "node"} or type(data["version"]) is not int or data["version"] != 1:
                        raise Rejected("invalid")
                    session = ledger.open_session(node, pin)
                    reply(conn, deadline, 201, {"version": 1, "session": session})
                else:
                    ledger.accept(node, pin, data)
                    reply(conn, deadline, 204)
            except FrameTooLarge:
                ledger.count("headers")
                reply(conn, deadline, 413, {"reason": "headers"})
            except Rejected as error:
                ledger.count(error.reason)
                reply(conn, deadline, error.status, {"reason": error.reason})
            except (ValueError, RecursionError):
                ledger.count("invalid")
                reply(conn, deadline, 400, {"reason": "invalid"})
            except (OSError, TimeoutError):
                ledger.count("transport")
            except sqlite3.Error:
                ledger.count("store")
                reply(conn, deadline, 503, {"reason": "store"})
    return handle


def snapshot_handler(ledger, port):
    def handle(conn, peer, deadline):
        method, path, headers, remaining = read_request(conn, deadline)
        if local_role(peer[0], headers, port()) != "admin":
            reply(conn, deadline, 403)
        elif method != "GET" or remaining or "Content-Length" in headers or "Transfer-Encoding" in headers:
            reply(conn, deadline, 405)
        elif path != "/v1/studios":
            reply(conn, deadline, 404)
        else:
            try:
                studios = ledger.snapshot()
            except sqlite3.Error:
                reply(conn, deadline, 503)
            else:
                reply(conn, deadline, 200, studios)
    return handle
