"""Isolated launchd-to-OrbStack qualification on fios-core."""

from contextlib import ExitStack
from hashlib import sha256
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.request import urlopen
from uuid import uuid4

from backend.enroll import command
from backend.machine_tls import fingerprint
from enrollment_fixtures import OPENSSL, Signer
from verify_supervision import Jobs


def wait_for(check, description, seconds=10):
    stop = time.monotonic() + seconds
    while time.monotonic() < stop:
        try:
            result = check()
        except (OSError, URLError, ValueError):
            result = None
        if result:
            return result
        time.sleep(0.1)
    raise RuntimeError(f"Timed out waiting for {description}")


def run(*args, env=None, limit=20, check=True):
    return subprocess.run(args, env=env, timeout=limit, check=check,
                          capture_output=True, text=True)


def get(port, path="/healthz"):
    with urlopen(f"http://127.0.0.1:{port}{path}", timeout=1) as response:
        return response.read()


def ports():
    with ExitStack() as stack:
        listeners = [stack.enter_context(socket.socket()) for _ in range(3)]
        for listener in listeners:
            listener.bind(("127.0.0.1", 0))
        return [listener.getsockname()[1] for listener in listeners]


def verify(root):
    import ssl

    if sys.platform != "darwin" or socket.gethostname().split(".")[0] != "fios-core":
        raise RuntimeError("Run qualification on fios-core")
    assert get(8741) == b"ok\n"
    name = f"fios-acceptance-{uuid4().hex[:10]}"
    deploy = root / "src"
    digest = sha256()
    for package in ("backend", "frontend"):
        shutil.copytree(Path("src") / package, deploy / package,
                        ignore=shutil.ignore_patterns("__pycache__"))
    for path in sorted(p for p in deploy.rglob("*") if p.is_file()):
        digest.update(str(path.relative_to(deploy)).encode() + b"\0")
        digest.update(sha256(path.read_bytes()).digest())
    print(f"Native source SHA-256 {digest.hexdigest()}", flush=True)

    env = dict(os.environ, PYTHONPATH=str(deploy))
    python = [sys.executable, "-B", "-m"]
    state, observations = root / "state", root / "observations"
    enroll = [*python, "backend.enroll"]
    agent = [*python, "backend.host_agent"]
    run(*enroll, "init", "--state-dir", state, env=env)
    run(*agent, "--node", "fios-core", "--directory", observations, env=env)
    signer = Signer(root, "preview-test")
    cert, key = signer.issue("fios-core", server=True)
    a, b = signer.issue("edge-a"), signer.issue("edge-b")
    replacement = signer.issue("edge-a-new", san="DNS:edge-a")
    worker_port, snapshot_port, ui_port = ports()
    jobs = Jobs(root, f"local.{name}", deploy)
    service = [*enroll, "serve", "--state-dir", state, "--test-loopback",
               "--bind", "127.0.0.1", "--worker-port", worker_port, "--snapshot-port", snapshot_port,
               "--ca", signer.ca, "--cert", cert, "--key", key, "--openssl", OPENSSL]

    def admin(*args):
        result = run(*enroll, "--socket", state / "operator.sock", *args, env=env)
        return json.loads(result.stdout)

    def ready():
        return command(state / "operator.sock", {"action": "status"})["ok"]

    def worker(node, leaf):
        return [*agent, "--node", node, "--remote", "127.0.0.1", "--server-name", "fios-core",
                "--test-loopback", "--port", worker_port, "--ca", signer.ca,
                "--cert", leaf[0], "--key", leaf[1]]

    def pin(leaf):
        return fingerprint(ssl.PEM_cert_to_DER_cert(leaf[0].read_text()))

    def inventory():
        return {host["id"]: host for host in json.loads(get(ui_port, "/api/v1/cluster"))["nodes"]}

    def sample(node, after=0):
        row = inventory()[node]
        if row["state"] == "reporting" and row["observation"]["sampled_at"] > after:
            return row["observation"]

    override = root / "compose.json"
    override.write_text(json.dumps({"services": {"core": {
        "image": name,
        "command": ["python", "-B", "-m", "backend.core", "--directory", "/observations",
                    "--port", str(ui_port), "--snapshot-port", str(snapshot_port)],
        "volumes": [{"type": "bind", "source": str(observations), "target": "/observations",
                     "read_only": True, "bind": {"create_host_path": False}}],
        "healthcheck": {"test": ["CMD", "python", "-Bc",
                        f"import urllib.request; urllib.request.urlopen('http://127.0.0.1:{ui_port}/healthz', timeout=2).read()"],
                        "interval": "2s"},
    }}}))
    docker = ["docker", "--context", "orbstack"]
    compose = [*docker, "compose", "-p", name, "-f", "compose.yaml", "-f", override]
    test_container = f"{name}-linux-tests"
    try:
        with ExitStack() as children:
            core_job = children.enter_context(ExitStack())
            core_job.enter_context(jobs.job("core", service))
            wait_for(ready, "native service")
            assert admin("approve", "studio-a", "--machine", "edge-a", "--leaf", a[0])["ok"]
            assert admin("approve", "studio-b", "--machine", "edge-b", "--leaf", b[0])["ok"]
            run(*compose, "up", "--build", "--wait", "--wait-timeout", "25", limit=90)
            assert sample("fios-core") and get(ui_port) == b"ok\n"
            linux = run(*docker, "run", "--rm", "--name", test_container,
                        "--network", "none", "--read-only",
                        "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                        "--workdir", "/src",
                        "--tmpfs", "/tmp:rw,noexec,nosuid,size=8m",
                        "--mount", f"type=bind,src={deploy},dst=/src,readonly",
                        "--mount", f"type=bind,src={Path('tests').resolve()},dst=/tests,readonly",
                        "-e", "PYTHONPATH=/src", name, "python", "-B", "-m", "unittest",
                        "discover", "-s", "/tests", "-p", "test_*enrollment*.py", limit=30)
            print("Linux test container:", " ".join(linux.stderr.strip().splitlines()[-3:]),
                  flush=True)
            first_worker = children.enter_context(ExitStack())
            started = time.monotonic()
            first_worker.enter_context(jobs.job("a", worker("studio-a", a)))
            children.enter_context(jobs.job("b", worker("studio-b", b)))
            first = wait_for(lambda: sample("studio-a") and sample("studio-b"), "both workers")
            initial_s = time.monotonic() - started
            assert first["memory_bytes"] > 0
            assert b"3 of 3 hosts reporting" in get(ui_port, "/")
            old = wait_for(lambda: jobs.pid("a"), "worker PID")
            previous = sample("studio-a")["sampled_at"]
            os.kill(old, signal.SIGKILL)
            new = wait_for(lambda: (pid := jobs.pid("a")) and pid != old and pid, "worker relaunch", 20)
            started = time.monotonic()
            updated = wait_for(lambda: sample("studio-a", previous), "restarted worker heartbeat")
            print(f"Both workers reporting in {initial_s:.2f}s. "
                  f"Worker PID {old} → {new}, fresh after {time.monotonic() - started:.2f}s "
                  f"({previous} → {updated['sampled_at']}).", flush=True)
            b_pid = wait_for(lambda: jobs.pid("b"), "second worker PID")
            core_job.close()
            assert inventory()["studio-a"]["enrollment"] == "unknown"
            assert sample("fios-core")
            first_worker.close()
            core_job.enter_context(jobs.job("core", service))
            wait_for(ready, "restarted native service")
            assert inventory()["studio-a"]["state"] == "awaiting"
            started = time.monotonic()
            wait_for(lambda: sample("studio-b"), "worker reconnect after core restart")
            assert jobs.pid("b") == b_pid
            print(f"Worker reconnected after core restart in {time.monotonic() - started:.2f}s "
                  f"with PID {b_pid} unchanged.", flush=True)
            assert admin("rotate", "studio-a", "--expected", pin(a), "--machine", "edge-a",
                         "--leaf", replacement[0])["ok"]
            with jobs.job("a", worker("studio-a", replacement)):
                wait_for(lambda: sample("studio-a"), "rotated worker heartbeat")
                assert admin("revoke", "studio-a", "--expected", pin(replacement))["ok"]
                assert inventory()["studio-a"]["enrollment"] == "revoked"
                wait_for(lambda: admin("status")["rejections"].get("identity"), "revocation denial")
                assert sample("studio-b")
                core_job.close()
                core_job.enter_context(jobs.job("core", service))
                wait_for(ready, "native service after revocation")
                assert inventory()["studio-a"]["enrollment"] == "revoked"
                wait_for(lambda: admin("status")["rejections"].get("identity"),
                         "revoked credential denied after restart")
                wait_for(lambda: sample("studio-b"), "unaffected worker recovery")
            print("Verified core restart, leaf rotation, durable revoke and independent worker recovery.",
                  flush=True)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        raise
    finally:
        try:
            if run(*docker, "container", "inspect", test_container, check=False).returncode == 0:
                run(*docker, "container", "rm", "-f", test_container)
            run(*compose, "down", "--remove-orphans", limit=30)
        finally:
            if run(*docker, "image", "inspect", name, check=False).returncode == 0:
                run(*docker, "image", "rm", name)
        assert not run(*compose, "ps", "-aq").stdout.strip()
        assert run(*docker, "image", "inspect", name, check=False).returncode != 0
        assert all(jobs.inspect(worker).returncode for worker in ("core", "a", "b"))
        assert get(8741) == b"ok\n"
        print("Verified test jobs, containers and image tag removed. Existing preview is healthy.",
              flush=True)


def interrupt(_signal, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupt)
    try:
        with tempfile.TemporaryDirectory(prefix="fios-", dir="/tmp") as directory:
            verify(Path(directory).resolve())
    except KeyboardInterrupt:
        raise SystemExit(130) from None
