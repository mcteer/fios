"""Local operator CLI and the native enrollment service."""

import argparse
from contextlib import ExitStack
import ctypes
import json
import os
import re
from pathlib import Path
import signal
import socket
import sqlite3
import stat
import struct
import sys
import threading
import time

from .enrollment import Ledger, Rejected, STUDIOS
from .heartbeat import Listener, json_object, snapshot_handler, worker_handler
from . import job_protocol
from .job_ledger import JobLedger
from .machine_tls import context, management_address, verified_worker_leaf
from .wire import read_until, timeout
from .scheduler import Scheduler

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


def admin_handler(ledger, openssl, ca, operator, scheduler=None):
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
            elif isinstance(action, str) and action in job_protocol.OPERATOR_FIELDS:
                result = job_protocol.operator(scheduler, action, data)
            elif action == "model-record":
                if scheduler is None or scheduler.catalog is None:
                    raise Rejected("scheduling_unavailable", 503)
                if (data.keys() != {"action", "profile", "evidence"}
                        or not isinstance(data["evidence"], dict)
                        or data["evidence"].get("synthetic") is not False):
                    raise Rejected("invalid_evidence")
                from .model_catalog import Profile
                profile = Profile.parse(data["profile"])
                scheduler.catalog.record(profile, data["evidence"])
                scheduler.sweep()
                result = {"revision": profile.revision}
            elif action in ("model-status", "model-trial", "model-promote", "model-withdraw"):
                if scheduler is None or scheduler.catalog is None:
                    raise Rejected("scheduling_unavailable", 503)
                expected = {
                    "model-status": {"action"},
                    "model-trial": {"action", "revision", "slot"},
                    "model-promote": {"action", "alias", "expected", "revision"},
                    "model-withdraw": {"action", "alias", "expected"},
                }[action]
                if data.keys() != expected:
                    raise Rejected("invalid")
                if action in ("model-status", "model-trial"):
                    with scheduler.jobs.transaction(write=False) as db:
                        if action == "model-status":
                            result = {"aliases": scheduler.catalog.inspect(db)}
                        else:
                            result = {"trial": scheduler.catalog.latest_trial(db, data["revision"], data["slot"])}
                else:
                    scheduler.catalog.change(data["alias"], data["expected"], data.get("revision"))
                    scheduler.sweep()
                    result = {}
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
            if error.reason == "queue_full":
                response["retry_after"] = 5
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
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    if args.inference_key and (args.synthetic_scheduling or not args.policy_port
                               or not re.fullmatch(r"[a-f0-9]{64}", args.policy_revision or "")):
        raise ValueError("Inference requires a pinned policy endpoint and its own scheduler mode")
    if (args.policy_port is not None or args.policy_revision is not None) and not args.inference_key:
        raise ValueError("A policy endpoint requires inference configuration")
    if bool(args.chat_bridge_key) != bool(args.chat_bridge_port) or (
            args.chat_bridge_key and not args.inference_key):
        raise ValueError("The chat bridge requires an explicit key, port and inference configuration")
    with ExitStack() as stack:
        stack.enter_context(job_protocol.service_lock(directory))
        scheduler = None
        local_worker = None
        chat_bridge = None
        if args.inference_key:
            from agent.text_policy import LoopbackPolicy
            from .chat_dispatch import Dispatch
            from .conversations import ConversationStore
            from .enrollment import private_path
            from .model_catalog import Catalog
            from .native_chat import browser_handler, local_handler

            private_path(args.inference_key)
            with args.inference_key.open("rb") as key_file:
                key = key_file.read(33)
            if len(key) != 32:
                raise ValueError("Inference key must contain 32 random bytes")
            jobs = JobLedger(directory / "jobs.sqlite")
            with jobs.transaction(write=False) as db:
                if db.execute("PRAGMA user_version").fetchone()[0] != 2:
                    raise ValueError("Migrate the job ledger before enabling inference")
            catalog = Catalog(jobs)
            scheduler = Scheduler(jobs, ledger, catalog=catalog)
            store = ConversationStore(jobs, key, catalog=catalog)
            scheduler.dispatch = Dispatch(scheduler, store, LoopbackPolicy(args.policy_port),
                                          policy_revision=args.policy_revision)

            def verify_peer(conn):
                if peer_uid(conn) != os.geteuid():
                    raise Rejected("identity", 403)

            path = directory / "inference.sock"
            if path.exists() or path.is_symlink():
                if not stat.S_ISSOCK(path.lstat().st_mode):
                    raise ValueError("Unexpected Mini worker socket path")
                path.unlink()
            local_worker = Listener(str(path), local_handler(scheduler, verify_peer), capacity=4,
                                    family=socket.AF_UNIX)
            stack.callback(path.unlink, missing_ok=True)
            stack.callback(local_worker.close)
            path.chmod(0o600)
            if args.chat_bridge_key:
                private_path(args.chat_bridge_key)
                with args.chat_bridge_key.open("rb") as key_file:
                    bridge_secret = key_file.read(33)
                if len(bridge_secret) != 32 or bridge_secret == key:
                    raise ValueError("Use an independent 32-byte chat bridge key")
                from .inventory import read_node

                def inventory():
                    mini = read_node(args.chat_observations, "fios-core", int(ledger.wall()))
                    nodes = {"fios-core": mini, **ledger.snapshot()}
                    return {node: {key: record[key] for key in ("state", "observation")}
                            for node, record in nodes.items()}

                chat_bridge = Listener(("127.0.0.1", args.chat_bridge_port),
                                       browser_handler(scheduler, bridge_secret, inventory), capacity=8)
                stack.callback(chat_bridge.close)
        if args.synthetic_scheduling:
            if not args.test_loopback:
                raise ValueError("Synthetic scheduling requires loopback")
            try:
                scheduler = Scheduler(JobLedger(directory / "jobs.sqlite"), ledger)
            except (OSError, ValueError, sqlite3.Error):
                print("scheduling unavailable", file=sys.stderr, flush=True)
        if endpoint.exists() or endpoint.is_symlink():
            if not stat.S_ISSOCK(endpoint.lstat().st_mode):
                raise ValueError("Unexpected operator socket path")
            endpoint.unlink()
        admin = Listener(str(endpoint), admin_handler(ledger, args.openssl, args.ca, os.geteuid(),
                                                     scheduler),
                         capacity=1, family=socket.AF_UNIX)
        stack.callback(endpoint.unlink, missing_ok=True)
        stack.callback(admin.close)
        endpoint.chmod(0o600)
        workers = Listener((address, args.worker_port), worker_handler(ledger, tls, scheduler),
                           per_peer=3, overload=lambda: ledger.count("overload"))
        stack.callback(workers.close)
        readings = Listener(("127.0.0.1", args.snapshot_port),
                            snapshot_handler(ledger, lambda: readings.address[1]), capacity=4)
        stack.callback(readings.close)
        listeners = (admin, readings, workers) + tuple(
            listener for listener in (local_worker, chat_bridge) if listener is not None)
        for listener in listeners:
            listener.start()
        print(json.dumps({"worker_port": workers.address[1], "snapshot_port": readings.address[1]}),
              flush=True)
        next_sweep = time.monotonic()
        while not stopping.wait(0.25):
            if not all(listener.thread.is_alive() for listener in listeners):
                raise RuntimeError("A native listener stopped")
            if scheduler and time.monotonic() >= next_sweep:
                next_sweep = time.monotonic() + 1
                try:
                    scheduler.sweep()
                except sqlite3.Error:
                    # Requests also sweep and cannot grant work while storage fails.
                    ledger.count("job_store")


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
            p.add_argument("--synthetic-scheduling", action="store_true")
            p.add_argument("--inference-key", type=Path)
            p.add_argument("--policy-port", type=int)
            p.add_argument("--policy-revision")
            p.add_argument("--chat-bridge-key", type=Path)
            p.add_argument("--chat-bridge-port", type=int)
            p.add_argument("--chat-observations", type=Path, default=Path(".fios/observations"))
    sub.add_parser("status")
    sub.add_parser("model-status")
    trial = sub.add_parser("model-trial")
    trial.add_argument("revision")
    trial.add_argument("slot", choices=("fios-core", *STUDIOS))
    sub.add_parser("model-record").add_argument("report", type=Path)
    for action in ("model-promote", "model-withdraw"):
        p = sub.add_parser(action)
        p.add_argument("alias", choices=("general-chat", "coding"))
        p.add_argument("--expected", required=action == "model-withdraw")
        if action == "model-promote":
            p.add_argument("revision")
    for name in ("approve", "rotate", "revoke"):
        p = sub.add_parser(name)
        p.add_argument("node", choices=STUDIOS)
        p.add_argument("--expected", required=name != "approve")
        if name != "revoke":
            p.add_argument("--machine", required=True)
            p.add_argument("--leaf", type=Path, required=True)
    job_protocol.cli(sub)
    args = parser.parse_args()
    try:
        if args.action == "init":
            Ledger.initialize(args.state_dir)
        elif args.action == "serve":
            serve(args)
        elif args.action in ("job-init", "job-migrate", "job-backup", "job-restore"):
            job_protocol.offline(args)
        else:
            if args.socket is None:
                parser.error("--socket is required")
            data = {"action": args.action}
            if args.action in job_protocol.OPERATOR_FIELDS:
                data.update({key: getattr(args, key) for key in job_protocol.OPERATOR_FIELDS[args.action]})
            elif args.action == "model-record":
                with args.report.open("rb") as report_file:
                    report = json_object(report_file.read(ADMIN_LIMIT))
                if report.keys() != {"profile", "evidence"}:
                    raise ValueError("Invalid qualification report")
                data.update(report)
            elif args.action == "model-trial":
                data.update(revision=args.revision, slot=args.slot)
            elif args.action in ("model-promote", "model-withdraw"):
                data.update(alias=args.alias, expected=args.expected)
                if args.action == "model-promote":
                    data["revision"] = args.revision
            elif args.action in ("approve", "rotate", "revoke"):
                data.update(node=args.node, expected=args.expected)
            if args.action in {"approve", "rotate"}:
                with args.leaf.open("rb") as stream:
                    data.update(machine=args.machine, leaf=stream.read(ADMIN_LIMIT).decode("ascii"))
            result = command(args.socket, data)
            print(json.dumps(result))
            if result.get("ok") is not True:
                raise SystemExit(1)
    except OSError as error:
        parser.exit(1, f"Enrollment operation failed (OS error {error.errno})\n")
    except (ValueError, RuntimeError, sqlite3.Error):
        parser.exit(1, "Enrollment operation failed\n")


if __name__ == "__main__":
    main()
