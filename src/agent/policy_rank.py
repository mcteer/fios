"""Native long-context classification using the exact tokenized transcript."""

import json
import os
from pathlib import Path
import subprocess
import sys

from backend.pair_trial import GIB
from .moe_watchdog import RankWatchdog, swap_used
from .native_executor import watch_parent


def run(model, messages):
    from mlx_lm import generate, load
    from mlx_lm.sample_utils import make_sampler

    watcher = RankWatchdog(
        memory=int(subprocess.check_output(["/usr/sbin/sysctl", "-n", "hw.memsize"], timeout=1)),
        floor=4 * GIB, ceiling=8 * GIB, baseline=swap_used())
    with watcher.monitoring():
        model, tokenizer = load(model, tokenizer_config={"trust_remote_code": False},
                                trust_remote_code=False)
        watcher.phase("prefill")
        tokens = tokenizer.apply_chat_template(messages, add_generation_prompt=True)
        if not 0 < len(tokens) <= 12288:
            raise SystemExit(65)
        watcher.phase("decode")
        return generate(model, tokenizer, prompt=tokens, max_tokens=8,
                        sampler=make_sampler(temp=0), verbose=False).strip()


def main():
    if len(sys.argv) != 4 or sys.argv[1] != "--parent":
        raise ValueError("The classifier requires an owning native worker")
    parent = int(sys.argv[2])
    if os.getppid() != parent or os.getpgrp() != os.getpid():
        raise ValueError("The classifier requires its own process group")
    watch_parent(parent)
    data = sys.stdin.buffer.read(256 * 1024 + 1)
    if len(data) > 256 * 1024:
        raise ValueError("Policy transcript exceeds its byte limit")
    answer = run(Path(sys.argv[3]), json.loads(data))
    if answer not in ("ALLOW", "WITHHOLD"):
        raise SystemExit(66)
    print(answer)


if __name__ == "__main__":
    main()
