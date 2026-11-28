"""Bind staged Mini trial artifacts to the verified serving and policy identities."""

import argparse
import json
import os
from pathlib import Path
import socket

from agent.native_runtime import digest_file, environment_root, manifest_digest, verify_environment
from agent.publication_prompt import prompt_digest
from backend.enrollment import private_path
from backend.model_catalog import Profile


def model_files(model):
    names = {".json", ".jinja", ".model", ".safetensors", ".txt"}
    return {file.name: digest_file(file) for file in model.iterdir() if file.suffix in names}


def prepare(root, engine, chat, guard, output_tokens, policy_input_limit=4096):
    private_path(root, directory=True)
    executable = digest_file(engine)
    site = environment_root(engine)
    environment = root / "environment-files.json"
    environment.touch(mode=0o600)
    environment.write_text(json.dumps({p.relative_to(site).as_posix(): digest_file(p)
                                       for p in site.rglob("*") if p.is_file()}))
    fingerprint = verify_environment(engine, environment, "mlx_lm.server", executable)
    with socket.socket() as first, socket.socket() as second:
        for listener in (first, second):
            listener.bind(("127.0.0.1", 0))
        chat_port, guard_port = first.getsockname()[1], second.getsockname()[1]
    chat_hashes, guard_hashes = model_files(chat), model_files(guard)
    worker = Path(__file__).resolve().parents[2] / "src" / "agent" / "policy_worker.py"
    identity = dict(artifact=manifest_digest(guard_hashes), engine=fingerprint,
                    prompt=prompt_digest("framed"), worker=digest_file(worker))
    if policy_input_limit != 4096:
        identity["input_limit"] = policy_input_limit
        identity["rank"] = {name: digest_file(worker.with_name(name))
                            for name in ("policy_rank.py", "macos_memory.py", "moe_watchdog.py")}
    policy = manifest_digest(identity)
    profile = dict(alias="general-chat", host_class="m4-pro-mini", artifact=manifest_digest(chat_hashes),
                   engine=fingerprint, template=chat_hashes.get(
                       "chat_template.jinja", chat_hashes.get("tokenizer_config.json")),
                   policy=policy, evaluation=digest_file(
                       Path(__file__).parents[1] / "fixtures" / "chat" / "policy_eval.json"),
                   license="LFM Open License 1.0", context=1024, output=output_tokens,
                   settings={"temperature": 0})
    configurations = (
        ("browser-trial.json", chat, Profile.parse(profile).revision, chat_port, chat_hashes),
        ("policy-trial.json", guard, policy, guard_port, guard_hashes),
    )
    for name, model, revision, port, hashes in configurations:
        file = root / name
        file.touch(mode=0o600)
        config = dict(revision=revision, model=str(model), engine=str(engine), executable_sha256=executable,
                      entry="mlx_lm.server", port=port, model_files=hashes,
                      environment_manifest=str(environment))
        if name == "browser-trial.json":
            config["profile"] = profile
        file.write_text(json.dumps(config))
    (root / "trial-profile.json").write_text(json.dumps(profile))
    (root / "policy-revision").write_text(policy)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("state", "engine", "chat", "guard"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--output-tokens", type=int, default=512)
    parser.add_argument("--policy-input-limit", type=int, choices=(4096, 12288), default=4096)
    args = parser.parse_args()
    os.umask(0o077)
    prepare(args.state, args.engine, args.chat, args.guard, args.output_tokens, args.policy_input_limit)


if __name__ == "__main__":
    main()
