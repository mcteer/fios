"""Qualify the opt-in native scheduler with two synthetic worker processes."""

from contextlib import ExitStack, contextmanager
import hashlib
import json
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen

from enrollment_fixtures import OPENSSL, Signer

ROOT = Path(__file__).resolve().parents[2]
ENROLL = [sys.executable, "-B", "-m", "backend.enroll"]


def preview():
    with urlopen("http://127.0.0.1:8741/healthz", timeout=3) as response:
        assert response.read() == b"ok\n"


def read(process):
    if not select.select([process.stdout], [], [], 8)[0]:
        raise TimeoutError("Synthetic process did not return a response")
    line = process.stdout.readline()
    if not line:
        raise RuntimeError(f"Synthetic process exited: {process.poll()}")
    return json.loads(line)


@contextmanager
def process(arguments):
    with subprocess.Popen(arguments, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          text=True, bufsize=1) as child:
        try:
            yield child
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)


def run(directory):
    signer = Signer(directory, "scheduling")
    cert, key = signer.issue("fios-core", server=True)
    state = directory / "state"
    backup = directory / "backup.sqlite"

    def offline(action, *args, success=True):
        result = subprocess.run([*ENROLL, action, "--state-dir", state, *args],
                                capture_output=True, text=True, timeout=5)
        assert (result.returncode == 0) == success, result.stderr

    def command(action, *args, success=True):
        result = subprocess.run([*ENROLL, "--socket", state / "operator.sock", action, *args],
                                capture_output=True, text=True, timeout=5)
        assert (result.returncode == 0) == success, (action, result.stdout, result.stderr)
        return json.loads(result.stdout)

    @contextmanager
    def service(*, scheduling=True):
        flags = ["--synthetic-scheduling"] if scheduling else []
        with process([*ENROLL, "serve", "--state-dir", state, "--bind", "127.0.0.1",
                      "--ca", signer.ca, "--cert", cert, "--key", key, "--openssl", OPENSSL,
                      "--test-loopback", "--worker-port", "0", "--snapshot-port", "0",
                      *flags]) as child:
            yield child, read(child)["worker_port"]

    def worker(stack, slot, port):
        child = stack.enter_context(process([sys.executable, "-B",
            ROOT / "tests/fixtures/scheduling_worker.py", slot, str(port), signer.ca, *leaves[slot]]))

        def invoke(operation, **fields):
            child.stdin.write(json.dumps([operation, fields]) + "\n")
            child.stdin.flush()
            return read(child)
        return invoke

    def submit(context, key, profile="single", deadline="60", success=True):
        reply = command("job-submit", "--incarnation", context, "--key", key,
                        "--profile", f"fake-{profile}-v1", "--tokens", "20",
                        "--deadline", deadline, success=success)
        return reply["job"]["id"] if success else reply["reason"]

    def get(job):
        return command("job-get", job)["job"]

    slots = ("studio-a", "studio-b")
    leaves = {slot: signer.issue(slot) for slot in slots}
    offline("init")
    with service() as (_, port), ExitStack() as stack:
        assert command("job-context", success=False)["reason"] == "scheduling_unavailable"
        assert command("status")["slots"] == dict.fromkeys(slots, "not_enrolled")
        for slot in slots:
            command("approve", slot, "--machine", slot, "--leaf", leaves[slot][0])
        assert worker(stack, slots[0], port)("sample")["status"] == 404
    offline("job-init")

    with service() as (_, port):
        incarnation = command("job-context")["incarnation"]
        queued = submit(incarnation, "present")
        offline("job-backup", "--target", backup, success=False)
    offline("job-backup", "--target", backup)

    with service() as (_, port), ExitStack() as stack:
        a, b = [worker(stack, slot, port) for slot in slots]
        for peer in (a, b):
            assert peer("sample")["status"] == 200
        print("Both synthetic workers authenticated and reporting capacity.", flush=True)
        assert submit(incarnation, "present") == queued
        assert a("poll")["action"] == "prepare"
        assert a("ready")["status"] == 200
        assert a("poll")["action"] == "start"
        assert a("renew")["status"] == 200
        counts = {"input": {"kind": "measured", "value": 10},
                  "output": {"kind": "estimated", "value": 4}}
        assert a("finish", result="ok", usage=counts)["status"] == 200
        assert a("finish", result="ok", usage=counts)["status"] == 200
        assert get(queued)["usage"]["cost"] == {
            "amount": "0.10", "currency": "USD", "tariff": "synthetic-v1",
            "unit": "token", "partial": True}
        assert a("cleanup")["status"] == 200

    with service() as (core, port), ExitStack() as stack:
        a, b = [worker(stack, slot, port) for slot in slots]
        for peer in (a,b):
            assert peer("sample")["status"] == 200
        lost = submit(incarnation, "absent", "pair")
        assert a("poll")["job"] == lost
        assert b("poll")["job"] == lost
        assert a("ready")["status"] == 200
        assert a("poll")["action"] == "prepare"
        assert b("ready")["status"] == 200
        assert a("poll")["action"] == "start"
        assert b("poll")["action"] == "start"
        assert b("finish", result="failed")["status"] == 200
        assert get(lost)["state"] == "stopping"
        assert a("cleanup")["status"] == b("cleanup")["status"] == 200
        assert get(lost)["state"] == "failed"
        hanging = submit(incarnation, "crash")
        old = a("poll")
        assert old["job"] == hanging
        core.kill()
        core.wait(timeout=5)

    with service() as (_, port), ExitStack() as stack:
        a = worker(stack, slots[0], port)
        assert a("sample")["status"] == 200
        reply = a("call", op="finish", result="ok",
                  **{k: old[k] for k in ("job", "grant", "generation", "epoch")})
        assert reply["reason"] == "fenced"
        assert get(hanging)["slots"] == [slots[0]]
        assert a("cleanup")["status"] == 200
        assert get(hanging)["state"] == "failed"
        cancelled = submit(incarnation, "cancel")
        assert a("poll")["job"] == cancelled
        assert a("ready")["status"] == 200
        assert a("poll")["action"] == "start"
        assert command("job-cancel", cancelled)["job"]["state"] == "stopping"
        assert a("cleanup")["status"] == 200
        assert get(cancelled)["state"] == "cancelled"
        recovered = submit(incarnation, "after-crash")
        assert a("poll")["job"] == recovered
        assert a("ready")["status"] == 200
        assert a("poll")["action"] == "start"
        assert a("finish", result="ok")["status"] == 200
        assert get(recovered)["state"] == "succeeded"
        assert get(recovered)["usage"]["cost"] is None
        assert a("cleanup")["status"] == 200
        for i in range(16):
            submit(incarnation, f"full-{i}")
        assert submit(incarnation, "overflow", success=False) == "queue_full"

    offline("job-restore", "--snapshot", backup)
    with service() as (_, port), ExitStack() as stack:
        restored = command("job-context")["incarnation"]
        peers = []
        for slot in slots:
            peer = worker(stack, slot, port)
            peers.append(peer)
            assert peer("sample")["status"] == 200
            assert peer("cleanup")["status"] == 200
            if slot == slots[0]:
                gated = submit(restored, "restore-gate")
                assert peer("poll")["action"] == "wait"
                assert get(gated)["reason"] == "restore_quarantine"
                command("job-cancel", gated)
        for previous_key in ("present", "absent"):
            assert submit(incarnation, previous_key, success=False) == "ledger_changed"
        assert get(queued)["reason"] == "restore_history_unknown"
        assert command("job-get", lost, success=False)["reason"] == "unknown_job"
        assert len(command("job-list")["jobs"]) == 2
        submit(restored, "fresh", deadline="4")
        peer = peers[0]
        assert peer("poll")["action"] == "prepare"
        assert peer("ready")["status"] == 200
        assert peer("poll")["action"] == "start"
        limit = time.monotonic() + 6
        while peer("state")["running"] and time.monotonic() < limit:
            time.sleep(0.1)
        assert not peer("state")["running"]
        assert peer("cleanup")["status"] == 200

    offline("job-restore", "--snapshot", backup)
    with service():
        assert command("job-context")["incarnation"] not in (incarnation, restored)
        assert submit(restored, "fresh", success=False) == "ledger_changed"
    with service(scheduling=False):
        assert command("status")["ok"]
        assert command("job-context", success=False)["reason"] == "scheduling_unavailable"


def main():
    if sys.platform != "darwin" or socket.gethostname().split(".")[0] != "fios-core":
        raise RuntimeError("Run qualification on fios-core")
    preview()
    digest = hashlib.sha256()
    for path in sorted((ROOT / "src/backend").glob("*.py")):
        digest.update(path.name.encode() + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    print("Scheduling source SHA-256", digest.hexdigest(), flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix="fios-sched-", dir="/tmp") as path:
            run(Path(path).resolve())
    finally:
        preview()
        assert not Path(path).exists()
        print("Removed synthetic processes and private run files. Existing preview is healthy.",
              flush=True)
    print("Native scheduling acceptance passed", flush=True)


def interrupt(_sig, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupt)
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130) from None
