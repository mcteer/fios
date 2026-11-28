"""Prepare the Qwen tokenizer, frozen suite and reduced probe in a private directory."""

import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
import sys

from backend.enrollment import private_path
from create_qwen_moe_probe import TOKENIZER_FILES
from stage_moe_pack import FILE_LIMIT, PACKS, pack_info, read_url
from verify_jaccl_model import verified_wheels


def prepare(root, policy):
    private_path(root, directory=True)
    source = root / "tokenizer"
    probe = root / "probe"
    suite = root / "suite"
    for directory in (source, probe, suite):
        directory.mkdir(mode=0o700)
    info = pack_info("qwen")
    (root / "pack.json").write_text(json.dumps(info, sort_keys=True))
    repo, revision = PACKS["qwen"]
    for name in TOKENIZER_FILES:
        expected = info["files"].get(name)
        if expected is None:
            continue
        data = read_url(f"https://huggingface.co/{repo}/resolve/{revision}/{name}", FILE_LIMIT)
        if len(data) != expected["bytes"] or sha256(data).hexdigest() != expected["sha256"]:
            raise ValueError("Candidate tokenizer differs from reviewed metadata")
        (source / name).write_bytes(data)

    verified_wheels(root)
    engine = root / "venv/bin/python"
    subprocess.run([sys.executable, "-m", "venv", root / "venv"], check=True, timeout=30)
    subprocess.run([engine, "-m", "pip", "--isolated", "install", "--no-index", "--require-hashes",
                    "--no-compile", "--find-links", root / "wheels", "-r", root / "requirements.txt"],
                   check=True, timeout=120, stdout=subprocess.DEVNULL)
    env = {**os.environ, "PYTHONPATH": "src:tests", "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1"}
    with (root / "probe.json").open("xb") as result:
        subprocess.run([engine, "-B", "tests/macos/create_qwen_moe_probe.py", source, probe],
                       stdout=result, env=env, check=True, timeout=60)
    subprocess.run([engine, "-B", "tests/macos/freeze_moe_suite.py", source, suite, policy],
                   env=env, check=True, timeout=60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("private_directory", type=Path)
    parser.add_argument("policy")
    args = parser.parse_args()
    os.umask(0o077)
    prepare(args.private_directory, args.policy)


if __name__ == "__main__":
    main()
