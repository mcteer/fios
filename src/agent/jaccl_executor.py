"""Native rank entry point. The files, peer and attempt are bound before launch."""

import json
import os
from pathlib import Path
import sys
import time

from backend.enrollment import Rejected

from .jaccl_transport import JacclTransport
from .macos_memory import footprint
from .native_executor import watch_parent


class ContextLimit(ValueError):
    pass


def share(core, group, rank, values):
    data = core.array(values if rank == 0 else [0] * len(values), dtype=core.int32)
    return core.distributed.all_sum(data, group=group).tolist()


def load_reviewed_moe(path, mx, group):
    from mlx_lm.utils import load_config, load_model, load_tokenizer

    # This path supports the reviewed built-in text adapter. A different
    # architecture needs its own loader and forward-transfer observer.
    if load_config(path).get("model_type") != "qwen3_5_moe":
        raise ValueError("Large-model text architecture requires an approved adapter")
    model, config = load_model(path, lazy=True, strict=True, trust_remote_code=False)
    tokenizer = load_tokenizer(path, {"trust_remote_code": False},
                               eos_token_ids=config.get("eos_token_id"))
    model.shard(group)
    mx.eval(model.parameters())
    mx.eval(mx.distributed.all_sum(mx.array(1.0), group=group, stream=mx.cpu))
    return model, tokenizer


def run(path, work):
    if "watchdog" not in work:
        return execute(path, work)
    import socket

    from .rank_monitor import RankPhases

    host = socket.gethostname().split(".")[0]
    if (work["world_size"] != 2 or work["rank"] not in (0, 1)
            or host != ("fios-edge-a", "fios-edge-b")[work["rank"]]):
        raise ValueError("Large-model ranks require their assigned Studios")
    with socket.socket(fileno=work["phase_fd"]) as channel:
        observer = RankPhases(channel)
        observer.phase("load")
        result = execute(path, work, watchdog=observer)
        observer.exchange(b"e")
        return result


def execute(path, work, *, watchdog=None):
    import mlx.core as mx
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler
    from mlx_lm.utils import sharded_load

    started = time.monotonic()
    rank = work["rank"]
    transport = None
    if work["world_size"] == 2:
        transport = JacclTransport(mx, rank)
        group = transport.group
        # A fresh rank must agree with its peer before either begins loading.
        identity = work["identity"]["attempt"]
        if watchdog:
            identity += work["identity"]["candidate"] + work["staged_artifact"]
        marker = list(bytes.fromhex(identity))
        match = share(mx, group, rank, marker) == marker
        agreement = mx.distributed.all_sum(mx.array(int(match), dtype=mx.int32), group=group)
        if agreement.item() != 2:
            raise ValueError("Peer has a different attempt or artifact")
        if watchdog:
            model, tokenizer = load_reviewed_moe(path, mx, group)
        else:
            model, tokenizer = sharded_load(path, tensor_group=group)
    else:
        model, tokenizer = load(path)

    if watchdog:
        watchdog.phase("prefill")
    prefill_started = time.monotonic()
    first_token = None
    tokens = []
    if work["messages"] is not None:
        options = {"enable_thinking": False} if work["no_thinking"] else {}
        tokens = tokenizer.apply_chat_template(work["messages"], add_generation_prompt=True, **options)
    if transport:
        size, = share(mx, group, rank, [len(tokens)])
        if not 0 < size <= work["input_limit"]:
            raise ContextLimit("Prompt exceeds the approved context")
        tokens = share(mx, group, rank, tokens if rank == 0 else [0] * size)
    if not 0 < len(tokens) <= work["input_limit"]:
        raise ContextLimit("Prompt exceeds the approved context")

    def answer():
        nonlocal first_token
        parts = []
        first = None
        count = 0
        for chunk in stream_generate(model, tokenizer, tokens, max_tokens=work["output_limit"],
                                     sampler=make_sampler(temp=work["temperature"])):
            if count == 0:
                first_token = time.monotonic()
                if watchdog:
                    watchdog.phase("decode")
            count += 1
            if chunk.text and first is None:
                first = time.monotonic() - started
            parts.append(chunk.text)
        return "".join(parts), count, first

    if transport:
        with transport.observe_forward_passes(observe_all_gather=watchdog is not None):
            text, count, first = answer()
        diagnostics = {"transport_evidence": transport.evidence(**work["identity"])}
    else:
        text, count, first = answer()
        diagnostics = {}
    decoded_at = time.monotonic()
    if not text or first is None or count <= 0:
        raise ValueError("No answer text was generated")
    if work["expected"] is not None or watchdog:
        _, peak = footprint(os.getpid())
        diagnostics["trial_measurement"] = dict(
            peak_bytes=peak, first_text_ms=int(first * 1000),
            elapsed_ms=max(1, int((decoded_at - started) * 1000)),
            fixture_passed=(work["expected"] is None
                            or text.strip().casefold().rstrip(".") == work["expected"].strip().casefold().rstrip(".")),
            completed_tokens=count,
        )
        if watchdog:
            diagnostics["trial_measurement"]["timing"] = dict(
                input_tokens=len(tokens), prefill_ms=max(1, int((first_token - prefill_started) * 1000)),
                decode_ms=max(1, int((decoded_at - first_token) * 1000)) if count > 1 else 0)
    return dict(answer=text if rank == 0 and work["expected"] is None else None,
                usage={"input": {"kind": "measured", "value": len(tokens)},
                       "output": {"kind": "measured", "value": count}},
                diagnostics=diagnostics)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--parent":
        expected = int(sys.argv[2])
        if os.getppid() != expected or os.getpgrp() != os.getpid():
            raise RuntimeError("Paired rank requires its native worker and a dedicated process group")
        watch_parent(expected)
        del sys.argv[1:3]
    raw = sys.stdin.buffer.read(100 * 1024 + 1)
    if len(raw) > 100 * 1024:
        raise ValueError("Native rank input exceeds its limit")
    try:
        result = run(Path(sys.argv[1]), json.loads(raw))
    except ContextLimit:
        raise SystemExit(65) from None
    except Rejected as error:
        if error.reason in ("unsafe_rank_resources", "stale_rank_resources"):
            raise SystemExit(78) from None
        raise
    output = json.dumps(result, ensure_ascii=True)
    if len(output) > 96 * 1024:
        raise ValueError("Native rank output exceeds its limit")
    print(output)


if __name__ == "__main__":
    main()
