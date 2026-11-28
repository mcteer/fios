"""Run a pinned native comparison as a disposable operator benchmark."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from hashlib import file_digest, sha1
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
HOSTS = ("mcteer@fios-edge-a.local", "mcteer@fios-edge-b.local")
OPTIONS = ("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=6")
PACKS = {
    "qwen2-coder": ("mlx-community/Qwen2.5-Coder-7B-Instruct-4bit", "019cc73c45c770444708a6dd8690c66243cc5c80"),
    "qwen3": ("mlx-community/Qwen3-8B-4bit", "545dc4251c05440727734bcd94334791f6ab0192"),
    "qwen3-instruct": ("mlx-community/Qwen3-4B-Instruct-2507-4bit",
                       "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"),
}


def parallel(operation, items):
    with ThreadPoolExecutor(max_workers=4) as pool:
        return list(pool.map(operation, items))


def metadata(url):
    with urlopen(url, timeout=20) as stream:
        return json.load(stream)


def stage_weights(directory, candidate):
    """Invoked on each Studio to download and verify its local copy."""
    pack, revision = PACKS[candidate]
    snapshot = metadata(f"https://huggingface.co/api/models/{pack}/revision/{revision}?blobs=true")
    if snapshot["sha"] != revision:
        raise ValueError("Unexpected model revision")
    directory.mkdir()

    def download(file):
        name = file["rfilename"]
        if Path(name).name != name:
            raise ValueError("Unexpected model file path")
        url = f"https://huggingface.co/{pack}/resolve/{revision}/{name}"
        location = directory / name
        with urlopen(url, timeout=180) as source, location.open("wb") as output:
            shutil.copyfileobj(source, output, length=1024**2)
        if location.stat().st_size != file["size"]:
            raise ValueError("Unexpected model file size")
        with location.open("rb") as stream:
            verified = (file_digest(stream, "sha256").hexdigest() == file["lfs"]["sha256"]
                        if "lfs" in file else
                        sha1(f"blob {file['size']}\0".encode() + stream.read()).hexdigest() == file["blobId"])
        if not verified:
            raise ValueError(f"Artifact digest differs for {name}")

    parallel(download, [item for item in snapshot["siblings"]
                        if Path(item["rfilename"]).suffix in (".json", ".txt", ".safetensors", ".jinja", ".model")])


def verified_wheels(directory):
    wheels = directory / "wheels"
    wheels.mkdir()
    subprocess.run([sys.executable, "-m", "pip", "--isolated", "download", "--no-cache-dir",
                    "--only-binary=:all:", "--disable-pip-version-check", "--dest", wheels,
                    "mlx==0.32.5", "mlx-lm==0.32.2"], check=True, timeout=180,
                   stdout=subprocess.DEVNULL)

    def pin(path):
        name, version = path.name.split("-")[:2]
        release = metadata(f"https://pypi.org/pypi/{name}/{version}/json")
        record = next(item for item in release["urls"] if item["filename"] == path.name)
        digest = record["digests"]["sha256"]
        with path.open("rb") as stream:
            if file_digest(stream, "sha256").hexdigest() != digest:
                raise ValueError(f"Wheel hash differs for {name}")
        return f"{name}=={version} --hash=sha256:{digest}"

    requirements = parallel(pin, sorted(wheels.glob("*.whl")))
    (directory / "requirements.txt").write_text("\n".join(requirements) + "\n")


def execute(argv):
    from agent.macos_memory import footprint, headroom

    memory = int(subprocess.check_output(["/usr/sbin/sysctl", "-n", "hw.memsize"], timeout=2))
    reserve, ceiling = 32 * 1024**3, 16 * 1024**3
    available, pressure = headroom(memory)
    if pressure != "normal" or available < reserve + ceiling:
        raise RuntimeError("Insufficient observed memory headroom")
    started = time.monotonic()
    peak = 0
    with tempfile.TemporaryFile() as output:
        child = subprocess.Popen([sys.executable, "-B", *argv], stdout=output, start_new_session=True)
        try:
            while child.poll() is None:
                try:
                    _, high = footprint(child.pid)
                except OSError:
                    if child.poll() is None:
                        raise
                    break
                peak = max(peak, high)
                available, pressure = headroom(memory)
                if pressure != "normal" or available < reserve or peak >= ceiling:
                    raise RuntimeError("Model comparison crossed its trial memory budget")
                if time.monotonic() - started >= 420:
                    raise TimeoutError("Model comparison exceeded its wall deadline")
                try:
                    child.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
            if child.returncode or peak <= 0:
                raise RuntimeError("Model comparison did not return measured results")
            output.seek(0)
            result = json.loads(output.read(128 * 1024))
            result["observed_peak_bytes"] = peak
            print(json.dumps(result))
        finally:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=5)


def compare(local, candidate, *, leases=False, leases_only=False, link_window=False, web_only=False,
            qualification_ledger=None, checker_port=None, checker_revision=None):
    remote_dir = "/private/tmp/fios-jaccl-model-" + secrets.token_hex(8)
    port = str(47000 + secrets.randbelow(10000))
    created = set()

    def remote(host, *args, limit=90, payload=None):
        result = subprocess.run(["ssh", *OPTIONS, host, shlex.join(args)], capture_output=True,
                                text=True, timeout=limit, input=payload)
        if result.returncode:
            raise RuntimeError(f"{host} exited {result.returncode}\n{result.stderr[-2400:]}")
        return result.stdout

    def stage(host):
        remote(host, "mkdir", "-m", "700", remote_dir)
        created.add(host)
        subprocess.run(["scp", *OPTIONS, "-r", *map(str, local.iterdir()), f"{host}:{remote_dir}/"],
                       check=True, timeout=140)
        remote(host, "/opt/homebrew/bin/python3", "-m", "venv", remote_dir + "/venv")
        remote(host, remote_dir + "/venv/bin/python", "-m", "pip", "--isolated", "install",
               "--no-index", "--no-compile", "--find-links", remote_dir + "/wheels", "--require-hashes",
               "-r", remote_dir + "/requirements.txt")
        # ensurepip may generate host-specific bytecode even when wheel installs
        # use --no-compile. Pin source artifacts and run with bytecode disabled.
        remote(host, "/opt/homebrew/bin/python3", "-B", "-c",
               "from pathlib import Path; import shutil,sys; "
               "[shutil.rmtree(path) for path in list(Path(sys.argv[1]).glob('**/__pycache__'))]",
               remote_dir + "/venv/lib")
        remote(host, "/opt/homebrew/bin/python3", "-B", remote_dir + "/verify_jaccl_model.py",
               "--stage-weights", remote_dir + "/model", "--candidate", candidate, limit=540)
        print(f"Verified candidate artifacts on {host.split('@')[1]}", flush=True)

    def run(host, *, rank=None):
        argv = [remote_dir + "/jaccl_model_probe.py", remote_dir + "/model", "--qualification"]
        env = dict(PYTHONPATH=remote_dir)
        if rank is not None:
            argv.append("--paired")
            env.update(MLX_RANK=str(rank), MLX_IBV_DEVICES=remote_dir + "/devices.json",
                       MLX_JACCL_COORDINATOR="192.168.0.1:" + port)
        if candidate == "qwen3":
            argv.append("--no-thinking")
        output = remote(host, "env", *(f"{k}={v}" for k,v in env.items()),
                        remote_dir + "/venv/bin/python", "-B", remote_dir + "/verify_jaccl_model.py",
                        "--execute", *argv, limit=435)
        result = json.loads(output)
        records = result["records"]
        summary = dict(rank=rank, load_s=result["load_s"],
                       correct=[entry["correct"] for entry in records],
                       first_s=[entry["first_s"] for entry in records[:6]],
                       peak_gb=max(entry["peak_gb"] for entry in records),
                       decode_tps=[entry["decode_tps"] for entry in records[:6]],
                       cap=(records[-1]["input_tokens"], len(records[-1]["token_ids"])),
                       collectives=result["completed_forward_collectives"],
                       collective_input_bytes=result["forward_collective_input_bytes"],
                       observed_peak_bytes=result["observed_peak_bytes"],
                       failed_answers=[entry["text"][:120] for entry in records[:6] if not entry["correct"]])
        print(json.dumps(summary), flush=True)
        return result

    def verify_serving_entry():
        # Run the real native adapter entry against the same staged pack.
        # Only the reporter receives chat messages over the control channel.
        attempt = secrets.token_hex(16)
        candidate_revision = PACKS[candidate][1]
        fixture_prompt = "Return only the SQL query that counts all rows in table orders."

        def rank_entry(entry):
            rank, host = entry
            env = dict(PYTHONPATH=remote_dir, HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1",
                       TOKENIZERS_PARALLELISM="false", MLX_RANK=str(rank),
                       MLX_IBV_DEVICES=remote_dir + "/devices.json",
                       MLX_JACCL_COORDINATOR=f"192.168.0.1:{int(port) + 1}")
            request = dict(rank=rank, world_size=2, input_limit=7168, output_limit=128,
                           messages=[{"role": "user", "content": fixture_prompt}] if rank == 0 else None,
                           expected=None, no_thinking=candidate == "qwen3", temperature=0,
                           identity=dict(attempt=attempt, candidate=candidate_revision, device=str(rank) * 64))
            return json.loads(remote(host, "env", *(f"{k}={v}" for k, v in env.items()),
                                     remote_dir + "/venv/bin/python", "-B",
                                     remote_dir + "/verify_jaccl_model.py", "--execute",
                                     "-m", "agent.jaccl_executor", remote_dir + "/model",
                                     limit=435, payload=json.dumps(request)))

        outcomes = parallel(rank_entry, enumerate(HOSTS))
        if not outcomes[0]["answer"] or outcomes[1]["answer"] is not None:
            raise ValueError("Native ranks returned output through the wrong channel")
        left, right = [entry["diagnostics"]["transport_evidence"] for entry in outcomes]
        if left["attempt"] != attempt or right["attempt"] != attempt or left["transfers"] != right["transfers"]:
            raise ValueError("Native rank output stages did not match")
        print("Native serving entry passed reporter-only output and matched JACCL observations.", flush=True)

    try:
        parallel(stage, HOSTS)
        if leases_only:
            from jaccl_lease_trial import run_leases
            run_leases(HOSTS, OPTIONS, remote, remote_dir, int(port) + 2, candidate == "qwen3",
                       link_window=link_window, web_only=web_only)
            return
        baseline = run(HOSTS[0])
        ranks = parallel(lambda entry: run(entry[1], rank=entry[0]), enumerate(HOSTS))
        if [report["rank"] for report in ranks] != [0, 1]:
            raise ValueError("Unexpected pair membership")
        for field in ("completed_forward_collectives", "forward_collective_input_bytes"):
            if not 0 < ranks[0][field] == ranks[1][field]:
                raise ValueError("Rank transport measurements disagree")
        tokens = lambda report: [entry["token_ids"] for entry in report["records"]]
        if tokens(ranks[0]) != tokens(ranks[1]):
            raise ValueError("Rank output tokens disagree")
        matches = sum(a == b for a,b in zip(tokens(baseline), tokens(ranks[0]), strict=True))
        print(f"Matched single/pair token sequences: {matches} of 9", flush=True)
        verify_serving_entry()
        if any(not entry["correct"] for report in [baseline, *ranks] for entry in report["records"]):
            raise ValueError("Candidate failed one or more quality or context checks")
        comparison = None
        if qualification_ledger:
            if matches != 9:
                raise ValueError("Comparable qualification requires matching generated tokens")
            seconds = max(record["first_s"] for report in [baseline, *ranks]
                          for record in report["records"] if record.get("first_s") is not None)
            comparison = dict(worst_latency_ms=round(seconds * 1000), latency_limit_ms=15_000)
        if leases:
            from jaccl_lease_trial import run_leases
            run_leases(HOSTS, OPTIONS, remote, remote_dir, int(port) + 2, candidate == "qwen3",
                       link_window=link_window, web_only=web_only,
                       qualification_ledger=qualification_ledger, checker_port=checker_port,
                       checker_revision=checker_revision, comparison=comparison)
    finally:
        def clean(host):
            if host in created:
                remote(host, "/opt/homebrew/bin/python3", "-B", "-c",
                       "import shutil,sys; shutil.rmtree(sys.argv[1])", remote_dir)
                remote(host, "test", "!", "-e", remote_dir)
        parallel(clean, HOSTS)
        print("Disposable model and environments removed from both Studios.", flush=True)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--execute":
        execute(sys.argv[2:])
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("--candidate", choices=PACKS, default="qwen3-instruct")
        parser.add_argument("--stage-weights", type=Path)
        parser.add_argument("--leases", action="store_true")
        parser.add_argument("--leases-only", action="store_true")
        parser.add_argument("--link-window", action="store_true")
        parser.add_argument("--web-only", action="store_true")
        parser.add_argument("--qualification-ledger", type=Path)
        parser.add_argument("--checker-port", type=int)
        parser.add_argument("--checker-revision")
        args = parser.parse_args()
        if args.qualification_ledger and (not args.leases or not args.link_window or args.leases_only
                                         or args.web_only or not args.checker_port or not args.checker_revision):
            parser.error("Export requires the complete comparison, physical link trial and real checker")
        if args.stage_weights:
            stage_weights(args.stage_weights, args.candidate)
        else:
            with tempfile.TemporaryDirectory(prefix="fios-jaccl-model-") as folder:
                local = Path(folder)
                verified_wheels(local)
                for name in ("verify_jaccl_model.py", "jaccl_model_probe.py"):
                    shutil.copyfile(Path(__file__).with_name(name), local / name)
                (local / "fixtures").mkdir()
                shutil.copyfile(ROOT / "tests/fixtures/chat_coding.py", local / "fixtures/chat_coding.py")
                (local / "agent").mkdir()
                for name in ("jaccl_transport.py", "macos_memory.py", "jaccl_executor.py", "native_executor.py"):
                    shutil.copyfile(ROOT / "src/agent" / name, local / "agent" / name)
                (local / "devices.json").write_text(json.dumps([[None, ["rdma_en5"]], [["rdma_en5"], None]]))
                if args.leases or args.leases_only or args.web_only:
                    shutil.copytree(ROOT / "src", local / "src", ignore=shutil.ignore_patterns("__pycache__"))
                    for name in ("jaccl_lease_trial.py", "arm_jaccl_link.sh"):
                        shutil.copyfile(Path(__file__).with_name(name), local / name)
                compare(local, args.candidate, leases=args.leases, leases_only=args.leases_only or args.web_only,
                        link_window=args.link_window, web_only=args.web_only,
                        qualification_ledger=args.qualification_ledger,
                        checker_port=args.checker_port, checker_revision=args.checker_revision)
