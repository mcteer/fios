"""Local operator CLI and the native enrollment service."""

import argparse
from contextlib import ExitStack
import ctypes
import fcntl
import json
import os
from pathlib import Path
import signal
import socket
import sqlite3
import stat
import struct
import threading
import time

from .enrollment import Ledger, Rejected, STUDIOS
from .heartbeat import Listener, json_object, snapshot_handler, worker_handler
from .machine_tls import context, management_address, verified_worker_leaf
from .wire import read_until, timeout

ADMIN_LIMIT = 8192


def peer_uid(conn):
    if hasattr(socket, "SO_PEERCRED"):
        credentials = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        return struct.unpack("3i", credentials)[1]
    uid, gid = ctypes.c_uint(), ctypes.c_uint()
    getpeereid = ctypes.CDLL(None, use_errno=True).getpeereid
    getpeereid.argtypes = (ctypes.c_int, ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint))
    if getpeereid(conn.fileno(), ctypes.byref(uid), ctypes.byref(gid)):
        raise OSError(ctypes.get_errno(), "Could not verify peer")
    return uid.value


def admin_handler(ledger, openssl, ca, operator):
    def handle(conn, _peer, deadline):
        try:
            if peer_uid(conn) != operator:
                raise Rejected("identity", 403)
            raw, remainder = read_until(conn, b"\n", ADMIN_LIMIT, deadline)
            if remainder:
                raise Rejected("invalid")
            data = json_object(raw)
            action = data.get("action")
            if action == "status" and data.keys() == {"action"}:
                result = ledger.status()
            else:
                if action not in ("approve", "rotate", "revoke"):
                    raise Rejected("invalid")
                expected_fields = {"action", "node", "expected"}
                if action != "revoke":
                    expected_fields |= {"machine", "leaf"}
                if data.keys() != expected_fields or data["node"] not in STUDIOS:
                    raise Rejected("invalid")
                machine = data.get("machine")
                pin = (verified_worker_leaf(openssl, ca, data["leaf"], machine)
                       if action != "revoke" else None)
                ledger.change(action, data["node"], data["expected"], machine=machine, pin=pin)
                result = {}
            response = {"ok": True, **result}
        except Rejected as error:
            ledger.count(error.reason)
            response = {"ok": False, "reason": error.reason}
        except (ValueError, RecursionError):
            ledger.count("invalid")
            response = {"ok": False, "reason": "invalid"}
        except sqlite3.Error:
            ledger.count("store")
            response = {"ok": False, "reason": "store"}
        timeout(conn, deadline)
        conn.sendall(json.dumps(response).encode("ascii") + b"\n")
    return handle


def command(path, data):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        deadline = time.monotonic() + 3
        timeout(conn, deadline)
        conn.connect(str(path))
        if peer_uid(conn) != os.geteuid():
            raise ValueError("Unexpected operator socket owner")
        body = json.dumps(data, ensure_ascii=True).encode("ascii")
        if len(body) >= ADMIN_LIMIT:
            raise ValueError("Operator request exceeds limit")
        conn.sendall(body + b"\n")
        raw, rest = read_until(conn, b"\n", ADMIN_LIMIT, deadline)
        if rest:
            raise ValueError("Unexpected operator response")
        return json_object(raw)


def serve(args):
    directory = args.state_dir.absolute()
    ledger = Ledger(directory)
    if not args.openssl.is_absolute() or not args.openssl.is_file():
        raise ValueError("Specify a reviewed absolute OpenSSL executable")
    if not args.test_loopback and (args.worker_port != 8742 or args.snapshot_port != 8743):
        raise ValueError("Unexpected production port")
    address = management_address(args.bind, args.test_loopback)
    if args.test_loopback and address != "127.0.0.1":
        raise ValueError("Test service requires loopback")
    tls = context(args.ca, args.cert, args.key, server=True)
    endpoint = directory / "operator.sock"
    lock_path = directory / "service.lock"
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    with ExitStack() as stack:
        descriptor = os.open(lock_path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        stack.callback(os.close, descriptor)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if endpoint.exists() or endpoint.is_symlink():
            if not stat.S_ISSOCK(endpoint.lstat().st_mode):
                raise ValueError("Unexpected operator socket path")
            endpoint.unlink()
        admin = Listener(str(endpoint), admin_handler(ledger, args.openssl, args.ca, os.geteuid()),
                         capacity=1, family=socket.AF_UNIX)
        stack.callback(endpoint.unlink, missing_ok=True)
        stack.callback(admin.close)
        endpoint.chmod(0o600)
        workers = Listener((address, args.worker_port), worker_handler(ledger, tls),
                           per_peer=3, overload=lambda: ledger.count("overload"))
        stack.callback(workers.close)
        readings = Listener(("127.0.0.1", args.snapshot_port),
                            snapshot_handler(ledger, lambda: readings.address[1]), capacity=4)
        stack.callback(readings.close)
        for listener in (admin, readings, workers):
            listener.start()
        print(json.dumps({"worker_port": workers.address[1], "snapshot_port": readings.address[1]}),
              flush=True)
        while not stopping.wait(0.25):
            if not all(listener.thread.is_alive() for listener in (admin, readings, workers)):
                raise RuntimeError("A native listener stopped")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", type=Path)
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("init", "serve"):
        p = sub.add_parser(name)
        p.add_argument("--state-dir", type=Path, required=True)
        if name == "serve":
            p.add_argument("--bind", required=True)
            for flag in ("ca", "cert", "key", "openssl"):
                p.add_argument(f"--{flag}", type=Path, required=True)
            p.add_argument("--worker-port", type=int, default=8742)
            p.add_argument("--snapshot-port", type=int, default=8743)
            p.add_argument("--test-loopback", action="store_true")
    sub.add_parser("status")
    for name in ("approve", "rotate", "revoke"):
        p = sub.add_parser(name)
        p.add_argument("node", choices=STUDIOS)
        p.add_argument("--expected", required=name != "approve")
        if name != "revoke":
            p.add_argument("--machine", required=True)
            p.add_argument("--leaf", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == "init":
            Ledger.initialize(args.state_dir)
        elif args.action == "serve":
            serve(args)
        else:
            if args.socket is None:
                parser.error("--socket is required")
            data = {"action": args.action}
            if args.action != "status":
                data.update(node=args.node, expected=args.expected)
            if args.action in {"approve", "rotate"}:
                with args.leaf.open("rb") as stream:
                    data.update(machine=args.machine, leaf=stream.read(ADMIN_LIMIT).decode("ascii"))
            result = command(args.socket, data)
            print(json.dumps(result))
            if result.get("ok") is not True:
                raise SystemExit(1)
    except (OSError, ValueError, RuntimeError, sqlite3.Error):
        parser.exit(1, "Enrollment operation failed\n")


if __name__ == "__main__":
    main()
