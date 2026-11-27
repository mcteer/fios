"""Read-only bootstrap dashboard on the trusted Mini's IPv4 loopback."""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
from ipaddress import ip_address
import json
from pathlib import Path
import time

from frontend.dashboard import STYLE, render

from .inventory import NODES, OBSERVATIONS, read_node


def permitted(role, operation):
    return role == "admin" and operation == "inventory.read"


def local_role(peer, headers, port):
    if not ip_address(peer).is_loopback:
        return None
    hosts = headers.get_all("Host", [])
    if len(hosts) != 1 or hosts[0] not in {f"localhost:{port}", f"127.0.0.1:{port}"}:
        return None
    origins = headers.get_all("Origin", [])
    if origins and origins != [f"http://{hosts[0]}"]:
        return None
    if "cross-site" in headers.get_all("Sec-Fetch-Site", []):
        return None
    if "Authorization" in headers or "Proxy-Authorization" in headers:
        return None
    if any(h.lower().startswith(("forwarded", "x-forwarded-", "x-fios-", "x-role",
                                 "x-real-ip", "x-remote-user")) for h in headers):
        return None
    return "admin"


class Handler(BaseHTTPRequestHandler):
    server_version = "fios"

    def setup(self):
        self.request.settimeout(3)
        super().setup()

    def log_message(self, *args):
        # Request targets and headers can contain sensitive input.
        pass

    def reply(self, status, content, media="text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", media)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy",
                         "default-src 'none'; style-src 'self'; frame-ancestors 'none'; "
                         "base-uri 'none'; form-action 'none'")
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
        if self.path == "/style.css":
            return self.reply(200, STYLE, "text/css; charset=utf-8")
        if self.path not in {"/", "/api/v1/cluster"}:
            return self.reply(404, b"Unknown resource\n")
        now = int(time.time())
        nodes = [read_node(self.server.directory, node, now) for node in NODES]
        if self.path == "/":
            return self.reply(200, render(nodes, now), "text/html; charset=utf-8")
        body = dict(version=1, observed_at=now, nodes=nodes)
        self.reply(200, json.dumps(body, allow_nan=False).encode(), "application/json")

    def method_denied(self):
        self.reply(405, b"Read-only service\n")

    do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = method_denied


def create_server(directory, port=8741):
    server = HTTPServer(("127.0.0.1", port), Handler)
    server.directory = directory
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=OBSERVATIONS)
    args = parser.parse_args()
    with create_server(args.directory) as server:
        print(f"fios listening on http://127.0.0.1:{server.server_port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
