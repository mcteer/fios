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

These are implementation requirements, not completed checks. T002/T018–T022 and the dependent runtime/lifecycle/release tasks remain open. The HTTP connection/control, expected-process and exact local-target slices are ported as detailed below. Backend/model/device custody, correlated native completion and the complete native contract remain unported. Optional ingress correlation metadata is supplied by the later addition below. The private startup-exclusion addition below supplies process reservation, without current installed activation.

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

Actual pre-change empty-model failure is `CURRENT_NATIVE_STALE_EPOCH_NOT_REJECTED` (`instance-prior-final.log`). Full native rebuild passes30/30 in177.268s; binary SHA95c8dc54b56c2bd48e892c37bc2259bca1c3ebebd8ca8f186f4fc871d14df98c. Canonical core-only fixture passes with `--expected-instance`:3 POSTs for the same unregistered fixture model,0 inference, stale409 and matching-vs-legacy missing-model control (`/private/tmp/f9-cur-ingress-yxvcjr56/receipt.json`, `instance-canonical.log`). This is not model competence, correlation, safe model replacement, startup reservation, backend retirement or atomic admission. Exact local-target/alias binding was unported at this historical slice; the addition below supplies that consistency guard.

```sh
# In a fresh exact source tree, apply ingress then instance additions.
.venv/bin/python -I -B tests/fixtures/platform/current-native-ingress.py --isolated ABS_PRIVATE_BINARY REVIEWED_BINARY_SHA256 --expected-instance
```

The optional flag records all3 actual model POST attempts; they reject against an empty model directory and do not invoke a model. Source integrity2/2 and exact sequential patch application pass. No installed service or Studio inference is exercised.

## Exact local-target consistency slice

The [target addition](../../platform/studio/native/mlx-serve-26.11.2-target.patch), SHA3be0da0bcd19dcd6f350777416be13fdc684f13bbbf9c923c484e5156e636741, applies after ingress and instance additions. Only the host router changes. Instance-bound chat requests select the decoded top-level JSON model string, retain that allocation through response handling and require an exact locally registered ID, including unloaded entries. Default names, paths that are not exact registered IDs and mutable aliases cannot substitute another target. Configured provider/LAN forwarding is refused for bound requests. Header-absent legacy selection remains unchanged. This is target consistency, not atomic admission or safe replacement.

Actual pre-change failure `CURRENT_NATIVE_BOUND_TARGET_USED_LEGACY_SELECTION` is retained in `target-prior.log`. Full native build passes30/30 in491.685s; binary SHA76958f4b162aba0bf1993bbeebc41035f385a0f6c85478b8d89c4fd27b607ba8. Canonical core-only `--exact-target` fixture passes7 POST attempts against the empty registry: stale-instance409, bound missing-ID404, legacy control, nested-only field, nonstring field, escaped ID and default-name refusal. No model executes. Receipt `/private/tmp/f9-cur-ingress-_hrfgbmr/receipt.json`; log `target-canonical.log`. The fixture does not prove a successful registered-ID dispatch or runtime provider/LAN refusal. In particular `-Dmas=true` disables provider startup in this vendor build.

```sh
# Apply ingress, instance, then target additions to the exact current source.
.venv/bin/python -I -B tests/fixtures/platform/current-native-ingress.py --isolated ABS_PRIVATE_BINARY REVIEWED_BINARY_SHA256 --exact-target
```

The earlier `--expected-instance` matching-vs-legacy control describes the historical instance-only slice. Use `--exact-target` for the combined target patch, whose bound missing-ID behavior intentionally differs from legacy selection. Source-input integrity3/3 and sequential patch application pass. Working-tree application build,106 Node tests,106 installed Python tests and17 Chromium regressions pass; this working tree includes preserved unrelated frontend/spec003 edits and is not an exact clean-commit receipt. No installation or all-client/backend authority follows.

## Private startup exclusion slice

The [startup addition](../../platform/studio/native/mlx-serve-26.11.2-startup.patch), SHA31922ef9e4ccabcac17b5dc0b039e4f7f72e2ababa2a410e221850c1f1b89c21, applies after the first3 layers. It changes only `src/main.zig` and adds the byte-identical existing `startup_guard.zig`. The guard runs before model-capable subcommands/backend setup; exact metadata calls keep the existing report fields through an extracted helper. No engine implementation changes. The shared companion still explicitly recognizes only the historical26.10.3 installed version, so this addition does not enable current26.11.2 installed startup. The current source fixture uses the existing explicit private-HOME opt-in.

Actual pre-change `CURRENT_NATIVE_STARTUP_RESERVATION_MISSING` follows two healthy ordinary empty-model servers sharing the same private reservation namespace but using different loopback ports and no second control transport; `startup-prior.log` and `/private/tmp/f9-cur-ingress-jxoi_61p` are retained. Native rebuild passes30/30 in49.571s; binary SHA05ddebef24de6f81420a13199b6bd46e7845073d9202666d0b6760e1269db7b9. Canonical `--startup` fixture passes metadata while the original owns the lock, duplicate refusal by `StartupGuardUnavailable`, original health preservation and normal reacquisition after the original process has exited. Receipt `/private/tmp/f9-cur-ingress-mcb0qd_l/receipt.json`, `startup-canonical-final.log`;0 model POSTs/inference. This is neither all-client activity nor terminality proof. Original child cleanup leaves independent native uncertainty untouched.

```sh
# Apply ingress, instance, target, then startup additions to the exact source.
.venv/bin/python -I -B tests/fixtures/platform/current-native-ingress.py --isolated ABS_PRIVATE_BINARY REVIEWED_BINARY_SHA256 --startup
```

The combined binary also passes `--exact-target` again (7 empty-registry POSTs,0 inference; `startup-target-regression.log`). Source-input integrity4/4 and sequential patch application pass. CI run43343784441 is green for earlier pushed2a3a7a9, not these later additions. Whole-task count remains38/55. No installed lifecycle, approved launch, safe model replacement, request correlation, backend retirement or atomic native admission is claimed.

The actual current Swift manager also authenticates this combined source process through PID/start/path/image binding and receives its ingress frame: `/private/tmp/f9-cur-ingress-n7w7tee9/receipt.json`, `startup-manager.log`. Status preserves `native_admissions:unsupported` separately from `native_ingress_admissions:admissionsOpen`;0 model POSTs,0 installed actions. Earlier target-only manager receipt is `/private/tmp/f9-cur-ingress-tv77yqi_/receipt.json`.

## Ingress correlation and pre-enqueue custody slice

The [correlation addition](../../platform/studio/native/mlx-serve-26.11.2-correlation.patch), SHA75c23f06c0cc7986d4af9bc8af2f222f501b1cc53751653c7f30ec8732780a23, applies after the first4 layers and changes only3 host HTTP files plus a private parser. The accept loop now enrolls the original ingress root before enqueue/spawn and transfers it to the thread; failures close the original socket/args before checked root release. The thread retains that root through original socket and argument cleanup, with explicit thread-local custody for the router. Optional `X-Fios-Request-ID` association occurs after existing authentication/LAN/process checks. Malformed/duplicate headers refuse; live identity conflicts refuse409. This is opaque metadata, not authorization, deduplication/retry permission or native completion. Header-absent traffic stays supported.

Actual pre-change failure `CURRENT_NATIVE_CORRELATION_HEADER_IGNORED` is retained in `correlation-prior.log`. The first build failed at import placement before the vendor's file documentation comment; that compiler failure is retained as attempt1 and is not a behavioral regression. Corrected full build passes30/30 in181.747s; binary SHA4d0ee72a60ba7d6ffb6f33e5c5b655d935328c203aa2887c520b702a7c556082. The exact native parser component passes1 test; the standalone ownership file runs0 tests and is not promoted to test evidence. A separate actual ownership component contract passes1 test for retained original lineage, conflicting live association and unknown missing records (`correlation-custody-component.log`).

Canonical core-only `--correlation` passes9 empty-registry POST attempts per run (0 inference), including malformed refusal and valid association preserving target refusal. The final run also reads the actual private lineage frame after the original HTTP root retires and requires missing/uncertain rather than terminal/not-sent. Receipt `/private/tmp/f9-cur-ingress-6der_npi/receipt.json`, `correlation-canonical.log`; the earlier run is retained separately. The held connection still exercises one composed host ledger. Source pre-enqueue placement is reviewed/compiled, but delayed-thread and complete enabled-modality acceptance remain open. `--startup` regression passes against the combined binary (`/private/tmp/f9-cur-ingress-6p4zhkoz/receipt.json`, `correlation-startup.log`). Source-input integrity5/5 and sequential patch application pass.

```sh
# Apply ingress, instance, target, startup, then correlation additions.
.venv/bin/python -I -B tests/fixtures/platform/current-native-ingress.py --isolated ABS_PRIVATE_BINARY REVIEWED_BINARY_SHA256 --correlation
ABS_REVIEWED_ZIG test -lc --dep ownership -Mroot=ABS_REPO/tests/fixtures/platform/current-native-correlation.zig -Mownership=ABS_PRIVATE_SOURCE/src/fios/request_ownership.zig
```

No primary model/device origin, async-media/WebSocket custody, SDK/backend enrollment, safe destructive transition, all-client source authority, correlated native terminality or atomic native admission is supplied. The genuine current MLX SDK remains the uninstrumented vendor SDK. T002/T018–T022 remain open; whole count38/55. Native installation and lifecycle remain closed.

Actual current manager authentication/ingress-status composition also passes on the combined correlation binary (`correlation-manager.log`; private receipt path retained in that log). It reports native admission unsupported and ingress open separately, with no model request or installed action.

## Diagnostic primary-model phase slice

The [primary addition](../../platform/studio/native/mlx-serve-26.11.2-primary.patch), SHAb633dc8da18143de358b773055bd1cc16fafea3f8f027ecc2731ce443bb3d74d, applies after5 earlier layers. It changes only the host router and startup integration. With tracked ingress it resolves the actual registered model identity before common CPU preparation/cold loading, keeps that exact entry ID for loading, records preparing→active→responding and retains the root through the existing original cleanup. Header-absent and nontracked ordinary vendor traffic remain supported. Earlier/special admin/media/async paths are not thereby enrolled. No SDK/engine/ABI implementation changes.

The canonical shared serving tracker defaults its primary guard to true, unlike local `Tracker` fixture construction. Review caught that distinction before this candidate was accepted. This addition explicitly sets the current shared guard false during trusted startup, before any tracker operation, because the host-only port must remain diagnostic and must not impose incomplete cross-model policy. The first compiled candidate is retained as `binding-build-attempt1*` and is not the accepted source candidate. The final full build passes30/30 in258.725s; binary SHAc3c9e770c7b0840a9846026ed4e18bcfb26d9541fddff9192b050ea4eff27c8b. Its declared changed inputs and binary match after build; that bracket is not whole-native provenance.

The component fixture now passes2 tests, including exact-case model identity, each primary request phase and retention through the original last reference (`binding-component-final.log`; the earlier fixture field-name compilation error is retained separately). These test metadata, not devices or successful native model dispatch. Actual combined-binary checks pass9 empty-registry correlation/target POSTs and actual missing-lineage-is-unknown (`/private/tmp/f9-cur-ingress-vyc_7nqn/receipt.json`), private startup regression (`/private/tmp/f9-cur-ingress-o1p4fp95/receipt.json`) and actual manager authentication/status (`/private/tmp/f9-cur-ingress-ijsvjo0p/receipt.json`). Logs are `binding-{correlation,startup,manager}.log`. All run0 inference and0 installed actions. These empty-registry HTTP cases do not enter positive primary-model binding. Source-input integrity6/6 and sequential patch application pass; positive registered-model/model-replacement, enabled-modality and complete lifetime acceptance remain open.

The current vendor ABI's optional `Admission` table prices context/memory and idle eviction; it is not an authenticated all-client ownership/reservation issuer. Its `admit` boolean, public `finished` event and void `close` callback cannot be promoted to the missing native contract. The genuine current MLX SDK still has no Fios origin enrollment. No current-source all-client/terminal/admission authority or installed activation is supplied; T002/T018–T022 remain unchecked and whole count38/55.

## Current MLX dependency ownership component

The separate [c69303b SDK patch](../../platform/studio/native/mlx-c69303b-owner-uncertainty.patch), SHA27cef3dc0bbd66b2c4279e30ec0e3d0332d34f8f7079a01b0db3e025f43a4f6a, rebases the historical cumulative owner/uncertainty hooks onto exact current MLXc69303b00f5f61860436e832f23fa8c34b96f93a. It changes7 existing SDK paths, not model engines. The historical patch failed on current Metal includes/compile-options/debug-graph contexts; rejected hunks remain outside the source tree. The rebase preserves the current custom-kernel include, GPU-architecture selection, `fast::CompileOptions` and debug graph validation. Exact fresh-base patch application passes.

A genuine CMake4.2.3 build with2 jobs passes in229.705s at `/private/tmp/fios-009-mlx-c693-port-jhy3gkva`. It uses SDK27.2/Metal32023.922, deployment target26.2, exact local JSON9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03/fmt407c905e45ad75fc29bf0f9bb7c5c2fd3475976f and genuine Metal-CPP26 archive SHA4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4. Fresh extraction matches every header input. Build is shared Release, CPU/Metal/safetensors enabled, GGUF/Python disabled and Metal JIT **off**, matching the observed current default. No synthetic SDK stamp/library is used. Exact7 declared source hashes match after build; this is not whole-native provenance.

The [ordinary component fixture](../../tests/fixtures/platform/current-mlx-ownership.cpp), SHAaaaeb565764ecb853ccad9d27ea926056c03ff14dee86fa332738155abd8ebdf, fails to link against the genuine uninstrumented current vendor library with undefined ownership symbols (`baseline-link.log`). Initial fixture compilation errors are retained as earlier attempts and are not the functional missing-interface evidence. Against the genuine candidate library, Debug and optimized clients pass a CPU scalar computation, bounded observation of original host callback retirement and normal same-creator source-component hold/release. A third process passes the genuine CPU safetensors scalar roundtrip. No model, GPU dispatch, fault/mutation campaign or installed action occurs. SDK library is Release in both client modes; these are not two SDK build configurations. Actual library SHA2b2fdb6642f2a1dcd75195c02ac2af321bb06f1f13e2387783bd66b979421f5b. `ordinary-receipt.json` binds these3 processes and component scope; it is not model competence or device terminal proof.

Data-only `sdk-review/` contains the3 actual retained library/metallib files and canonical `candidate.json`, review SHAc158b76f76e0f9c97246a283963f96b8ca35cb3bbe73de5e50453838c315bd18. The separate current-generation [reader](../../scripts/lib/platform-current-mlx-source-review.mjs) verifies exact source/patch/artifact identities without loading a library, rejects historical source generations and keeps all authority/activation/installed/inference/terminal flags false. Actual retained-data verification and3 mock-only metadata tests pass. Historical readers/receipts are unchanged. Seven source-path integrity tests pass; they are not native behavior proof.

Reproduce in an owned private exact source checkout, applying only the current SDK patch. Use the existing exact local dependency inputs above and full Xcode per-command environment:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ABS_PINNED_CMAKE -S ABS_CURRENT_MLX_SOURCE -B ABS_PRIVATE_BUILD -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=26.2 -DBUILD_SHARED_LIBS=ON -DMLX_BUILD_TESTS=OFF -DMLX_BUILD_EXAMPLES=OFF -DMLX_BUILD_PYTHON_BINDINGS=OFF -DMLX_BUILD_SAFETENSORS=ON -DMLX_BUILD_GGUF=OFF -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DFETCHCONTENT_SOURCE_DIR_JSON=ABS_PINNED_JSON -DFETCHCONTENT_SOURCE_DIR_FMT=ABS_PINNED_FMT -DFETCHCONTENT_SOURCE_DIR_METAL_CPP=ABS_VERIFIED_METAL_CPP
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ABS_PINNED_CMAKE --build ABS_PRIVATE_BUILD -j 2
# Build library only; never install it into the system or installed app.
```

Actual finite orchestration inputs/build/link/client logs remain in that private parent. The component is not composed into the current native server, whose SDK remains genuine and uninstrumented. GPU buffer/shared-event/origin callbacks, current scheduler/model/registry/native ABI bridge, other native backends and all-client acceptance remain unproven. This candidate supplies no native reservation issuer or installation permission. T002/T018–T022 stay open;38/55 whole tasks complete.

## Current SDK/native CPU owner composition

The existing source SDK host-owner driver now has an explicit `--current-sdk` mode. The initial CPU checkpoint selected the separate current-generation reader and only the healthy CPU scenario. The ordinary Metal extensions below retain healthy-only execution and continue rejecting callback-error, cleanup-error and abandoned-buffer variants. Historical metadata readers/default fixtures remain separate. This opt-in is a development input selector, not native admission or installed enrollment.

Actual current SDK/native ownership composition passes Debug and ReleaseSafe with the genuine retained SDK reviewc158b76f76e0f9c97246a283963f96b8ca35cb3bbe73de5e50453838c315bd18 and canonical actual `request_ownership.zig`/`sdk_request_ownership.zig`. Each mode runs2 genuine CPU callbacks: a parent and another spawned by the original captured object's destructor. The original connection reference is released while the real callback remains held; both original and nested callbacks still see the original native owner/context/root. Normal cleanup retires those contexts afterward. Receipt `/private/tmp/fios-009-sdk-host-owners-6kfFPv/receipt.json`; aggregate log `/private/tmp/fios-009-mlx-c693-port-jhy3gkva/native-owner-composition.log`. Network is denied,0 model/Metal operations,0 installed actions. Fixture PASS text is shared with the historical driver: only `healthy` actually ran here, so it is not current cached-fence/error evidence.

```sh
node scripts/check-platform-sdk-host-owners.mjs --isolated --sdk ABS_CURRENT_SDK_REVIEW --sha256 REVIEW_SHA256 --source ABS_CURRENT_MLX_SOURCE --zig ABS_REVIEWED_ZIG --developer-dir /Applications/Xcode.app/Contents/Developer --current-sdk
```

This composes the genuine CPU SDK callback and native tracker implementation, not the current HTTP server/scheduler or all enabled modalities. It does not establish native device/model completion, all-client non-preemption or a reservation issuer. Whole tasks remain38/55; T018/T021/T022 remain open.

## Current ordinary Metal and distinct-origin composition

The explicit current driver now also accepts the ordinary empty-Metal and separate-encoding-origin fixtures on core. Only `healthy` runs; callback-error/stream-cleanup-error/abandonment and historical cached-fence cases remain excluded. No shader dispatch or model is present. C++ clients use `NDEBUG` to match this genuine Release SDK's conditional Metal class layout; Zig Debug/ReleaseSafe test checks remain active.

Actual ordinary Metal composition passes both modes with1 genuine private command buffer/shared event and1 destructor-enqueued CPU callback per mode. Two original native roots remain retained after their original connection references leave, through the real buffer wait/completion/captured-object cleanup and nested CPU work. Receipt `/private/tmp/fios-009-sdk-host-owners-1TBxZs/receipt.json`, `native-metal-owner-composition.log` in the c693 private parent. This is original participant lifetime, not global GPU completion or native terminal proof.

The distinct-origin fixture separately passes both modes: first-origin encoding retains its original root before any completion callback/commit exists; a later independent request contributes a second origin into that same buffer; both remain through completion and nested cleanup. Receipt `/private/tmp/fios-009-sdk-host-owners-7VRy0w/receipt.json`, `native-buffer-origin-composition.log`. The known current SDK source/artifact review is unchanged and reverified after every run.0 models/installed actions, network denied, no fault/mutation campaign. Core-only component results do not establish Studio inference/resource acceptance.

```sh
# Same explicit current SDK/source/Zig/developer arguments as the CPU command:
# add --metal --metal-cpp-zip ABS_VERIFIED_METAL_CPP_ZIP
# or --buffer-origins --metal-cpp-zip ABS_VERIFIED_METAL_CPP_ZIP
```

SDK/native callback components are now exercised for these positive paths, but current HTTP/scheduler/load/slot/model/native ABI bridge, other enabled backends/modalities, independently uncertain/cancellation/destructive transitions and all-client admission still remain uncomposed/unproven. Whole count38/55; no whole task is completed by these scoped component receipts.

## Load queue ownership handoff

The [load-origin addition](../../platform/studio/native/mlx-serve-26.11.2-load-origins.patch), SHA71dfecc82f899d39b0d66b176bee763c8f75a30924748121d6755be1f88c030d, applies after the6 host layers. It adds a byte-identical [queued scope](../../platform/studio/native/queued_request_ownership.zig) and changes existing request/scheduler/load-worker metadata only. It implements no model engine or new load/eviction policy. Sender origin storage survives the existing uncancelable `done` wait; GPU/ANE workers clone original references before effects, keep worker-local token storage through cleanup and restore prior TLS. ANE requeue/fallback retains the sender while `done` is false. Known native uncertainty prevents conditional metadata release. No acknowledgement is native terminal proof.

A genuine current-SDK component tests this exact helper across an actual native thread: sender references finish after worker capture, work acknowledgement precedes worker exit, and original roots remain through genuine SDK parent/destructor-enqueued callbacks. Debug and ReleaseSafe pass (`/private/tmp/fios-009-sdk-host-owners-wlryWr/receipt.json`, c693 parent `native-queued-owner-composition.log`);0 models/Metal/installed actions. The explicit current driver `--queued` is healthy CPU-only and cannot select error/Metal/abandonment variants.

```sh
# Same reviewed current SDK/source/Zig/developer arguments as other components:
# add --current-sdk --queued
```

Full current native build passes30/30 in242.485s, binary SHAda407b25bef9d38c00598e602a98aebb7881c1e3c992f618b87d869ef5f272fa. Declared changed inputs match after build. Empty-registry correlation9-POST/unknown-lineage, startup and actual manager authentication regressions pass (`custody-{correlation,startup,manager}.log` in the current native parent),0 inference/installed actions. Sequential patch application,8 source-input and3 current-metadata tests pass. These empty-registry tests do not enter positive cold-load/ANE paths or establish their cross-compilation-unit/global/context lifetime. The full server still uses its uninstrumented vendor SDK; source SDK/native bridge, slots, model/registry/destructive transitions, other modalities/backends and all-client admission remain uncomposed/unproven. T018/T021/T022 remain open;38/55 whole tasks complete.

## Shared ownership across compilation units

The actual full load-origin binary revealed2 distinct private `request_ownership.shared` data objects. That meant the preceding standalone queue component could pass while host/engine attribution was still partitioned. Those earlier receipts were intentionally not promoted to positive model-load/current-server proof.

The [unit-ownership addition](../../platform/studio/native/mlx-serve-26.11.2-unit-ownership.patch), SHAe7b7f672136e3a65cfbe53bc53e109e36151f685e3d1c2b44d6863458e748744, applies after the7 previous host/load layers. It adopts the exact upstream `Shared`/`SharedThreadLocal` storage mechanism and registers the ledger/current-token/current-group types in `shared_all.zig`. Current callers use pointer getters; engine/plugin objects resolve the host-owned ledger and the current thread's host-owned TLS slot, never a cached other-thread slot. Historical canonical companions and old capsules are unchanged; this is a separate current API/storage adapter, not native authority.

The actual separate-object [fixture](../../scripts/check-platform-native-ownership-units.mjs) reproduces `FIO_NATIVE_LEDGER_PARTITIONED` before the fix (`unit-ownership-prior.log`, retained `/private/tmp/fios-009-ownership-units-YKq3gz`). Corrected Debug/ReleaseSafe pass (`unit-ownership-current.log`, `/private/tmp/fios-009-ownership-units-XUQ3XX/receipt.json`). It compiles the actual current ownership/queue sources and byte-exact upstream shared helper SHA d3154ceda0ba5f2fb5f0ec2c6ddbcb52f6cfe1f7e82e678d21ac3bec0a478338 as genuine host/unit objects; compatibility accessors observe either real API generation, not substitute state. It verifies ledger address identity, host/unit token/group visibility and worker-thread scope/restoration without leaking the parent's TLS. Network denied,0 SDK/model/hardware/installed actions.

```sh
node scripts/check-platform-native-ownership-units.mjs --isolated --source ABS_CURRENT_NATIVE_SOURCE --zig ABS_REVIEWED_ZIG
```

Full native build passes30/30 in191.786s; binary SHA8f76a345329485387d1efc18da1bb258a1037631fd2bcf098e914820bbe491f9. Its linked identity check finds1 ledger data object and exactly1 exported host getter for each ledger/token/group namespace (`unit-storage-linked-identity.json`); declared changed inputs match after build. Empty-model correlation9-POST/unknown-lineage, startup and actual authenticated manager checks pass (`unit-storage-{correlation,startup,manager}.log`),0 inference/installed actions. Source-input9 and metadata3 checks pass; fresh sequential patch application passes.

Storage/TLS identity is now directly exercised, but successful model loads, complete SDK/current-server/slot/backend composition and all-client/terminal/admission acceptance remain open. No model policy or public engine ABI changes.38/55 whole tasks complete; T018/T021/T022 stay unchecked.

## Current server and SDK composition

The optional [SDK bridge layer](../../platform/studio/native/mlx-serve-26.11.2-sdk-ownership.patch), SHAa3d76597ef26c7dc93ce9461509af203084082f75912d810b7de47a716f976e6, applies after the8 preceding layers. It composes the genuine current SDK hooks with the existing native owner callback implementation, adapted only to shared pointer accessors. `-Dfios-source-sdk=true` is accepted only for a `-fios-source-fixture` version; default false retains the ordinary build. Immutable compiled hooks enroll before main; native ledger/context initialization precedes engine startup. A fixed noninitializing SDK negative getter can retain uncertainty; it cannot grant admission. The partial tracker still has `primary_guard=false`. No engine algorithms, provider or public ABI are added.

A separate genuine vendor SDK build uses exactc69303b and mlx-c56b2d39 with its original gather patch, the reviewed7-path ownership patch, SDK27.2/Metal32023.922 and original `build-mlx.sh` with2 jobs. CPU/Metal/safetensors/GGUF are on and JIT off. This differs from the earlier GGUF-off component, whose reviewc158b76f is not reused as full-server provenance. Actual SDK build247.808s; `libmlx.dylib` SHA f4cc0d15b71de481c621c50008d7f0a1c05d47e8a6a6daab9dd32ec23a42a417. Inputs, all4 artifact hashes and recipe hash are retained in `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/vendor-sdk-{inputs,receipt}.json`; build log retained alongside them. No model download or inference.

Both actual full native builds pass30/30: enabled404.799s, binary SHA68926a9806f501d0cd76381658fb69ebb9a3ef25ba10fe7651d2b20f0fcff365; default disabled366.584s, SHAceb663c33cedfddacc3c7d7e53458cf3f977a1c7d3ae9a208d7e92926da43a0a. Changed declared inputs match the enabled build receipt. The enabled binary and private libraries are preserved under `sdk-enabled-runtime/`; default output remains in `source/zig-out/`. Both builds and exact vendor inputs are private development artifacts, not package enrollment or installed approval.

Both candidates pass empty-model correlation9-POST/unknown-lineage, startup metadata/duplicate/refusal/reacquisition, and actual current Swift-manager authenticated control checks. Enabled receipts: `/private/tmp/f9-cur-ingress-{m37ggw6k,nox46fs8,t50uo4t1}/receipt.json`. Default receipts: `/private/tmp/f9-cur-ingress-{htx7b_zi,q5nj967d,2lglek71}/receipt.json`. Aggregate `{correlation,startup,manager}.log` and `default-*` logs are retained in the private parent. Both managers report native admission unsupported and ingress admissions open; coverage remains unknown.0 inference, installed changes or privileged actions.

Source-input/current-metadata checks pass13/13. Working-tree app regression passes116 Node/106 installed Python tests (`application-tests.log`), including preserved unrelated frontend/spec003 edits; this is not exact clean-commit coverage. Existing isolated SDK CPU/Metal/queue receipts remain component evidence, not proof that an HTTP model request traverses every actual engine/slot/backend. Slot and worker-origin integration, all modalities, destructive transitions, native terminality and all-client admission remain unfinished.38/55 whole tasks complete; T002/T018–T022 remain unchecked.

## Current request-slot custody and actor-origin component

The [slot-custody layer](../../platform/studio/native/mlx-serve-26.11.2-slot-custody.patch), SHA0efa8cfd351a7abf24b12e083fbfc4ffad4534eb77d72adc65546fd42701b4b3, applies after the9 current host/load/SDK layers. It captures original attribution before Slot.init allocations and adds an independent model reference before queue publication. Actual Slot.deinit restores those original origins during cleanup, releases local metadata only conditionally and retains the whole slot/model custody when independent native uncertainty is known. It does not claim asynchronous backend terminality or implement a model engine.

The executable [fixture](../../platform/studio/native/current_slot_custody_test.zig.fixture) uses the actual current Scheduler.submit/complete and Slot.init/deinit with one registered metadata stub and zero layers/weights/inference; no inference thread or MLX arrays are created by that scenario. Baseline167.683s fails `FIO_CURRENT_SLOT_LOST_REQUEST_CUSTODY`, expected1 found0 after connection release. Corrected169.296s passes the targeted scenario and enclosing27/27 steps,61/61 tests. Earlier fixture setup used the old scheduler member syntax and failed compilation; `slot-fixture-setup*` is retained separately and is not a behavioral red. Actual red/green inputs and logs are retained under `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/slot-{baseline,current}*`. Full SDK-enabled executable build passes30/30 in365.072s, binary SHAec05ebc852e6c273af5e9d3db72920d04ae099489eb3b16a5ad9f5c264487e88; declared changed inputs match afterward (`slot-build-receipt.json`). Empty-model correlation9-POST/unknown-lineage, startup metadata/duplicate/refusal/reacquisition and actual authenticated manager checks pass (`slot-{correlation,startup,manager}.log`, receipts `/private/tmp/f9-cur-ingress-{f_xj9cw0,81n51u1z,eo8zdmyh}/receipt.json`). Native admission remains unsupported/ingress open; these do not enter positive model execution.

A separate [actor-origin helper](../../platform/studio/native/current_slot_origins.zig) computes a bounded immutable union of every slot's original tokens, deduplicates repeated participants and clones before entering worker TLS. Missing tracking remains unavailable diagnostics; a partly attributed batch cannot drop a participant. The component uses actual current native tracker/SDK/queue sources plus byte-exact upstream Shared, and slot-shaped metadata rather than the complete scheduler. Two original request correlations remain through an actual native thread, overwritten sender metadata, worker exit, genuine SDK parent callback and destructor-enqueued callback; unrelated previous TLS is restored. Debug/ReleaseSafe pass with network denied and2 actual CPU callbacks per mode (`/private/tmp/fios-009-sdk-host-owners-JTQtMa/receipt.json`, parent `slot-origins-component.log`). Initial aggregate-only positive control is separately retained under `slot-origins-initial.log`; the final case checks both exact lineage root sequences.

This component intentionally uses the separate GGUF-off SDK reviewc158b76f, not the full-server vendor SDK receipt. The driver now accepts `--current-sdk --slot-origins --native-source ABS_CURRENT_NATIVE_SOURCE` only for healthy CPU composition; no error/abandonment/Metal combination is permitted. Actual native declared inputs and original source helper hashes are recorded/rechecked; no accessor substitutes or mock SDK are used. Existing ordinary current SDK driver regression also passes both modes (`/private/tmp/fios-009-sdk-host-owners-tsyC7X/receipt.json`). Only healthy ran; generic historical PASS text is not independent-negative scenario evidence.

```sh
# Same reviewed current SDK/source/Zig/developer arguments as the other components:
# add --current-sdk --slot-origins --native-source ABS_CURRENT_NATIVE_SOURCE
```

Worker call-site integration remains pending; this helper component is not current server prefill/decode/media/backend/all-client acceptance. Source/metadata checks pass14/14. Working-tree app regression passes117 Node/106 installed Python (`slot-application-tests.log`), including preserved unrelated frontend/spec003 edits, not a clean-commit receipt. No model inference, installed action, admission grant, merge or deployment.38/55 whole tasks complete; T002/T018–T022 remain open.

## Current worker call-site attribution

The [actor-origin layer](../../platform/studio/native/mlx-serve-26.11.2-actor-origins.patch), SHA52fc551660855032153d06d2465c2d94ff369f8da4e2fb2014f2f4f13c60a163, applies after the10 earlier layers. Its helper is byte-identical to the SDK-tested current slot-origin component. Existing prefill admission, batched decode, finishing, speculative-yield cleanup and cleanup-queue execution now enter stable worker-local scopes and restore previous attribution. No numerical engine code, model selection policy or native authority is added. Lost attribution preserves original custody/uncertainty rather than asserting native completion.

The actual [finish-callback fixture](../../platform/studio/native/current_actor_origins_test.zig.fixture) calls existing Scheduler.submit/complete, finishSlot and its ABI sink with a zero-layer registered metadata stub. The submitting thread clears its TLS before the finish; the real callback must observe the original root. Baseline171.267s fails `FIO_CURRENT_FINISH_LOST_ORIGINS`; corrected169.925s passes27/27 enclosing steps,61/61 tests. Initial call-site compilation needed explicitly typed single-slot slices rather than inferred tuples; that failed build is separately retained in `actor-current-compile-attempt*`, not counted as the behavioral red. Logs/declared inputs are in `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/actor-{baseline,current}*`.

Full SDK-enabled build passes30/30 in191.740s; binary SHA a4e65bf4384b43c7c549a0d54885ce03ac8be55b3294461a1256ca9f749f6d5d and declared changed inputs match after build (`actor-build-receipt.json`). Empty-model correlation9-POST/unknown-lineage, startup metadata/duplicate/refusal/reacquisition and actual authenticated manager regressions pass (`actor-{correlation,startup,manager}.log`; receipts `/private/tmp/f9-cur-ingress-{vghnbfw_,tbnviq35,42n4xkdz}/receipt.json`). Native admission remains unsupported, ingress open, coverage unknown.0 model inference/installed changes.

Source/current-metadata checks pass15/15 and fresh sequential patch application checks pass. Working-tree application regression passes118 Node/106 installed Python (`actor-application-tests.log`), including preserved unrelated frontend/spec003 edits; not exact clean-commit coverage. Positive prefill/decode model execution, media/vision/embedding/other backend custody, complete registry/destructive transitions and all-client/native terminal/admission acceptance remain unproven.38/55 whole tasks complete; T002/T018–T022 remain open. No merge or deployment.

## Current media, vision and embedding queue custody

The [media-origin layer](../../platform/studio/native/mlx-serve-26.11.2-media-origins.patch), SHAdd48a9f46bf70c971ad940c1e3ac84b3de4f213d879c557ce3713ad095b3ed45, applies after the11 preceding layers. Existing generation/vision/embedding senders retain their original group before queue publication, keep it across the uncancelable wait and restore the request's previous metadata pointer on return. Workers clone before effects, retain stable local storage past acknowledgement and restore prior TLS. The pointer-view [queued adapter](../../platform/studio/native/current_queued_origins.zig) reuses the tested bounded union without copying256 complete token arrays onto the stack. A refused generation handoff wakes only its original senders with an error; acknowledgement remains distinct from native completion.

The actual [two-sender fixture](../../platform/studio/native/current_media_origins_test.zig.fixture) calls current runGeneration/runGenRequests with2 native sender threads, a registered metadata stub and a metadata-only merged callback. It releases both original references after publication, then requires the callback to see both exact live roots. Baseline169.233s fails `FIO_CURRENT_MEDIA_LOST_ORIGINS`; corrected169.541s passes27/27 enclosing steps,61/61 tests. No model, rendering, vision or embedding forward pass occurs. The genuine empty-cache cleanup is process-local. Logs/input receipts remain under `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/media-{baseline,current}*`.

The separate actual current-native/SDK queued pointer-view component passes Debug/ReleaseSafe, both exact correlated roots surviving overwritten sender metadata, actor exit, genuine SDK parent and destructor-spawned CPU callbacks (`/private/tmp/fios-009-sdk-host-owners-NFzMRp/receipt.json`, `queued-batch-component.log`). This uses the earlier GGUF-off SDK reviewc158b76f, not full-server vendor provenance. Only healthy runs, with network denied and0 models. The explicit `--current-sdk --queued-batch --native-source ABS_CURRENT_NATIVE_SOURCE` driver mode rejects other scenario families. An initial CLI variable-order setup error is retained in `queued-batch-cli-setup.log`, not a behavioral red. Existing slot-origin driver regression also passes both modes (`/private/tmp/fios-009-sdk-host-owners-CkYJez/receipt.json`).

Full SDK-enabled native build passes30/30 in184.863s; binary SHAc2dc4ae1b9313573a0018767f7a0041a7a2f85010e506e8a842c6b2615501ed7, declared changed inputs match afterward (`media-build-receipt.json`). Empty-model correlation9-POST/unknown-lineage, startup and actual authenticated manager regressions pass (`media-{correlation,startup,manager}.log`, receipts `/private/tmp/f9-cur-ingress-{8imxtzhk,ui6yje3w,apm9xrsx}/receipt.json`). Coverage remains unknown, native admission unsupported and ingress open;0 inference/installed actions.

Source/current-metadata checks16/16, sequential patch application and working-tree119 Node/106 installed Python pass (`media-application-tests.log`). Application evidence includes preserved unrelated frontend/spec003 edits, not clean-commit coverage. Positive media/vision/embedding model execution, own-thread/native backend context lifetime, registry/destructive transitions, all-client non-preemption and native terminal/admission acceptance remain open.38/55 whole tasks complete; no merge/deployment.

## Current own-thread request-book custody

The [book-custody layer](../../platform/studio/native/mlx-serve-26.11.2-book-custody.patch), SHA2fb23faca83dfa8223af393fdd5dc4041db8ba46578ae8556829ad58d9f02bcb, applies after the12 preceding layers. It changes only the existing shared request book used by DS4/llama.cpp/ANE: original attribution is retained before request-copy allocations and queue publication, and released conditionally after local descriptor destruction. Release remains callback-free while the book mutex is held. Known uncertainty quarantines original references; descriptor destruction is not native terminality. No numerical engine implementation or public ABI changes.

The actual [book fixture](../../platform/studio/native/current_book_custody_test.zig.fixture) copies/queues/takes/completes an ABI request through the real Book with a normal event sink, using no model or backend. It releases the connection reference before taking the request, requires its exact original lineage to remain found, then checks normal local metadata retirement after the callback. The source initializes with testing.io while Book uses its actual global native Io, exercising those shared-mutex operations without claiming contended/native-device acceptance. Baseline166.055s fails `FIO_CURRENT_BOOK_LOST_REQUEST_CUSTODY`; corrected166.029s passes27/27 steps,61/61 tests (`book-{baseline,current}*` in `/private/tmp/fios-009-current-sdk-server-h_mvvlhq`). Initial fixture ordering attached correlation after binding; that failed `InvalidCorrelationState` before the intended assertion. Its `book-fixture-setup*` and `book-baseline-terminal.log` diagnostics are retained separately and not counted as the behavioral red.

Full enabled native build passes30/30 in187.934s; binary SHAf2f1fdca3b5bac9622abbd1293e70a61197a8477ef0dbff9f0f8852f8a15ee82 and declared inputs match after build (`book-build-receipt.json`). Empty-model correlation9-POST/unknown-lineage, startup and actual authenticated manager regressions pass (`book-{correlation,startup,manager}.log`; receipts `/private/tmp/f9-cur-ingress-{rbhcy4eb,5irco1ld,beptji9u}/receipt.json`). Coverage unknown/native admission unsupported/ingress open;0 inference or installed changes.

Source/current-metadata checks17/17, sequential patch application and working-tree120 Node/106 installed Python tests pass (`book-application-tests.log`), with preserved unrelated frontend/spec003 edits included only in working-tree application evidence. Engine worker TLS/compute/native backend retirement and all-client acceptance remain unfinished; ABI finished events and void close are not terminal proof.38/55 whole tasks complete. Exact03dced8 CI43368077903 now passes all6 prerequisites plus aggregate; pusheddaebe2a CI43371408534 is running, not green evidence. No merge/deployment.

## Current DS4 adapter worker attribution

The [DS4 actor layer](../../platform/studio/native/mlx-serve-26.11.2-ds4-actor.patch), SHA78ff265a8769611f5b7efa34532444fd98a5cdf0a91a24763651f624fcb03262, applies after the13 preceding layers. The existing adapter worker clones the request book's original group before its existing serve call, retains stable scope storage across Book.done/free and local cleanup, and restores the previous thread context. It adds no model engine or numerical algorithm. Unknown attribution fails the original request and preserves independent uncertainty; an ABI finished event remains distinct from native terminality.

The actual [adapter fixture](../../platform/studio/native/current_ds4_actor_test.zig.fixture) uses the existing model-free FakeBridge with the real adapter, request book and native worker thread. A real prefilled callback must observe the exact original root after the submitting thread releases its reference; normal model-free completion/join restores TLS and retires local metadata. Baseline162.852s fails `FIO_CURRENT_DS4_WORKER_LOST_ORIGINS`; corrected165.820s passes27/27 enclosing steps,61/61 tests. The earlier local name shadowed the existing probe function; its compile-only `ds4-actor-fixture-setup*` receipt is retained separately, not a behavioral red. No DS4 weights, GPU/native backend inference or model competence is exercised. Logs and inputs remain under `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/ds4-actor-*`.

Full enabled native build passes30/30 in189.835s; binary SHAa6fd7d23e30f97ea72fcaf178a60151e76d48520fe39abfbf9a4e973e112dd9e and declared inputs match afterward. Empty-model correlation9-POST/unknown-lineage, startup and actual authenticated manager checks pass (`ds4-actor-{correlation,startup,manager}.log`, receipts `/private/tmp/f9-cur-ingress-{yxzmrewy,lorjx3y8,syrv5jl3}/receipt.json`). Native admission unsupported/ingress open/coverage unknown;0 inference or installed actions. Source/metadata18/18, sequential patch application and working-tree121 Node/106 installed Python pass (`ds4-actor-application-tests.log`), with unrelated frontend/spec003 work included only in working-tree app evidence.

Real DS4 C/Metal/peer/RDMA/terminal lifetime, other adapter worker scopes, complete registry/destructive/all-client integration and Studio acceptance remain open.38/55 whole tasks complete; no merge/deployment.
