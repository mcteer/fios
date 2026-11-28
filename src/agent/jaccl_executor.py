"""Native rank entry point. The files, peer and attempt are bound before launch."""

import json
import os
from pathlib import Path
import sys
import time

from .jaccl_transport import JacclTransport
from .macos_memory import footprint
from .native_executor import watch_parent


def share(core, group, rank, values):
    data = core.array(values if rank == 0 else [0] * len(values), dtype=core.int32)
    return core.distributed.all_sum(data, group=group).tolist()


def run(path, work):
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
        attempt = list(bytes.fromhex(work["identity"]["attempt"]))
        match = share(mx, group, rank, attempt) == attempt
        agreement = mx.distributed.all_sum(mx.array(int(match), dtype=mx.int32), group=group)
        if agreement.item() != 2:
            raise ValueError("Peer is running a different attempt")
        model, tokenizer = sharded_load(path, tensor_group=group)
    else:
        model, tokenizer = load(path)

    tokens = []
    if work["messages"] is not None:
        options = {"enable_thinking": False} if work["no_thinking"] else {}
        tokens = tokenizer.apply_chat_template(work["messages"], add_generation_prompt=True, **options)
    if transport:
        size, = share(mx, group, rank, [len(tokens)])
        if not 0 < size <= work["input_limit"]:
            raise ValueError("Prompt exceeds the approved context")
        tokens = share(mx, group, rank, tokens if rank == 0 else [0] * size)
    if not 0 < len(tokens) <= work["input_limit"]:
        raise ValueError("Prompt exceeds the approved context")

    def answer():
        parts = []
        first = None
        count = 0
        for chunk in stream_generate(model, tokenizer, tokens, max_tokens=work["output_limit"],
                                     sampler=make_sampler(temp=work["temperature"])):
            count += 1
            if chunk.text and first is None:
                first = time.monotonic() - started
            parts.append(chunk.text)
        return "".join(parts), count, first

    if transport:
        with transport.observe_forward_passes():
            text, count, first = answer()
        diagnostics = {"transport_evidence": transport.evidence(**work["identity"])}
    else:
        text, count, first = answer()
        diagnostics = {}
    if not text or first is None or count <= 0:
        raise ValueError("No answer text was generated")
    if work["expected"] is not None:
        _, peak = footprint(os.getpid())
        diagnostics["trial_measurement"] = dict(
            peak_bytes=peak, first_text_ms=int(first * 1000),
            elapsed_ms=max(1, int((time.monotonic() - started) * 1000)),
            fixture_passed=text.strip().casefold().rstrip(".") == work["expected"].strip().casefold().rstrip("."),
            completed_tokens=count,
        )
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
    result = run(Path(sys.argv[1]), json.loads(raw))
    output = json.dumps(result, ensure_ascii=True)
    if len(output) > 96 * 1024:
        raise ValueError("Native rank output exceeds its limit")
    print(output)


if __name__ == "__main__":
    main()
