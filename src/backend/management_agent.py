"""Expose one Mac's native observation in its own management container."""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import time

from .inventory import NODES, read_node
from .local_access import local_role


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        self.request.settimeout(2)
        super().setup()

    def log_message(self, *args):
        pass

    def do_GET(self):
        if local_role(self.client_address[0], self.headers, self.server.server_port) != "admin":
            self.reply(403, {"reason": "local_access"})
        elif self.path == "/healthz":
            self.reply(200, {"state": "running"})
        elif self.path == "/v1/host":
            self.reply(200, {"version": 1, "host": read_node(
                self.server.observations, self.server.node, int(self.server.wall()))})
        else:
            self.reply(404, {"reason": "route"})

    def reply(self, status, data):
        body = json.dumps(data, allow_nan=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)


def create_server(node, observations, port, *, wall=time.time):
    if node not in NODES:
        raise ValueError("Unknown cluster inventory ID")
    server = HTTPServer(("127.0.0.1", port), Handler)
    server.node = node
    server.observations = observations
    server.wall = wall
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", required=True, choices=NODES)
    parser.add_argument("--observations", type=Path, default=Path("/observations"))
    parser.add_argument("--port", type=int, default=8745)
    args = parser.parse_args()
    with create_server(args.node, args.observations, args.port) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
