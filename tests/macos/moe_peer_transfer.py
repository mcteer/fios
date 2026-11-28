"""Copy a verified public shard over the dedicated Studio link using mTLS."""

import argparse
from contextlib import contextmanager
from http.client import HTTPSConnection
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
from pathlib import Path
import re
import socket
from socketserver import TCPServer
import stat
import time

from backend.enrollment import private_path
from backend.machine_tls import context


LEADER = "192.168.0.1"
FOLLOWER = "192.168.0.2"
BLOCK = 1024 * 1024


class TransferServer(HTTPServer):
    def server_bind(self):
        # The dedicated addresses have no reverse DNS. Advertise the socket
        # immediately without resolving a name before the transfer starts.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]

    def get_request(self):
        stream, peer = super().get_request()
        try:
            if peer[0] != FOLLOWER:
                raise OSError("Unexpected shard recipient")
            stream.settimeout(30)
            return self.tls.wrap_socket(stream, server_side=True), peer
        except BaseException:
            stream.close()
            raise


def serve(path, ca, cert, key):
    private_path(path.parent, directory=True)
    if socket.gethostname().split(".")[0] != "fios-edge-a":
        raise ValueError("Shard sender requires the first Studio")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size <= 0:
            raise ValueError("Expected a verified regular shard")
        sent = False

        class Artifact(BaseHTTPRequestHandler):
            def do_GET(self):
                nonlocal sent
                if self.path != "/shard":
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Length", str(info.st_size))
                self.end_headers()
                deadline = time.monotonic() + 900
                while block := source.read(BLOCK):
                    if time.monotonic() >= deadline:
                        raise TimeoutError("Shard transfer exceeded its deadline")
                    self.wfile.write(block)
                sent = True

            def log_message(self, *_):
                pass

        with TransferServer((LEADER, 0), Artifact) as server:
            server.tls = context(ca, cert, key, server=True)
            server.timeout = 35
            print(server.server_port, flush=True)
            server.handle_request()
            if not sent:
                raise ValueError("Authenticated peer did not finish the shard receipt")


@contextmanager
def receive(port, ca, cert, key):
    if socket.gethostname().split(".")[0] != "fios-edge-b":
        raise ValueError("Shard recipient requires the second Studio")
    connection = HTTPSConnection(LEADER, port, timeout=30, context=context(ca, cert, key))
    try:
        connection.request("GET", "/shard", headers={"Connection": "close"})
        with connection.getresponse() as response:
            if response.status != 200:
                raise ValueError("Peer did not offer the reviewed shard")
            yield response
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("ca", type=Path)
    parser.add_argument("cert", type=Path)
    parser.add_argument("key", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,119}", args.file.name):
        parser.error("Unexpected shard file name")
    serve(args.file, args.ca, args.cert, args.key)


if __name__ == "__main__":
    main()
