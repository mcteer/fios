"""Finite incomplete loopback GET body; no inference or native control."""
import json
import select
import socket
import sys
import time

assert sys.version_info[:3] == (3, 11, 17)
assert len(sys.argv) == 2
port = int(sys.argv[1])
assert 1024 < port < 65536
deadline = time.monotonic() + 12

def remaining():
    value = deadline - time.monotonic()
    assert value > 0
    return min(3, value)

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as connection:
    connection.settimeout(remaining())
    connection.connect(("127.0.0.1", port))
    body = b"x" * 4096
    connection.sendall(b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 4096\r\nConnection: close\r\n\r\n" + body[:1])
    print(json.dumps({"ready": True, "request_bytes": len(body), "sent_body_bytes": 1, "model_requests": 0}), flush=True)
    assert select.select([sys.stdin], [], [], min(8, deadline - time.monotonic()))[0]
    action = sys.stdin.readline()
    assert action in ("release\n", "drain\n")
    if action == "drain\n":
        connection.sendall(body[1:])
        head = bytearray()
        while b"\r\n\r\n" not in head:
            connection.settimeout(remaining())
            chunk = connection.recv(256)
            assert chunk and len(head) + len(chunk) <= 4096
            head.extend(chunk)
        header, initial_body = bytes(head).split(b"\r\n\r\n", 1)
        headers = header.split(b"\r\n")
        assert headers[0] == b"HTTP/1.1 200 OK"
        lengths = [int(line.split(b":", 1)[1]) for line in headers[1:] if line.lower().startswith(b"content-length:")]
        assert len(lengths) == 1 and 256 * 1024 < lengths[0] <= 2 * 1024 * 1024
        count = len(initial_body)
        while count < lengths[0]:
            connection.settimeout(remaining())
            chunk = connection.recv(min(65536, lengths[0] - count))
            assert chunk
            count += len(chunk)
        assert count == lengths[0]
        print(json.dumps({"complete": True, "body_bytes": count}), flush=True)
