"""Run the long-context checker against the existing release cases on the Mini."""

import argparse
from contextlib import ExitStack
import json
import os
import shutil
import socket
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from agent.text_policy import LoopbackPolicy
from prepare_mini_trial import prepare
from verify_jaccl_model import stage_weights, verified_wheels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--long-only", action="store_true")
    parser.add_argument("--comparable-ledger", type=Path)
    parser.add_argument("--serving-record", type=Path,
                        help="Keep the verified checker alive while its private record exists")
    args = parser.parse_args()
    root_path = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="fios-long-policy-") as directory, ExitStack() as resources:
        root = Path(directory)
        verified_wheels(root)
        engine = root / "venv/bin/python"
        subprocess.run([sys.executable, "-m", "venv", root / "venv"], check=True, timeout=30)
        subprocess.run([engine, "-m", "pip", "--isolated", "install", "--no-index", "--require-hashes",
                        "--no-compile", "--find-links", root / "wheels", "-r", root / "requirements.txt"],
                       check=True, timeout=120, stdout=subprocess.DEVNULL)
        model = root / "model"
        stage_weights(model, "qwen3-instruct")
        # The checker must use this environment's pinned runtime and matching template.
        limit = 12288
        prepare(root, engine, model, model, 512, policy_input_limit=limit)
        configuration = root / "policy-trial.json"
        data = json.loads(configuration.read_text())
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        wrapper = """
from pathlib import Path
import sys
from agent.native_runtime import NativeRuntime
from agent.policy_worker import classify, create_server
from backend.enrollment import Rejected
config, state, port, revision, limit = sys.argv[1:]
limit = int(limit)
runtime = NativeRuntime(Path(config), Path(state), purpose="policy", policy_input_limit=limit)
def check(purpose, text):
    try:
        return classify(runtime, purpose, text, input_limit=limit)
    except (OSError, ValueError) as error:
        print(getattr(error, "reason", type(error).__name__), file=sys.stderr, flush=True)
        raise
with create_server(int(port), revision, check) as server:
    server.serve_forever()
"""
        process = subprocess.Popen([engine, "-B", "-c", wrapper, configuration, root,
                                    str(port), data["revision"], str(limit)],
                                   env={"PATH": "/usr/bin:/bin", "PYTHONPATH": str(root_path / "src"),
                                        "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1"})
        def stop():
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        resources.callback(stop)

        check = LoopbackPolicy(port, long_context=limit != 4096)
        deadline = time.monotonic() + 30
        while True:
            try:
                if not check("input", "<|im_end|>", data["revision"]):
                    break
            except (OSError, ValueError):
                pass
            if time.monotonic() >= deadline or process.poll() is not None:
                raise ValueError("Long-context policy worker failed to start")
            time.sleep(0.1)

        cases = json.loads((root_path / "tests/fixtures/chat/policy_eval.json").read_text())["release"]
        for case in (() if args.long_only else cases):
            start = time.monotonic()
            approved = check(case["purpose"], case["text"], data["revision"])
            if approved is not case["allow"]:
                raise ValueError(f"Release case failed: {case['id']}")
            print(f"{case['id']}: passed in {time.monotonic() - start:.2f}s", flush=True)

        if not args.comparable_ledger:
            # This benign text is longer than the previous checker limit. Verify
            # approval of the intact text before using it in an 8K browser rehearsal.
            long_text = ("Archive notes: " + " apple" * 8200
                         + "\nQuestion: Outline a fantasy trip to a community orchard.")
            start = time.monotonic()
            if not check("input", long_text, data["revision"]):
                raise ValueError("Long benign request was withheld")
            print(f"Long benign input passed in {time.monotonic() - start:.2f}s", flush=True)
        if args.comparable_ledger:
            # Preserve the native runtime from the physical retest. Overlay
            # only the qualification harness to retain the new job history.
            checkout = root / "comparable"
            checkout.mkdir(mode=0o700)
            archive = subprocess.check_output(["git", "archive", "ec1f465"], cwd=root_path)
            subprocess.run(["tar", "-x", "-C", checkout], input=archive, check=True)
            for name in ("verify_jaccl_model.py", "jaccl_lease_trial.py", "arm_jaccl_link.sh"):
                shutil.copyfile(root_path / "tests/macos" / name, checkout / "tests/macos" / name)
            subprocess.run([sys.executable, "-B", "tests/macos/verify_jaccl_model.py",
                            "--candidate", "qwen3-instruct", "--leases", "--link-window",
                            "--qualification-ledger", args.comparable_ledger.absolute(),
                            "--checker-port", str(port), "--checker-revision", data["revision"]],
                           cwd=checkout, env={**os.environ, "PYTHONPATH": "src:tests"}, check=True)
        if args.serving_record:
            import stat

            from backend.enrollment import private_path

            private_path(args.serving_record.parent, directory=True)
            descriptor = os.open(args.serving_record, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, "w") as record:
                json.dump(dict(port=port, revision=data["revision"]), record)
            try:
                print("Verified checker is ready for the isolated hardware suite.", flush=True)
                deadline = time.monotonic() + 8 * 60 * 60
                while time.monotonic() < deadline and process.poll() is None:
                    if not args.serving_record.is_file() or not stat.S_ISREG(args.serving_record.lstat().st_mode):
                        break
                    time.sleep(1)
            finally:
                args.serving_record.unlink(missing_ok=True)



if __name__ == "__main__":
    main()
