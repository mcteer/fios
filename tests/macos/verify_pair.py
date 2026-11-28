"""Exercise the admin socket and two independent trial worker processes on the Mini."""

import argparse
from contextlib import ExitStack
import json
import os
from pathlib import Path
from urllib.request import urlopen
import secrets
import subprocess
import sys
import tempfile

from backend.enrollment import STUDIOS
from enrollment_fixtures import OPENSSL, Signer
from verify_enrollment import run as command_output, wait_for
from verify_scheduling import ENROLL, ROOT, preview, process, read
from verify_supervision import Jobs

CANDIDATE = "a" * 64
DEVICES = dict(zip(STUDIOS, ("b" * 64, "c" * 64), strict=True))


def check_management(directory, observations):
    name = "fios-pair-management-" + secrets.token_hex(6)
    docker = ("/usr/local/bin/docker", "--context", "orbstack")
    env = dict(os.environ, FIOS_INVENTORY_ID="fios-core",
               FIOS_OBSERVATIONS_DIR=str(observations))
    override = directory / "management.json"
    override.write_text(json.dumps({"services": {"agent": {"image": name}}}))
    compose = (*docker, "compose", "-p", name, "-f", ROOT / "compose.management.yaml",
               "-f", override)

    def reporting():
        with urlopen("http://127.0.0.1:8745/v1/host", timeout=2) as response:
            host = json.load(response)["host"]
        return host["id"] == "fios-core" and host["state"] == "reporting"

    try:
        command_output(*compose, "up", "--build", "--detach", env=env, limit=90)
        wait_for(reporting, "management agent reports native observations", seconds=20)
        command_output(*compose, "restart", "agent", env=env)
        wait_for(reporting, "management agent reports after replacement", seconds=20)
    finally:
        command_output(*compose, "down", env=env, limit=30)
        if command_output(*docker, "image", "inspect", name, check=False).returncode == 0:
            command_output(*docker, "image", "rm", name)


def check_supervisor(directory, *, outage):
    prefix = "local.fios.pair." + secrets.token_hex(6)
    jobs = Jobs(directory, prefix, ROOT / "src")
    output = directory / f"{prefix}.supervisor.stdout"
    observations = directory / "observations"
    with jobs.job("supervisor", [
        sys.executable, "-B", "-m", "backend.host_agent", "--node", "fios-core",
        "--directory", observations, "--watch", "--recover-orbstack",
    ]):
        wait_for(lambda: output.exists() and "OrbStack dependency ready" in output.read_text(),
                 "native supervisor sees OrbStack and Docker ready")
        assert (observations / "fios-core.json").is_file()
        check_management(directory, observations)
        if not outage:
            return
        orb = "/usr/local/bin/orb"
        docker = ("/usr/local/bin/docker", "--context", "orbstack")
        if command_output(orb, "list").stdout.strip() or command_output(
                *docker, "ps", "--format", "{{.Names}}").stdout.splitlines() != ["fios-core-1"]:
            raise RuntimeError("Live rehearsal expects the development preview as the only workload")
        try:
            command_output(orb, "stop", limit=40)
            wait_for(lambda: "OrbStack dependency starting" in output.read_text(),
                     "supervisor observed and restarted OrbStack", seconds=35)
            wait_for(lambda: output.read_text().count("OrbStack dependency ready") >= 2,
                     "supervisor verified Docker recovery", seconds=35)
        finally:
            # Restore the same preview container even if the assertions fail.
            command_output(orb, "start", limit=35)
            command_output(*docker, "start", "fios-core-1", limit=20)
            wait_for(lambda: preview() is None, "preview returns after OrbStack recovery", seconds=25)
        print("Live OrbStack stop, native recovery and preview restoration passed.", flush=True)


def run(directory):
    signer = Signer(directory, "pair")
    cert, key = signer.issue("fios-core", server=True)
    leaves = {slot: signer.issue(slot) for slot in STUDIOS}
    state = directory / "state"
    inference_key = directory / "inference.key"
    inference_key.touch(mode=0o600)
    inference_key.write_bytes(b"I" * 32)
    recipes = directory / "recipes.json"
    recipes.touch(mode=0o600)
    recipes.write_text(json.dumps({"native-fixture": dict(
        candidate=CANDIDATE, fixture="d" * 64, engine="mlx-lm", devices=DEVICES,
        budgets={slot: dict(ceiling=2**28, floor=2**27) for slot in STUDIOS},
        tokens=20, deadline=60)}))
    for action in ("init", "job-init", "job-migrate"):
        subprocess.run([*ENROLL, action, "--state-dir", state], check=True, timeout=5)

    def command(action, *args):
        reply = subprocess.run([*ENROLL, "--socket", state / "operator.sock", action, *args],
                               capture_output=True, text=True, timeout=5, check=True)
        return json.loads(reply.stdout)

    def start(stack):
        service = stack.enter_context(process([
            *ENROLL, "serve", "--state-dir", state, "--bind", "127.0.0.1",
            "--ca", signer.ca, "--cert", cert, "--key", key, "--openssl", OPENSSL,
            "--test-loopback", "--worker-port", "0", "--snapshot-port", "0",
            "--inference-key", inference_key, "--policy-port", "1", "--policy-revision", "e" * 64,
            "--pair-trials", recipes,
        ]))
        return read(service)["worker_port"]

    def client(stack, port, slot):
        child = stack.enter_context(process([
            sys.executable, "-B", ROOT / "tests/fixtures/scheduling_worker.py",
            slot, str(port), signer.ca, *leaves[slot], "--pair",
        ]))

        def invoke(action, **fields):
            child.stdin.write(json.dumps([action, fields]) + "\n")
            child.stdin.flush()
            response = read(child)
            assert response.get("status") == 200, (slot, action, response)
            return response

        return invoke

    with ExitStack() as stack:
        port = start(stack)
        for slot in STUDIOS:
            command("approve", slot, "--machine", slot, "--leaf", leaves[slot][0])
        a, b = [client(stack, port, slot) for slot in STUDIOS]
        a("sample")
        incarnation = command("job-context")["incarnation"]
        args = ("--incarnation", incarnation, "--key", "first", "--candidate", CANDIDATE,
                "--recipe", "native-fixture")
        job = command("pair-trial-submit", *args)["job"]["id"]
        assert command("pair-trial-submit", *args)["job"]["id"] == job
        assert a("poll")["action"] == "wait"
        b("sample")
        assert a("poll")["job"] == b("poll")["job"] == job
        a("ready")
        assert a("poll")["action"] == "prepare"
        b("ready")
        assert a("poll")["action"] == b("poll")["action"] == "start"
        command("pair-trial-cancel", job)
        a("cleanup")
        result = command("pair-trial-inspect", job)["job"]
        assert result["state"] == "stopping" and result["slots"] == [STUDIOS[1]]
        b("cleanup")
        result = command("pair-trial-inspect", job)["job"]
        assert result["state"] == "cancelled" and result["slots"] == [] and result["usage"] is None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outage", action="store_true")
    args = parser.parse_args()
    preview()
    with tempfile.TemporaryDirectory(prefix="fios-pair-acceptance-") as folder:
        directory = Path(folder)
        check_supervisor(directory, outage=args.outage)
        run(directory)
    preview()
    print("Native supervisor readiness, admin and two mTLS trial workers passed. Existing preview is healthy.")
