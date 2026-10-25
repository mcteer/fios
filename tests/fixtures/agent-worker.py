"""Fault simulator for supervisor tests only. No model/network calls."""
import json
import os
import signal
import sys
import time

mode = sys.argv[1] if len(sys.argv) > 1 else "normal"
if mode == "startup_exit":
    sys.exit(1)
if mode == "hang_start":
    time.sleep(60)
if mode == "wrong_version":
    print('{"v":1,"type":"ready"}', flush=True)
    time.sleep(60)
if mode == "oversized":
    print("x" * (1024 * 1024 + 1), flush=True)
    time.sleep(60)
if mode == "stderr":
    print("SENSITIVE_TEST_MARKER", file=sys.stderr, flush=True)
print('{"v":2,"type":"ready"}', flush=True)
for line in sys.stdin:
    frame = json.loads(line)
    if frame["type"] == "shutdown":
        break
    if frame["type"] == "run":
        run_id = frame["run_id"]
        if mode == "exit_run":
            sys.exit(1)
        if mode == "mismatch":
            run_id = "00000000-0000-4000-8000-000000000000"
        if mode == "wedged":
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            time.sleep(60)
        print(json.dumps({"v": 2, "type": "started", "run_id": run_id}), flush=True)
        if mode == "wait_cancel":
            continue
        print(json.dumps({"v": 2, "type": "delta", "run_id": run_id, "content": "hello 🧵"}), flush=True)
        print(json.dumps({"v": 2, "type": "done", "run_id": run_id, "status": "complete"}), flush=True)
    elif frame["type"] == "cancel":
        print(json.dumps({"v": 2, "type": "done", "run_id": frame["run_id"], "status": "interrupted"}), flush=True)
