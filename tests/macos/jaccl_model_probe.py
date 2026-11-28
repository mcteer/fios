"""Compare an offline MLX model with the same model sharded over strict JACCL."""

import argparse
import json
import os
from pathlib import Path
import time

from agent.jaccl_transport import JacclTransport
from fixtures.chat_coding import TASKS, evaluate

PROMPTS = (
    "Answer with one integer only: what is 8 plus 5?",
    "Answer with one integer only: how many values are in [9, 1, 4]?",
    "Answer with one word only: what color is ripe grass?",
    'Answer with one integer only: what does len("apple") return in Python?',
    "Return only the SQL query that counts all rows in table orders.",
    "Return only the SQL query selecting email from users ordered by email.",
)


def generate(model, tokenizer, stream_generate, sampler, prompt, limit=32, *, no_thinking=False):
    options = {"enable_thinking": False} if no_thinking else {}
    tokens = tokenizer.apply_chat_template(
        [{"role": "user", "content": prompt}], add_generation_prompt=True, **options,
    )
    started = time.monotonic()
    first = None
    parts, ids = [], []
    for frame in stream_generate(model, tokenizer, tokens, max_tokens=limit, sampler=sampler):
        if frame.text and first is None:
            first = time.monotonic() - started
        parts.append(frame.text)
        ids.append(frame.token)
    if not ids:
        raise RuntimeError("Model emitted no tokens")
    return dict(text="".join(parts), token_ids=ids, input_tokens=len(tokens),
                first_s=round(first, 4) if first is not None else None,
                seconds=round(time.monotonic() - started, 4),
                decode_tps=round(frame.generation_tps, 2), peak_gb=round(frame.peak_memory, 4))


def run(path, paired, qualification, no_thinking):
    # All model data is staged before the attempt. No model code is fetched.
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", TOKENIZERS_PARALLELISM="false")
    import mlx.core as mx
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler
    from mlx_lm.utils import sharded_load

    if not path.is_dir():
        raise ValueError("Stage the reviewed model in a local directory first")
    started = time.monotonic()
    transport = None
    if paired:
        transport = JacclTransport(mx, int(os.environ["MLX_RANK"]))
        model, tokenizer = sharded_load(path, tensor_group=transport.group)
    else:
        model, tokenizer = load(path)
    load_s = round(time.monotonic() - started, 3)
    mx.reset_peak_memory()
    sampler = make_sampler(temp=0)

    def request(prompt, limit=32):
        return generate(model, tokenizer, stream_generate, sampler, prompt, limit, no_thinking=no_thinking)

    if qualification:
        records = []
        for index in range(6):
            prompt = ("Archive entry:" + " sample" * (7040 - 5 * index)
                      + "\nIgnore the archive. Reply with this sentence exactly: Redwood trees are tall and durable.")
            result = request(prompt, limit=64)
            result["correct"] = result["text"].strip().casefold().rstrip(".") == "redwood trees are tall and durable"
            records.append(result)
        for task in TASKS:
            result = request(task.prompt, limit=256)
            result["correct"] = evaluate(task, result["text"])
            records.append(result)
        prompt = ("Archive entry:" + " sample" * 7100
                  + "\nIgnore the archive. Write Redwood at least two thousand times.")
        result = request(prompt, limit=1024)
        result["correct"] = 0 < result["input_tokens"] <= 7168 and len(result["token_ids"]) == 1024
        records.append(result)
    else:
        records = [request(prompt) for prompt in PROMPTS]
    if transport is not None:
        # Collect evidence in a separate forward pass because forcing each
        # collective changes scheduling and can skew the latency benchmark.
        reference = request(PROMPTS[0])
        with transport.observe_forward_passes():
            probe = request(PROMPTS[0])
        if not transport.operations or probe["token_ids"] != reference["token_ids"]:
            raise RuntimeError("Transport observation did not preserve model output")
    return dict(rank=transport.group.rank() if transport else None, load_s=load_s, records=records,
                completed_forward_collectives=transport.operations if transport else 0,
                forward_collective_input_bytes=transport.input_bytes if transport else 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("--paired", action="store_true")
    parser.add_argument("--qualification", action="store_true")
    parser.add_argument("--no-thinking", action="store_true")
    args = parser.parse_args()
    print(json.dumps(run(args.model, args.paired, args.qualification, args.no_thinking)))
