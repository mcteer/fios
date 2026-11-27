"""Send native observations to the approved Mini over mutual TLS."""

import http.client
import json
import random
import re
import socket
import ssl
import time

from .machine_tls import context, management_address
from .wire import read_reply


class CoreConnection(http.client.HTTPConnection):
    def __init__(self, address, port, server_name, tls, *, timeout=2):
        super().__init__(address, port, timeout=timeout)
        self.server_name, self.tls = server_name, tls

    def connect(self):
        with socket.create_connection((self.host, self.port), self.timeout) as raw:
            self.sock = self.tls.wrap_socket(raw, server_hostname=self.server_name)


class Reporter:
    def __init__(self, node, address, port, server_name, tls):
        self.node = node
        self.target = address, port, server_name, tls
        self.session = None
        self.sequence = 0

    def request(self, path, body, *, timeout=2):
        connection = CoreConnection(*self.target, timeout=timeout)
        try:
            deadline = time.monotonic() + timeout
            connection.request("POST", path, json.dumps(body, allow_nan=False).encode("ascii"),
                               {"Content-Type": "application/json", "Connection": "close"})
            return read_reply(connection.sock, deadline, 4096)
        finally:
            connection.close()

    def report(self, observe, *, retry_session=True):
        if self.session is None:
            status, reply = self.request("/v1/sessions", {"node": self.node, "version": 1})
            if status != 201:
                return False
            data = json.loads(reply)
            if not (isinstance(data, dict) and data.keys() == {"version", "session"}
                    and type(data["version"]) is int and data["version"] == 1
                    and isinstance(data["session"], str)
                    and re.fullmatch(r"[a-f0-9]{32}", data["session"])):
                raise ValueError("Invalid session reply")
            self.session = data["session"]
            self.sequence = 0
        self.sequence += 1
        report = dict(observe(self.node), session=self.session, sequence=self.sequence)
        status, reply = self.request("/v1/heartbeats", report)
        if status == 409 and reply == b'{"reason": "session"}':
            self.session = None
            if retry_session:
                return self.report(observe, retry_session=False)
        return status == 204

    def run(self, observe):
        backoff = 1
        last_reason = None
        while True:
            try:
                ok = self.report(observe)
                reason = None if ok else "core-rejected"
            except ssl.SSLError:
                reason = "tls"
            except (OSError, ValueError, http.client.HTTPException):
                reason = "transport-or-sample"
            if reason != last_reason:
                print("worker " + (reason or "reporting"), flush=True)
                last_reason = reason
            if reason is None:
                backoff = 1
                time.sleep(5)
            else:
                time.sleep(min(5, backoff + random.uniform(0, 0.25)))
                backoff = min(5, backoff * 2)


def from_args(args):
    if args.node not in ("studio-a", "studio-b"):
        raise ValueError("Only configured Studio workers may report remotely")
    if not all((args.server_name, args.ca, args.cert, args.key)):
        raise ValueError("Worker TLS configuration is incomplete")
    address = management_address(args.remote, args.test_loopback)
    if args.test_loopback and address != "127.0.0.1":
        raise ValueError("Test worker requires loopback")
    if not args.test_loopback and args.port != 8742:
        raise ValueError("Unexpected management port")
    return Reporter(args.node, address, args.port, args.server_name,
                    context(args.ca, args.cert, args.key))
