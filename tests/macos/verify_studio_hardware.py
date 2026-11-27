"""Qualify one staged Studio through an isolated private-LAN enrollment."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
import json
import os
from pathlib import Path
import shlex
import socket
import ssl
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen

from agent.native_runtime import NativeRuntime, digest_file
from agent.text_policy import LoopbackPolicy
from backend.chat_dispatch import Dispatch
from backend.conversations import ConversationStore
from backend.enrollment import Ledger
from backend.heartbeat import Listener, worker_handler
from backend.job_ledger import JobLedger
from backend.machine_tls import context, fingerprint, management_address
from backend.model_catalog import Catalog, Profile
from backend.scheduler import Scheduler
from enrollment_fixtures import Signer
from fixtures import chat_coding
from fixtures.chat_coding import TASKS, evaluate

STUDIO = "studio-a"
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
       "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15"]


def remote(host, *argv, data=None, timeout=30):
    run = subprocess.run([*SSH, host, shlex.join(map(str, argv))], input=data,
                         capture_output=True, check=True, timeout=timeout)
    return run.stdout


def remote_python(args, *argv, data=None, timeout=30):
    root = args.remote_root
    try:
        return remote(args.host, "/usr/bin/env", f"PYTHONPATH={root}/src",
                      f"{root}/venv/bin/python", "-B", f"{root}/tests/macos/studio_trial_worker.py",
                      *argv, data=data, timeout=timeout)
    except subprocess.CalledProcessError as error:
        # Forward only the worker's typed reasons. Generic tracebacks may contain
        # local path details or unexpected upstream diagnostics.
        detail = error.stderr.strip().removeprefix(b"Trial rejected: ")
        if detail != error.stderr.strip() and detail.replace(b"_", b"").isalnum() and len(detail) <= 64:
            raise RuntimeError(f"Studio {argv[0]} failed: {detail.decode('ascii')}") from None
        raise


def stage_source(args):
    archive = subprocess.check_output(
        ["/usr/bin/tar", "--exclude=__pycache__", "-cf", "-", "src/agent", "src/backend",
         "tests/macos/studio_trial_worker.py"], timeout=15)
    remote(args.host, "/usr/bin/tar", "-xf", "-", "-C", args.remote_root, data=archive)


def issue_remote(args, root, signer):
    csr = remote_python(args, "csr", args.remote_root)
    path = root / "worker.csr"
    path.write_bytes(csr)
    extensions = root / "worker.ext"
    extensions.write_text("basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n"
                          "extendedKeyUsage=clientAuth\nsubjectAltName=DNS:edge-a\n"
                          "subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid\n")
    certificate = root / "worker.crt"
    signer.run("x509", "-req", "-in", path, "-CA", signer.ca, "-CAkey", signer.path("ca.key"),
               "-CAcreateserial", "-days", "1", "-extfile", extensions, "-out", certificate)
    return certificate


def check_enrollment(args, root):
    stage_source(args)
    path = root / "state"
    Ledger.initialize(path)
    ledger = Ledger(path)
    signer = Signer(root, "studio-probe")
    server, key = signer.issue("fios-core", server=True)
    leaf = issue_remote(args, root, signer)
    ledger.change("approve", STUDIO, None, machine="edge-a",
                  pin=fingerprint(ssl.PEM_cert_to_DER_cert(leaf.read_text())))
    listener = Listener((args.bind, 0), worker_handler(
        ledger, context(signer.ca, server, key, server=True))).start()
    try:
        configuration = {"ca": signer.ca.read_text(), "leaf": leaf.read_text(),
                         "address": args.bind, "port": listener.address[1]}
        remote_python(args, "probe", args.remote_root, data=json.dumps(configuration).encode())
        row = ledger.snapshot()[STUDIO]
        if row["state"] != "reporting" or row["observation"]["memory_bytes"] != 274877906944:
            raise RuntimeError("Studio did not report expected native telemetry over mutual TLS")
        print("Studio A passed disposable private-LAN mutual TLS enrollment and heartbeat.", flush=True)
    finally:
        listener.close()


def preview():
    with urlopen("http://127.0.0.1:8741/healthz", timeout=2) as health:
        return health.read()


def start_policy(config, resources):
    runtime = NativeRuntime(config, config.parent, purpose="policy")
    with socket.socket() as candidate:
        candidate.bind(("127.0.0.1", 0))
        port = candidate.getsockname()[1]
    process = subprocess.Popen(
        [sys.executable, "-B", "-m", "agent.policy_worker", "--config", str(config),
         "--state", str(config.parent), "--port", str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def shutdown():
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=6)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)

    resources.callback(shutdown)
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline and process.poll() is None:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return runtime.revision, LoopbackPolicy(port)
        except OSError:
            time.sleep(0.1)
    raise RuntimeError("Mini publication service did not start")


def qualify(args, root, resources):
    if preview() != b"ok\n":
        raise RuntimeError("Existing Mini preview is unavailable")
    stage_source(args)
    metadata = json.loads(remote_python(args, "inspect", args.remote_root, timeout=40))
    policy, checker = start_policy(args.policy_config, resources)
    manifest = dict(alias="coding", host_class="m3-ultra-studio", artifact=metadata["artifact"],
                    engine=metadata["engine"], template=metadata["template"], policy=policy,
                    evaluation=digest_file(Path(chat_coding.__file__)),
                    license="Qwen Community License 1.0", context=8192, output=1024,
                    settings={"temperature": 0})
    profile = Profile.parse(manifest)
    state = root / "state"
    Ledger.initialize(state)
    ledger = Ledger(state)
    JobLedger.initialize(state / "jobs.sqlite")
    jobs = JobLedger(state / "jobs.sqlite")
    jobs.migrate()
    catalog = Catalog(jobs, synthetic=True)
    store = ConversationStore(jobs, os.urandom(32), catalog=catalog)
    scheduler = Scheduler(jobs, ledger, catalog=catalog)
    # This private trial grants only its fixed, harmless coding fixtures. The
    # resulting evidence is scoped to runtime and transport qualification.
    scheduler.dispatch = Dispatch(scheduler, store, checker, policy_revision=policy)
    catalog.record(profile, dict(slot=STUDIO, peak_bytes=args.trial_budget, passed=True, synthetic=True))
    catalog.change("coding", None, profile.revision, synthetic=True)
    signer = Signer(root, "studio-trial")
    cert, key = signer.issue("fios-core", server=True)
    leaf = issue_remote(args, root, signer)
    ledger.change("approve", STUDIO, None, machine="edge-a",
                  pin=fingerprint(ssl.PEM_cert_to_DER_cert(leaf.read_text())))
    identifiers = []
    for idx, task in enumerate(TASKS, start=1):
        cid = store.create("operator", f"fixture-{idx}")
        tx = store.submit("operator", cid, jobs.context(), f"analysis-{idx}", None,
                          "coding", task.prompt, False, deadline=600)
        identifiers.append((task, cid, tx["job"]))

    stop_conversation = store.create("operator", "cancel-trial")
    stop_turn = store.submit("operator", stop_conversation, jobs.context(), "cancel-turn", None,
                             "coding", "List consecutive integers from one to one thousand.", False,
                             deadline=600)
    stop_job = stop_turn["job"]

    with ExitStack() as listeners:
        listener = Listener((args.bind, 0), worker_handler(
            ledger, context(signer.ca, cert, key, server=True), scheduler), per_peer=3)
        listeners.callback(listener.close)
        listener.start()
        configuration = {"profile": manifest, "ca": signer.ca.read_text(),
                         "leaf": leaf.read_text(), "address": args.bind,
                         "port": listener.address[1], "jobs": len(identifiers) + 1,
                         "budget": args.trial_budget}
        with ThreadPoolExecutor(max_workers=1) as task_runner:
            run = task_runner.submit(remote_python, args, "run", args.remote_root,
                                     data=json.dumps(configuration).encode(), timeout=420)
            cancelled_at = None
            while not run.done():
                scheduler.sweep()
                job = jobs.get("operator", stop_job)
                if job["state"] == "running" and cancelled_at is None:
                    try:
                        marker = remote(args.host, "/bin/cat",
                                        args.remote_root / "trial-inference-started", timeout=5)
                    except subprocess.CalledProcessError:
                        marker = b""
                    if marker == b"3":
                        cancelled_at = time.monotonic()
                        scheduler.cancel("operator", stop_job)
                if cancelled_at and job["state"] == "cancelled":
                    break
                time.sleep(0.5)
            report = json.loads(run.result())
        scheduler.sweep()
        cancelled = jobs.get("operator", stop_job)
        stopped_turn = store.read("operator", stop_conversation, policy)["turns"][0]
        cancelled_and_clean = (cancelled_at is not None and cancelled["state"] == "cancelled"
                               and not cancelled["slots"] and not stopped_turn["answer"])
        cancellation = {"passed": cancelled_and_clean,
                        "elapsed_seconds": round(time.monotonic()-cancelled_at, 3) if cancelled_at else None,
                        "state": cancelled["state"]}
        results = []
        for task, cid, job in identifiers:
            state = jobs.get("operator", job)
            turn = store.read("operator", cid, manifest["policy"])["turns"][0]
            results.append({"state": state["state"], "reason": state["reason"],
                            "correct": evaluate(task, turn["answer"]), "cleanup": not state["slots"],
                            "fenced_sql": turn["answer"].lstrip().startswith("```"),
                            "usage": state["usage"]})
        # Record redacted evidence rather than publishing candidate contents.
        result = {"runtime": report, "coding": results, "cancellation": cancellation}
        print(json.dumps(result, indent=2), flush=True)
        if not all(item["state"] == "succeeded" and item["correct"] and item["cleanup"] for item in results):
            raise RuntimeError("Studio coding trial failed a required check")
        if not cancelled_and_clean:
            raise RuntimeError("Studio did not pass cancellation and cleanup")
        if len(report["runs"]) != 3 or any(not 0 < item["peak_bytes"] < args.trial_budget
                                            for item in report["runs"][:2]):
            raise RuntimeError("Studio memory measurement failed")
    benchmark = json.loads(remote_python(args, "benchmark", args.remote_root, timeout=450,
                                         data=json.dumps({"budget": args.trial_budget,
                                                          "context": manifest["context"],
                                                          "output": manifest["output"]}).encode()))
    print(json.dumps({"native_context_benchmark": benchmark, "profile": manifest}, indent=2), flush=True)
    observations = benchmark["observations"]
    if (len(observations) != 6 or not benchmark["clean"]
            or any(not item["correct"] or item["decode_tokens_per_second"] is None
                   or item["first_text_seconds"] > (120 if index == 0 else 45)
                   for index, item in enumerate(observations))):
        raise RuntimeError("Studio cold/warm qualification failed")
    if preview() != b"ok\n":
        raise RuntimeError("Existing Mini preview failed its final health check")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--remote-root", type=Path, required=True)
    parser.add_argument("--bind", type=management_address, required=True)
    parser.add_argument("--trial-budget", type=int, default=180_000_000_000)
    parser.add_argument("--enrollment-only", action="store_true")
    parser.add_argument("--policy-config", type=Path)
    args = parser.parse_args()
    if (args.host != "mcteer@fios-edge-a.local" or args.remote_root.parent != Path("/tmp")
            or not args.remote_root.name.startswith("fios-studio-trial.")):
        parser.error("This trial requires the approved Studio and dedicated staging path")
    if not args.enrollment_only and args.policy_config is None:
        parser.error("The hardware trial requires the attested native publication checker")
    with tempfile.TemporaryDirectory(prefix="fios-studio-core-") as folder, ExitStack() as resources:
        if args.enrollment_only:
            check_enrollment(args, Path(folder))
        else:
            qualify(args, Path(folder), resources)


if __name__ == "__main__":
    main()
