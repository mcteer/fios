# Native acceptance preparation

Status: metadata preparation only,2026-10-31. T051 remains open. This is not an executable plan, resource grant, installation approval or all-client compatibility result.

## Host observations

Both Studios report256GiB physical RAM, `Mac15,14`, `Apple M3 Ultra` through the authorized read-only hardware query. Core's24GiB small-Gemma experiments are separate.

After the operator reboot, edge-a accepts the existing SSH key. A later fixed loopback native `/health` read did not respond (`curl` HTTP000); this does not identify a power state or authorize starting a service. No catalog request followed that failed health read.

Edge-b's fixed loopback `/health` and `/v1/models` return HTTP200/status ok. Its catalog advertises five unloaded entries. No model was loaded or invoked. The filtered observations are retained in `/tmp/fios-009-studio-model-inventory-20261031.log` and `/tmp/fios-009-edge-b-text-model-metadata.log`; installed binary/source identities from older inventory have not been re-established by these HTTP reads.

## Advertised text candidates on edge-b

| Exact ID | Catalog byte figure | Reported state | Advertised inputs |
| --- | ---: | --- | --- |
| `mlx-community/Qwen3.8-Flash-Next-Uncensored-oQ6e-mtp` |150445864519 |unloaded |text, image, video |
| `ddalcu/Qwen3.8-Flash-Next-MLX-Serve-8bit` |137277371312 |unloaded |text, image, video |

Both entries report resident bytes0 and context limits262144. These are catalog metadata, not process/GPU usage, native idle, peak loading requirements or an acceptance context budget. Advertised modalities do not prove model competence. Model locality/enrollment is not inferred from names or a cached entry.

Unloaded but advertised on a healthy serving host means available on demand; this preparation introduces no loaded-only requirement. A future execution still needs fresh own-host health/catalog checks and the exact reviewed host/native binding. Other advertised nontext entries were left unchanged and are not selected by this text preparation.

## Observed configuration and sidecar on edge-b

The following separate read-only file observations apply only to `ddalcu/Qwen3.8-Flash-Next-MLX-Serve-8bit`. They load no model and establish no current memory envelope. Selected metadata is retained in `/private/tmp/fios-009-large-model-metadata-8C7NzX/observation.json`; observations are not an atomic file-set snapshot.

| Configuration | Observed value |
| --- | --- |
| Root/text model types | `qwen4_exp` / `qwen4_exp_text` |
| Architecture | `Qwen4ExpForConditionalGeneration`; vision configuration present |
| Hidden size / layers |2560 /48;36 linear-attention and12 full-attention layers |
| Attention heads / KV heads / head dimension |24 /2 /256 |
| Experts / experts per token |512 /10 |
| Declared text / recurrent dtype | `bfloat16` / `float32` |
| Quantization |8-bit affine, group size64 |
| Hyper-connections / low rank |4 /320 |
| MTP layers |1 |
| PLE embedding / layer IDs |2560 / `[2]` |
| N-gram size / heads / vocabulary base / split parts |3 /8 /20000000 /128 |

The separately observed configuration digest is `3b75deecf2341a23fdd46e0eb36c9ff3c4f4f9d3ff89656c5c5cca142c0824a7`. Declared dtypes and configuration presence do not prove runtime cache precision, vision competence or allocator behavior.

| Selected files | Count | Apparent bytes |
| --- | ---: | ---: |
| Safetensors |101 |137277371312 |
| Separate `ngram_table.bin` |1 |57600276856 |
| Combined selected files |102 |194877648168 |

The catalog figure matches the observed Safetensors sum and excludes this separate table. The combined figure still excludes other configuration/tokenizer/processor files. It is neither resident memory nor a loading-peak measurement. Table CPU/GPU placement, touched pages, working-set/buffer limits, recurrent/MTP state and temporary allocations remain inputs to the future resource plan.

The pinned disposable source has Qwen4-specific config parsing and sidecar handling in `src/model.zig` (observed file SHA256 `7d0a1759ce907cd7c0294279ffa1d587a3dfbab606c61c12da0baa11ef86c6e4`, base `046b647686419df06c6c7132fb1d15d76185c3e5`). At the initial metadata checkpoint this was a source reference only; the parser had not been executed against the configuration. It establishes no installed artifact identity or native compatibility. No values are extrapolated to the other advertised model.

## Ordinary source parser check

A later CPU-only check calls the genuine pinned `parseConfigFromJson` against the same SHA-bound configuration. It passes one selected positive test, validating the actual parsed architecture,48 layers/2560 hidden size,24 attention/2 KV heads/head dimension256,512 experts/10 per token,8-bit/group64 quantization,4/320 hyper-connections, PLE embedding2560 and zero-based layer index1,128 split parts and f32 recurrent state. It creates no tensor or model worker and reads no weights. The JSON-only parser leaves `ngram_table_path` null: disk-based sidecar selection, embedded-versus-separate table use and working pages remain unproven.

```sh
node scripts/check-platform-native-config.mjs --isolated --source /ABS/PRIVATE_NATIVE_SOURCE --zig /ABS/PINNED_ZIG --config /ABS/BOUNDED_CONFIG_COPY.json --sha256 3b75deecf2341a23fdd46e0eb36c9ff3c4f4f9d3ff89656c5c5cca142c0824a7
```

The checker executes only its named positive parser test using actual source modules, with a180s deadline. It records and compares349 declared root/Sushi Zig source inputs before/after, retains private fixture/config/log/receipt data, and removes only its own temporary source helper files. This is a CPU configuration check, not the full upstream build/link/SDK graph or whole-repository/native provenance. The passing receipt is `/private/tmp/fios-009-native-config-cpXfGP/receipt.json` (`/tmp/fios-009-native-config-check.log`). No native server, model inference, installed action, memory-fit or native authority follows; T002/T051 remain open.

## Remaining prerequisites

- Complete T002's actual source/native all-client non-preemption and completion contract; observations and successful core responses do not satisfy it.
- Establish current installed/running source and artifact identities for each Studio, not just an application version or catalog response.
- Restore edge-a's serving readiness through the operator's separately authorized workflow before choosing any model there; no automatic restart follows this document.
- Review a large-model envelope on each host, including peak preparation, sidecar placement/working pages, recurrent/MTP and KV/cache state, existing native allocations, VM reservations, native headroom and finite request/process bounds. File sizes do not establish this envelope.
- Prepare a separate Studio-bound runner/plan after those inputs are reviewed. The existing fixed core Gemma runner must not be repurposed to load these models or to claim Studio acceptance.
- Obtain the separately scoped scenario/resource and installed lifecycle approvals before T051's operational execution. Keep008 parked; no RDMA/network changes or merge follow from this preparation.

Current normal source checks remain in the quickstart and validation record. Their unknown/unsupported outcomes, independent inference uncertainty and inactive development packages remain unchanged.
