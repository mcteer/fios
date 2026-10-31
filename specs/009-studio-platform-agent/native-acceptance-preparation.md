# Native acceptance preparation

Status: metadata preparation only,2026-10-31. T051 remains open. This is not an executable plan, resource grant, installation approval or all-client compatibility result.

## Host observations

Both Studios report256GiB physical RAM, `Mac15,14`, `Apple M3 Ultra` through the authorized read-only hardware query. Core's24GiB small-Gemma experiments are separate.

After the operator reboot, edge-a accepts the existing SSH key. A later fixed loopback native `/health` read did not respond (`curl` HTTP000); this does not identify a power state or authorize starting a service. No catalog request followed that failed health read.

Edge-b's fixed loopback `/health` and `/v1/models` return HTTP200/status ok. Its catalog advertises five unloaded entries. No model was loaded or invoked. The filtered observations are retained in `/tmp/fios-009-studio-model-inventory-20261031.log` and `/tmp/fios-009-edge-b-text-model-metadata.log`; installed binary/source identities from older inventory have not been re-established by these HTTP reads.

## Advertised text candidates on edge-b

| Exact ID | Reported disk bytes | Reported state | Advertised inputs |
| --- | ---: | --- | --- |
| `mlx-community/Qwen3.8-Flash-Next-Uncensored-oQ6e-mtp` |150445864519 |unloaded |text, image, video |
| `ddalcu/Qwen3.8-Flash-Next-MLX-Serve-8bit` |137277371312 |unloaded |text, image, video |

Both entries report resident bytes0 and context limits262144. These are catalog metadata, not process/GPU usage, native idle, peak loading requirements or an acceptance context budget. Advertised modalities do not prove model competence. Model locality/enrollment is not inferred from names or a cached entry.

Unloaded but advertised on a healthy serving host means available on demand; this preparation introduces no loaded-only requirement. A future execution still needs fresh own-host health/catalog checks and the exact reviewed host/native binding. Other advertised nontext entries were left unchanged and are not selected by this text preparation.

## Remaining prerequisites

- Complete T002's actual source/native all-client non-preemption and completion contract; observations and successful core responses do not satisfy it.
- Establish current installed/running source and artifact identities for each Studio, not just an application version or catalog response.
- Restore edge-a's serving readiness through the operator's separately authorized workflow before choosing any model there; no automatic restart follows this document.
- Review a large-model envelope on each host, including peak preparation, KV/cache, existing native allocations, VM reservations, native headroom and finite request/process bounds. Disk size does not establish this envelope.
- Prepare a separate Studio-bound runner/plan after those inputs are reviewed. The existing fixed core Gemma runner must not be repurposed to load these models or to claim Studio acceptance.
- Obtain the separately scoped scenario/resource and installed lifecycle approvals before T051's operational execution. Keep008 parked; no RDMA/network changes or merge follow from this preparation.

Current normal source checks remain in the quickstart and validation record. Their unknown/unsupported outcomes, independent inference uncertainty and inactive development packages remain unchanged.
