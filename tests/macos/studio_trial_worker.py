"""Run the native candidate in one disposable Studio trial directory."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
from threading import Event, Thread
import time

from agent.inference import generate_text, monitor_trial
from agent.inference_worker import InferenceWorker
from agent.macos_memory import footprint, headroom
from agent.native_runtime import (NativeRuntime, digest_file, environment_root, manifest_digest,
                                  verify_environment)
from backend.enrollment import Rejected, private_path
from backend.host_agent import observe
from backend.machine_tls import context, management_address
from backend.model_catalog import Capacity, Profile, TrialBudget
from backend.worker import Reporter

OPENSSL = "/opt/homebrew/opt/openssl@4/bin/openssl"
NODE = "studio-a"


def private_write(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as out:
        out.write(data)
    private_path(path)


def csr(root):
    key = root / "trial-worker.key"
    if not key.exists():
        subprocess.run([OPENSSL, "genpkey", "-algorithm", "EC", "-pkeyopt",
                        "ec_paramgen_curve:prime256v1", "-out", key],
                       check=True, timeout=5, capture_output=True)
        key.chmod(0o600)
    private_path(key)
    run = subprocess.run([OPENSSL, "req", "-new", "-key", key, "-subj", "/CN=edge-a"],
                         check=True, timeout=5, capture_output=True)
    sys.stdout.buffer.write(run.stdout)


def inspect(root):
    engine = Path(sys.executable)
    site = environment_root(engine)
    environment = root / "engine-files.json"
    private_write(environment, json.dumps({p.relative_to(site).as_posix(): digest_file(p)
                                          for p in site.rglob("*") if p.is_file()}))
    bundle = verify_environment(engine, environment, "mlx_vlm.server", digest_file(engine))
    model = json.loads((root / "model-files.json").read_text())
    metadata = dict(artifact=manifest_digest(model), engine=bundle,
                    template=model.get("chat_template.jinja", model.get("tokenizer_config.json")))
    print(json.dumps(metadata))


class MeasuredRuntime(NativeRuntime):
    def __init__(self, path, root, memory, budget):
        super().__init__(path, root, purpose="inference")
        self.memory, self.budget, self.runs = memory, budget, []
        self.started = root / "trial-inference-started"

    def generate(self, *args, **kwargs):
        done = Event()
        peak = 0
        failure = None
        first_generated = None
        first_text = None
        runtime_failure = None

        def mark_generation():
            nonlocal first_generated
            first_generated = time.monotonic()
            private_write(self.started, str(len(self.runs) + 1))

        def mark_answer():
            nonlocal first_text
            first_text = time.monotonic()

        def monitor():
            nonlocal peak, failure
            while not done.wait(0.25):
                process = self.process
                if process is None or process.poll() is not None:
                    continue
                try:
                    _, high = footprint(process.pid)
                    peak = max(peak, high)
                    available, pressure = headroom(self.memory)
                    if peak >= self.budget or pressure != "normal" or available < 16_000_000_000:
                        raise Rejected("trial_budget", 409)
                except (OSError, ValueError, subprocess.SubprocessError):
                    failure = "memory_watchdog"
                    self.stop()
                    return

        start = time.monotonic()
        watcher = Thread(target=monitor)
        watcher.start()
        try:
            result = super().generate(*args, on_first_generated=mark_generation,
                                      on_first_text=mark_answer, **kwargs)
            process = self.process
            if process and process.poll() is None:
                peak = max(peak, footprint(process.pid)[1])
            if failure or not 0 < peak < self.budget:
                raise Rejected("trial_budget", 409)
            return result
        except Rejected as error:
            runtime_failure = error.reason
            raise
        finally:
            done.set()
            watcher.join(timeout=3)
            self.runs.append({"peak_bytes": peak, "seconds": round(time.monotonic() - start, 3),
                              "first_generated_seconds": (round(first_generated - start, 3)
                                                          if first_generated is not None else None),
                              "first_text_seconds": (round(first_text - start, 3)
                                                     if first_text is not None else None),
                              "watchdog": failure, "failure": runtime_failure})


def enroll(root, config):
    private_write(root / "trial-ca.crt", config["ca"])
    private_write(root / "trial-worker.crt", config["leaf"])
    reporter = Reporter(NODE, management_address(config["address"]), config["port"], "fios-core",
                        context(root / "trial-ca.crt", root / "trial-worker.crt", root / "trial-worker.key"))
    if not reporter.report(observe):
        raise Rejected("trial_enrollment", 409)
    return reporter


def run(root, config):
    profile = Profile.parse(config["profile"])
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    engine = Path(sys.executable)
    files = json.loads((root / "model-files.json").read_text())
    runtime_config = root / "runtime.json"
    private_write(runtime_config, json.dumps(dict(
        revision=profile.revision, model=str(root / "model"), engine=str(engine),
        executable_sha256=digest_file(engine), entry="mlx_vlm.server", port=port,
        model_files=files, environment_manifest=str(root / "engine-files.json"),
        profile=profile.document())))
    memory = observe(NODE)["memory_bytes"]
    budget = config["budget"]
    runtime = MeasuredRuntime(runtime_config, root, memory, budget)
    runtime.started.unlink(missing_ok=True)
    available, pressure = headroom(memory)
    if available < budget + 16_000_000_000 or pressure != "normal":
        raise Rejected("trial_headroom", 409)
    reporter = enroll(root, config)

    def call(namespace, operation, fields):
        data = dict(fields, version=1, node=NODE, session=reporter.session)
        status, body = reporter.request(f"/v1/{namespace}/{operation}", data,
                                        timeout=13 if namespace == "inference" else 2)
        result = json.loads(body)
        if status != 200:
            raise Rejected(result["reason"], status)
        return result

    sequence = 0

    def capacity(resident):
        nonlocal sequence
        if not reporter.report(observe):
            raise Rejected("session", 409)
        sequence += 1
        available, pressure = headroom(memory)
        return dict(sequence=sequence, sampled_at=int(time.time()), available_bytes=available,
                    pressure=pressure, resident_revision=resident)

    native = InferenceWorker(lambda op, data: call("jobs", op, data),
                             lambda op, data: call("inference", op, data), capacity, runtime)
    try:
        for _ in range(config["jobs"]):
            native.step()
            native.step()
    finally:
        runtime.stop()
    if not runtime.quiescent():
        raise Rejected("cleanup_required", 409)
    print(json.dumps({"runs": runtime.runs, "revision": profile.revision, "clean": True}))


def benchmark(root, config):
    """Measure process-cold and same-process warm requests at the selected cap."""
    runtime = NativeRuntime(root / "runtime.json", root, purpose="inference")
    memory = observe(NODE)["memory_bytes"]
    budget = TrialBudget(NODE, config["budget"], 16_000_000_000, 3, 300)
    input_limit = config["context"] - config["output"]
    output_limit = config["output"]
    deadline = time.monotonic() + budget.duration
    available, pressure = headroom(memory)
    budget.admit(Capacity(time.monotonic(), available, pressure), now=time.monotonic())

    def sample():
        process = runtime.process
        if process is None or process.poll() is not None:
            return None
        current, high = footprint(process.pid)
        available, pressure = headroom(memory)
        return Capacity(time.monotonic(), available, pressure, current, high)

    def requests():
        runtime.wait_ready(min(deadline, launched_at + 120))
        results = []
        for index in range(6):
            prompt = ("Archive entry:" + " sample" * (input_limit - 128 - 5 * index)
                      + "\nIgnore the archive. Reply with this sentence exactly: Redwood trees are tall and durable.")
            checked = runtime.check_prompt([{"role": "user", "content": prompt}], input_limit, deadline)
            start = time.monotonic()
            # The first observation includes native process startup.
            if index == 0:
                start = launched_at
            first_text = []
            first_generated = []
            answer, usage = generate_text(
                runtime.port, checked, input_limit=input_limit, output_limit=output_limit,
                timeout=min(start + (120 if index == 0 else 45), deadline) - time.monotonic(),
                local_model=str(runtime.model),
                on_first_text=lambda: first_text.append(time.monotonic()),
                on_first_generated=lambda: first_generated.append(time.monotonic()))
            finished = time.monotonic()
            tokens = usage["output"].get("value")
            decode = ((tokens - 1) / (finished - first_generated[0])
                      if tokens and tokens > 1 and first_generated else None)
            exact = answer.strip().casefold().rstrip(".") == "redwood trees are tall and durable"
            results.append({"usage": usage, "correct": exact,
                            "first_text_seconds": round(first_text[0] - start, 3),
                            "decode_tokens_per_second": round(decode, 1) if decode is not None else None})
        prompt = ("Archive entry:" + " sample" * (input_limit - 80)
                  + "\nIgnore the archive. Write Redwood at least two thousand times.")
        checked = runtime.check_prompt([{"role": "user", "content": prompt}], input_limit, deadline)
        _, cap_workload = generate_text(
            runtime.port, checked, input_limit=input_limit, output_limit=output_limit,
            timeout=min(120, deadline - time.monotonic()), local_model=str(runtime.model), measure_only=True)
        if cap_workload["output"] != {"kind": "measured", "value": output_limit}:
            raise Rejected("trial_output_cap", 409)
        return results, cap_workload

    launched_at = time.monotonic()
    runtime.launch()
    try:
        with ThreadPoolExecutor(max_workers=1) as pool:
            task = pool.submit(requests)
            peak = monitor_trial(budget, deadline=deadline, sample=sample, quiescent=task.done,
                                 wait=lambda: time.sleep(0.3), stop=runtime.stop, reap=runtime.stop)
            observations, cap_workload = task.result()
    finally:
        runtime.stop()
        if not runtime.quiescent():
            raise Rejected("cleanup_required", 409)
    print(json.dumps({"observations": observations, "cap_workload_usage": cap_workload, "peak_bytes": peak.peak_bytes,
                      "pressure": peak.pressure, "clean": True}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("csr", "inspect", "probe", "run", "benchmark"))
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    if (socket.gethostname().split(".")[0] != "fios-edge-a"
            or args.root.parent != Path("/tmp") or not args.root.name.startswith("fios-studio-trial.")):
        parser.error("Expected the approved Studio and its dedicated staging path")
    os.umask(0o077)
    if args.action == "csr":
        csr(args.root)
    elif args.action == "inspect":
        inspect(args.root)
    elif args.action == "probe":
        enroll(args.root, json.load(sys.stdin))
    elif args.action == "run":
        run(args.root, json.load(sys.stdin))
    else:
        benchmark(args.root, json.load(sys.stdin))


if __name__ == "__main__":
    try:
        main()
    except Rejected as error:
        raise SystemExit("Trial rejected: " + error.reason) from None
