"""Create tiny deterministic Qwen MoE tensors for the reviewed two-rank probe."""

import argparse
from hashlib import file_digest
import json
import os
from pathlib import Path
import shutil

from backend.enrollment import private_path
from backend.pair_trial import GIB


PROBE_CONFIG = {
    "model_type": "qwen3_5_moe",
    "text_config": {
        "model_type": "qwen3_5_moe",
        "hidden_size": 128,
        "intermediate_size": 256,
        "num_hidden_layers": 4,
        "num_attention_heads": 4,
        "num_key_value_heads": 2,
        "head_dim": 64,
        "full_attention_interval": 2,
        "linear_num_value_heads": 4,
        "linear_num_key_heads": 2,
        "linear_key_head_dim": 64,
        "linear_value_head_dim": 64,
        "num_experts": 4,
        "num_experts_per_tok": 2,
        "shared_expert_intermediate_size": 256,
        "moe_intermediate_size": 256,
        "tie_word_embeddings": False,
        "vocab_size": 151936,
    },
    "quantization": {"group_size": 64, "bits": 4, "mode": "affine"},
}
TOKENIZER_FILES = ("tokenizer.json", "tokenizer_config.json", "chat_template.jinja",
                   "special_tokens_map.json", "added_tokens.json", "merges.txt", "vocab.json")


def build(tokenizer_source, destination):
    import mlx.core as mx
    import mlx.nn as nn
    from mlx.utils import tree_flatten
    from mlx_lm.models.qwen3_5_moe import Model, ModelArgs
    from mlx_lm.utils import load_tokenizer

    private_path(destination, directory=True)
    if any(destination.iterdir()):
        raise ValueError("Use an empty private probe directory")
    config = json.loads(json.dumps(PROBE_CONFIG))
    tokenizer = load_tokenizer(tokenizer_source, {"trust_remote_code": False})
    answer = tokenizer.encode(" apple", add_special_tokens=False)
    if len(answer) != 1 or not 0 <= answer[0] < config["text_config"]["vocab_size"]:
        raise ValueError("Reviewed tokenizer does not provide the single-token control")
    if type(tokenizer.eos_token_id) is int:
        config["eos_token_id"] = tokenizer.eos_token_id

    mx.random.seed(613)
    model = Model(ModelArgs.from_dict(config))
    for layer in model.language_model.model.layers:
        # Keep the residual stream positive while still executing attention
        # and expert collectives. The synthetic output head has one winner.
        layer.apply(lambda tensor: tensor.astype(mx.float32) * 0.001)
    model.language_model.model.embed_tokens.weight = mx.ones_like(
        model.language_model.model.embed_tokens.weight)
    head = model.language_model.lm_head
    head.weight = (mx.arange(head.weight.shape[0])[:, None] == answer[0]).astype(mx.float32) * (
        mx.ones((1, head.weight.shape[1]), dtype=mx.float32))
    nn.quantize(model, group_size=64, bits=4,
                class_predicate=lambda _, module: hasattr(module, "to_quantized")
                and module.weight.shape[-1] % 64 == 0)
    mx.eval(model.parameters())
    mx.save_safetensors(str(destination / "model.safetensors"), dict(tree_flatten(model.parameters())))
    (destination / "config.json").write_text(json.dumps(config))
    for name in TOKENIZER_FILES:
        source = tokenizer_source / name
        if source.is_file() and not source.is_symlink():
            shutil.copyfile(source, destination / name)
    files = {}
    for path in sorted(destination.iterdir()):
        with path.open("rb") as stream:
            files[path.name] = dict(sha256=file_digest(stream, "sha256").hexdigest(), bytes=path.stat().st_size)
    if sum(item["bytes"] for item in files.values()) > GIB:
        raise ValueError("Synthetic probe exceeds the reviewed transfer ceiling")
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tokenizer_source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    print(json.dumps(build(args.tokenizer_source, args.destination), sort_keys=True))


if __name__ == "__main__":
    main()
