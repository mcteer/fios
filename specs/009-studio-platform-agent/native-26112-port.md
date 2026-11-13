# Existing native boundary port to26.11.2

Status: source preparation in progress; no ported native contract or activation authority. Whole tasks remain38/55. This ports the existing009 ownership/control integration to the installed upstream version. It adds no model engine, model/modality support, routing policy or frontend feature.

## Exact inputs

| Input | Identity |
| --- | --- |
| MLX-Serve | 4e231ceebe63308cc038117d40b9f9b64bd0372e /26.11.2 |
| MLX | c69303b00f5f61860436e832f23fa8c34b96f93a |
| mlx-c | 56b2d39fc831f2c0eb5bb94d82ef7191f7b31fa6 plus the vendor build recipe’s gather/global-scale patch |
| DS4 | 9139e2ae58a41503968a500f36f75895c1ba63fc |
| opencode module | e90093a161c040c144a6adedff0deab9d078c7cc |
| Zig | 0.17.0, executable SHA1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523 |
| CMake | 4.2.3, executable SHA08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490 |
| SDK/Metal | 27.2 / Apple Metal32023.922, genuine installed toolchain |
| Llama library | b11429, SHA10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b |
| WebP source | 4fa21912338357f89e4fd51cf2368325b59e9bd9 /1.6.0 |

Private work is `/private/tmp/fios-009-port-26112-ft5mnlcq/source`, branch `fios-009-port-26112`; the clean reference stays separate. All4 submodules are fetched at exact pins without LFS model downloads. The vendor MLX/MLX-C SDK build passes in247.303s with two jobs, generated real NAX shader data and macOS26.2 deployment target. Only the private build recipe’s job count changes; its original/bounded hashes and actual vendor dependency patch are recorded. This is a dependency baseline, not the old instrumented64ea011 SDK or its owner/device proof.

Receipts are `mlx-build-inputs.json`, `mlx-build-receipt.json`, `tool-inputs.json` and `webp-build-receipt.json` in the private parent. WebP builds in7.752s into that parent. The full native baseline links30/30 steps in431.592s with two jobs/1200s observation deadline, MAS/no-model-pull build and explicit26.11.2 source-baseline version. Largest reported compile-step RSS is3GiB; this is not an aggregate host peak. Input/completion receipts and log are `native-build-inputs.json`, `native-build-receipt.json`, `native-build.log`. Binary SHAaebb6409ad15cafde5a8afc480eef723eb64caa89a6ce416d877fd830639eed0; `--version` succeeds and reports MLX0.32.5/NAX off on M4. The build itself starts no server/model. A subsequent bounded private empty-model server has health200/empty catalog but no private ingress socket (`CURRENT_NATIVE_INGRESS_INTERFACE_MISSING`, `ingress-prior.log`). The first HTTP connection-only port builds30/30 steps in395.356s, binary SHA fbc5a4aee7741d0185f7cc8d78dd0b809ab4bb80d6c9a0ef6a29f739ee12267e (`ingress-build-inputs.json`, `ingress-build-receipt.json`, `ingress-build.log`). It passes actual empty-model health/catalog, private protocol3, a single accepted HTTP connection appearing in the same host ledger, and its original HTTP custody retirement. The canonical core-only wire fixture receipt is `/private/tmp/f9-cur-ingress-pl37x0va/receipt.json`. A separate current Swift manager/CLI run authenticates the actual native PID/start/image, receives current source captures and reports native admission unsupported (`/private/tmp/f9-cur-ingress-dqzxpz0i/receipt.json`, `ingress-manager.log`). These are not backend/device/terminal or all-client admission proof. An initial raw wire fixture omitted the required write-half-close and timed out; the corrected caller passes without changing transport.

## Source relocation

| Existing integration | Current upstream location |
| --- | --- |
| Process entry/startup reservation | `src/main.zig` |
| HTTP ingress, exact local target/process binding | `src/host/http/server.zig` and the called host API handlers |
| Registry/model transition/reference custody | `src/host/registry/registry.zig` |
| Former single scheduler | `src/host/gpu_thread/scheduler.zig` and `src/engines/mlx/scheduler.zig` |
| MLX FFI/transformer | `src/mlx/ffi.zig`, `src/engines/mlx/transformer.zig` |
| DS4 wrappers | `src/engines/ds4/{engine,bridge,ffi,load,round}.zig` |
| Llama wrappers | `src/engines/llama/{engine,bridge,ffi,load,policy}.zig` |
| Stream module integration | `src/engines/mlx/modules/mlx_stream.zig`, `src/mlx_stream.zig` |
| Model discovery | `src/host/registry/discovery.zig` |
| Shared serving-engine interface | `src/abi/engine.zig`, `src/host/engines/served.zig` |

The old18-path patch fails a read-only applicability check. A path rename is insufficient: the default build now separates host, MLX engine and plugin compilation units. Importing a fresh copy of the request tracker in each unit would partition ownership and cannot supply a coherent process source. One host-owned origin ledger must remain original across reviewed callbacks/opaque retained origins. The current ABI1 `finished` event and void `close` callback alone prove neither device completion nor a retained native reservation.

## Required implementation checks

- Preserve the public ABI1 layout and explicit unsupported behavior. Any private host/engine callback surface needs exact generation/identity/lifetime binding; missing callbacks or legacy/uncovered participants remain unknown. No authenticated frame or package flag grants all-client coverage.
- Port process startup and common ingress/target/epoch correlation first, with private empty-model server/manager checks. Cover asynchronous host media jobs and WebSocket lifetime; response completion is not backend retirement.
- Carry original request/model/engine/context custody through preparation, execution, cleanup, errors and cancellation. Checked refusal retains original references and uncertainty. Preserve SDK/dependency origins across worker and compilation-unit boundaries; no sampled counters or local reaping substitute for native terminal proof.
- Port registry/model transitions and safe non-preemption before any positive native admission claim. Ordinary idle replacement stays allowed; no admin load/unload, model substitution, warmup, replay or new model-policy behavior follows from the port.
- Version source-build/capsule declarations around actual new inputs. Retain old26.10.3 artifacts as historical candidates. No old dependency receipt, empty-model fixture, backend flag or uninstrumented vendor baseline is promoted to current all-client/installed acceptance.
- Continue ordinary correctness checks only. Installed activation, privileged/disruptive acceptance and both-Studio scenarios remain separately gated. Small-model tests belong only on core; there is no Studio small-model substitution or cybersecurity campaign.

These are implementation requirements, not completed checks. T002/T018–T022 and the dependent runtime/lifecycle/release tasks remain open. Only the HTTP connection/control slice is ported. Backend/model/device custody, startup reservation, bound local-target/correlation guards and the complete native contract remain unported.

## Reproduce the first slice

The [six-path source patch](../../platform/studio/native/mlx-serve-26.11.2-ingress.patch) SHA82cdd7521f7513e242f662963dd77b20870e2d7f67f72f47b37bf49ac2748f00 applies to the exact clean4e231ce reference. It changes only the two HTTP integration files and adds four byte-identical existing project companions; a mock-only Node check enforces that scope and byte identity. No engine implementation changes. The actual fixture exercises one ordinary accepted connection, not a traffic/fault campaign.

After the exact genuine dependency preparation above, apply the patch in a new private source tree. Build with:

```sh
.zig-toolchain/zig build -j2 -Doptimize=ReleaseFast -Dmas=true -Dversion=26.11.2-fios-source-fixture -Dwebp-prefix=ABS_PRIVATE_WEBP_PREFIX --summary all
```

On core, execute the bounded wire fixture against the reviewed private binary:

```sh
.venv/bin/python -I -B tests/fixtures/platform/current-native-ingress.py --isolated ABS_PRIVATE_BINARY REVIEWED_BINARY_SHA256
```

The fixture is not a build/source attestor, a package installer or a native admission issuer. It explicitly reports no kernel peer authentication proof; the separate actual Swift manager receipt supplies that transport check. Health, connection retirement and local child reaping never clear native inference uncertainty. All private state is retained; original children are stopped without touching installed services. No model POST is issued.

## Expected-process consistency slice

The separate [instance addition](../../platform/studio/native/mlx-serve-26.11.2-instance.patch), SHA2e998f1f1fa2d3f98bb5708ed3ab351e8d5f1b454dcb077219bdd11e21d94e3a, applies after the ingress patch on the exact current base. It changes only the router and a private header parser. The parser preserves the existing optional lowercase32-hex/nonzero/duplicate refusal rules. A supplied stale instance returns409 before model resolution or provider/LAN forwarding; unavailable tracking returns503. A matching instance is consistency metadata, not admission. Header-absent behavior stays unchanged.

Actual pre-change empty-model failure is `CURRENT_NATIVE_STALE_EPOCH_NOT_REJECTED` (`instance-prior-final.log`). Full native rebuild passes30/30 in177.268s; binary SHA95c8dc54b56c2bd48e892c37bc2259bca1c3ebebd8ca8f186f4fc871d14df98c. Canonical core-only fixture passes with `--expected-instance`:3 POSTs for the same unregistered fixture model,0 inference, stale409 and matching-vs-legacy missing-model control (`/private/tmp/f9-cur-ingress-yxvcjr56/receipt.json`, `instance-canonical.log`). This is not model competence, correlation, safe model replacement, startup reservation, backend retirement or atomic admission. Exact local-target/alias binding is still unported.

```sh
# In a fresh exact source tree, apply ingress then instance additions.
.venv/bin/python -I -B tests/fixtures/platform/current-native-ingress.py --isolated ABS_PRIVATE_BINARY REVIEWED_BINARY_SHA256 --expected-instance
```

The optional flag records all3 actual model POST attempts; they reject against an empty model directory and do not invoke a model. Source integrity2/2 and exact sequential patch application pass. No installed service or Studio inference is exercised.
