# Native activity integration: concrete implementation seam

**Current scope (2026-10-31):** Native hardening and security-adjacent investigation are stopped at the operator’s request. The source matrices and receipts below are historical evidence, not instructions to resume that work. Ordinary functional implementation, native integration and correctness checks continue; installed activation and disruptive acceptance remain separately gated.

Status: source-only integration/testing authorized by the user's explicit reaffirmation on2026-10-27; implementation/source audit in progress, not a deployed native modification. Do not ask again for this scope. Installed binaries/configuration, service restarts, network/RDMA changes and deployment remain separately gated. The user granted standing real-inference approval on2026-10-30; bounded private source-model experiments may run without another inference permission/model-ID request. This does not approve installed lifecycle or disruptive/native acceptance. No resident-only API is required. Ordinary on-demand replacement of an idle model is allowed.

Current backend-specific findings and unproven terminality requirements: [native-backend-terminality.md](native-backend-terminality.md).

## Ordinary image-bearing source check —2026-10-31

The finite model runner accepts `--scenario single-image` on plan/check/run, with one fixed64×64 PNG and the same small exact Gemma model/resource limits. Current genuine source integration returns400 because this model variant’s vision tower is explicitly not wired (`model.zig` sets `has_vision=false`). The presence of vision weights/config is insufficient to claim serving support. Retain this unsupported result; it is not model competence or complete modality coverage. No larger-model substitution, retry or native installation follows. See the validation record for the actual one-use plan and result.

## Source capture metadata integration —2026-10-31

The ordinary private control protocol now optionally returns version3 frames with the original native capture sequence and source UTC milliseconds. Version2 remains the default compatible32/64-byte exchange; version3 uses32/80 bytes. The manager keeps transport receipt age distinct from source age and carries current native metadata into activity export with coverage still unknown. See [native control](contracts/native-private-control.md).

A private native executable can be compiled/staged without running the earlier test/probe/HTTP matrices by appending `--functional-build-only` to the existing `check-platform-native-fixture.mjs` command, with `--review-output` and the normal exact source/dependency inputs. This mode checks the declared source patch, copies the actual source companions and builds against genuine dependencies; receipts explicitly set `root_tests_rerun:false` and `http_checks_rerun:false`. It does not claim upstream staging/release attestation or all-client/backend coverage. Run `check-platform-native-status.mjs --isolated --capsule ABS --sha256 RECEIPT --protocol-version 3` separately for the normal empty-model source-server/manager flow; the same capsule supports the unchanged version2 check.

## Source-fixture startup ownership prerequisite

The current reviewed patch adds `src/main.zig` as its tenth fixed path and calls the separate `startup_guard.zig` before native initialization. It is enabled only by the exact `FIOS_NATIVE_STARTUP=isolated-source-fixture` marker plus fixture version suffix, nonroot equal real/effective UID and a preexisting private0700 HOME. The0700 subdirectory and0600 regular single-link/no-ACL lock are opened by descriptor without following their final symlinks; an exclusive nonblocking close-on-exec `flock` is retained for the process lifetime. Release closes the descriptor without unlinking the pathname. The startup refusal carries `StartupGuardUnavailable`, independent of later HTTP-port or control-socket conflicts.

This is deliberately per-fixture-HOME source engineering. A caller can omit the marker or choose another HOME, so it does not establish production global singleton authority, all-client absence or backend terminality. It cannot authorize app launch, stop, uncertainty release or native acceptance. A production enrollment/namespace policy and duplicate/unmanaged-process coverage are still required for T002/T027. Ordinary unconfigured native startup creates no guard state.

## Existing safety mechanism located in version-aligned source

In `server.zig::handleConnection`, after local/peer resolution and non-loading metadata routes, `scheduler.ensureLoaded(requested_model_id)` returns a referenced model. A `defer` releases that model only after the selected handler returns (status reads use releaseStatus). Text chat, completions, messages, responses/WebSocket and other local handlers dispatch under this outer ownership. `model_registry.zig::pickLruEvictable` skips nonzero refcounts; scheduler load planning refuses admission if no safe victim exists and drains selected victim readers before unloading.

This is stronger evidence than sampled scheduler running/waiting gauges: the reference spans the handler's response work. It is still necessary to audit detached workers, early response/error paths and auxiliary-model handlers before asserting every enabled modality is covered.

## Why metrics alone miss a phase

There is a window before `ensureLoaded` acquires the final model reference, including cold CPU preloading. Existing scheduler counters do not prove absence of a request there. A model can also retain response ownership after the GPU scheduler stops counting it. Combining sampled catalog/metrics does not reconstruct a coherent lifecycle.

## Minimal native-local observation change if existing interfaces are insufficient

Implement a bounded request-ownership tracker **inside the existing server**, not a proxy or OS packet sniffer:

1. After authentication/LAN policy and identifying a local inference route, before any loading/preparation, acquire a bounded tracker token. Capture only exact resolved model identity, request phase and process epoch/sequence; never prompt/body/header/client secrets. Track unparsed inference ingress conservatively as unknown so it cannot create a false-idle window. Exclude health/metrics/status routes.
2. Keep the token through local model acquisition and response handling; release in an outer defer only once the handler and any detached native computation are proven terminal. If a handler hands work to another owner, transfer/refcount the tracker token rather than releasing at socket close.
3. Expose one coherent bounded local-only snapshot containing process identity/epoch/sequence, preparing/active owners grouped by exact model, registry transition/resident state and an explicit overflow/unknown flag. Snapshot serialization takes compatible bounded locks; never hold locks while writing to a slow socket. Source overflow must not truncate into idle.
4. Keep LAN admin denial unchanged. Initial integration can use a fixed loopback-only endpoint or private Unix channel; no new public/LAN listener or auth bypass. The manager exports only the safe normalized contract through its own role-separated observation boundary.
5. Retain native model reference protection for dispatch races. Admission tests must prove different-model requests do not evict an in-use model and same-model requests may coexist. No special reject-if-not-resident option, load/unload admin call or synthetic warmup is needed.

## Development versus deployment

A source patch and isolated unit tests can be developed without replacing the installed server. Building/packaging must follow upstream toolchain/dependency/license requirements. Installing it into the signed native application, changing launch configuration or restarting serving processes requires the explicit native rollout procedure; never patch the live binary or inject instrumentation. If upstream already exposes an equivalent supported lifecycle view, prefer that and avoid a fork.

## Required audit/test matrix

Exact local and tunneled IDs; unknown/default-alias rejection by009's own exact mapping; pre-body/partial-body ingress; cold preloading; resident same-model overlap; queued/prefill/decode; slow reader; disconnect with compute continuing; handler errors; auxiliary alignment/diarization; WebSocket repeated turns; stored/detached responses; native process restart; tracker overflow; snapshot serialization failure; concurrent activity source reads versus native model switch. Each path must be covered or host eligibility stays unsupported. These native tests are distinct from the Swift policy unit tests and should not be reported as passing before they run.

## Source-only implementation checkpoint (2026-10-27)

`platform/studio/native/mlx-serve-26.10.3.patch` applies to pinned source revision `046b647686419df06c6c7132fb1d15d76185c3e5`; the current patch modifies only `src/server.zig` and `src/scheduler.zig`. Copy the accompanying `request_ownership.zig` as `src/fios_request_ownership.zig` when preparing that development checkout. No installed application is patched.

- A bounded256-slot tracker enters before connection-thread spawn and before request/body parsing. Allocation failure closes the accepted socket without dispatch. Spawn failure releases its token. The thread's outer defer releases ownership after socket close; token/IO values are copied before the thread arguments are destroyed. Early returns, auth denials and write/read errors retain ingress ownership until this defer.
- The main local resolution path and explicit load-model handler bind a copied, UTF-8-validated exact registry ID before `ensureLoaded`, including its CPU preparation window. Loading uses that same canonical ID so a concurrent default-model change cannot silently change the tracked target. Preparation/handler/response-tail phases are conservative ownership labels, **not GPU execution phases**. Metadata and proxy connections remain conservatively counted as ingress in this first checkpoint rather than being falsely subtracted.
- Overflow, invalid/stale tokens, invalid model identities, phase rewinds and allocation-sequence exhaustion permanently fence tracker certainty. Model storage is bounded1024 bytes and cleared on release. Snapshot counters are copied under a mutex; serialization and socket writes happen after unlock, using a fixed1024-byte response buffer.
- Development `GET /v1/fios/activity` is loopback-only and refuses tunnel-marked requests in addition to existing auth/LAN gates. It returns `coverage:"unknown"`, `reason:"native_ownership_audit_incomplete"` and explicitly includes the observer connection. Its sequence is the token-allocation sequence, **not an authoritative observation epoch/sequence**. This diagnostic is deliberately **not** the009 normalized activity contract and cannot enroll a host or clear inference uncertainty. It contains no model list, prompts, headers or credentials.
- Further source audit confirms `gen_sse.offload` joins its CPU worker and optional keepalive worker before returning. `Scheduler.complete` waits for `slot.in_pass` but subsequently enqueues native cleanup; that cleanup and asynchronous device completion still require audit. `unloadModelIfIdle(..., null)` marks evicting and drains references rather than establishing an idle precondition. At this initial checkpoint transcription's lazy aligner/diarizer loads bypassed exact auxiliary binding. The later bounded multi-model checkpoint below adds source hooks; actual auxiliary GPU/modality acceptance remains unproven. Destructive admin operations remain conservatively ingress-owned without a native quiescence claim. No non-preemptive admission change has yet been enabled.

Reproduce without mutating the supplied source checkout or launching a server:

```sh
node scripts/check-platform-native.mjs --source ABS_PINNED_CHECKOUT --zig ABS_ZIG_0_17_0
```

The checker reconstructs only the pinned original server in a private disposable directory, verifies/applies the fixed patch there, syntax-checks it and runs the tracker tests in Debug and ReleaseSafe. It does not install dependencies, invoke inference, run Homebrew or alter native configuration. Characterization assertions are supplemental source checks, not HTTP acceptance.

Initial checkpoint evidence:6 tracker tests passed in both modes, including8 concurrent threads/512 ownership cycles, bounded JSON/serialization failure, overflow, token replay, invalid phases and sequence exhaustion. Failing-first logs: `/tmp/fios-009-native-ownership-red.log`, `/tmp/fios-009-native-render-red.log`; reproducible green: `/tmp/fios-009-native-source-hermetic.log`. Full upstream `zig build check` was attempted and stopped at configure time because Homebrew `webp >=1.6.0` is missing (`/tmp/fios-009-native-source-check.log`); it did **not** establish full semantic compilation. No host dependencies were installed. Native HTTP/modalities/non-preemption acceptance and G2 remain incomplete.

## Deferred native cleanup and reproducible semantic subset

The current source module shares one bounded tracker between connection and inference threads. A native-created thread-local token propagates into scheduler submission; queued slots retain it and clone the caller's existing model reference with a nonzero/overflow-checked atomic increment. The clone never waits on an evictor that may already be waiting on that caller. Slot destruction releases the model reference and then the retained request token **after** native slot cleanup, using copies that survive slot destruction. Socket close cannot erase this retained owner. Non-request scheduler callers keep their existing behavior; they are not silently promoted to all-client coverage. Diagnostic `owned_requests` counts retained requests, not only open sockets. The later checkpoint below adds bounded exact auxiliary identity ownership. GPU completion, all-enabled-path coverage and native quiescence remain unproven.

Eight Debug/ReleaseSafe tracker tests now pass, including retained ownership after socket-owner release and non-resurrecting/overflow-safe model-reference cloning. Red `/tmp/fios-009-native-retain-red.log`; green `/tmp/fios-009-native-retain-green.log`. These eight pure tests are not a real inference/slot-destruction acceptance test; a subsequent actual CPU-only scheduler cleanup test is recorded below.

Pinned native source submodules and genuine libwebp1.6.0 headers were fetched only into disposable development checkouts. The host also lacks CMake and a usable Metal compiler; no toolchain/host dependency installation was performed. A distinct, reproducible **Zig semantic-only subset** now checks both actual native executable/test roots with the patch:

```sh
node scripts/check-platform-native-sema.mjs --source ABS_PINNED_CHECKOUT --zig ABS_ZIG_0_17_0 --webp-source ABS_WEBP_1_6_0_CHECKOUT
```

The checker verifies native/submodule/header commit pins, exact reviewed source patch/module bytes and the unchanged upstream build graph. It generates/removes a private temporary graph that explicitly excludes runtime staging verification and C/object/library link inputs **only for the fixed `check` target**. All real Zig roots/imports remain; no model/backend stubs, forged `.version` stamps or runtime substitutes are used. The original upstream build/release gates are unchanged. Passing this subset establishes actual Zig semantic compilation of the integration, **not** C compilation/linking, dependency staging, ABI compatibility, an upstream full build or native acceptance. `/tmp/fios-009-native-sema-repro.log` passes. The initial attempt without removing link inputs correctly failed on unstaged libraries (`/tmp/fios-009-native-sema.log`). Production eligibility stays closed.


## Linked source fixture, actual cleanup and bounded auxiliary identities

`check-platform-native-fixture.mjs` now provides a separate reproducible **linked development fixture**, not an upstream staged/release build. It verifies the exact source/submodule/header/helper/patch pins through the semantic checker first, plus exact Zig executable, Apple Metal-cpp26 archive, staged upstream llama b11429 library/header and six installed framework input hashes. It copies the installed frameworks read-only into private development state; it never executes or changes the installed server. It uses actual native executable/test roots and **retains all real C/object/library link inputs**. No model/backend implementation stubs, fake dependency stamps, Homebrew/CMake/Metal-compiler installation or upstream release-gate modification is involved. Only the copied private WebP library's load ID/signature is adjusted for its unavailable Homebrew path; the installed original is verified unchanged afterward.

```sh
node scripts/check-platform-native-fixture.mjs \
  --source ABS_PRIVATE_TMP_PINNED_CHECKOUT --zig ABS_ZIG_0_17_0 \
  --webp-source ABS_WEBP_1_6_0_CHECKOUT --metal-cpp-zip ABS_APPLE_METAL_CPP_26_ZIP
```

Prerequisites are the genuine pinned submodules, upstream `scripts/fetch-llama.sh` output and Apple's `https://developer.apple.com/metal/cpp/files/metal-cpp_26.zip` (the script verifies its exact hash). The generated build graph, output, private WebP input and empty-home/model HTTP state are removed. Unstamped verified header/library copies may remain in the disposable source checkout for development, not release attestation. The source fixture uses version `26.10.3-fios-source-fixture`, MAS provider-disable mode, a fresh HOME/empty model directory and an ephemeral loopback-only listener; no LAN/distributed flags or model POST completion. No installed/native service restart or actual Studio enrollment is implied.

- ReleaseFast real executable code generation/linking passes. ReleaseSafe filtered actual test root passes **5/5**, including one named Fios scheduler cleanup test, two upstream route/thread characterization cases and unnamed import/discovery tests. The Fios test invokes real `Scheduler.submit`, `complete`, `Slot.deinit` and registry LRU selection using a **zero-layer CPU-only metadata fixture**, no weights, MLX arrays or inference thread. Model reference and primary/auxiliary request identities survive simulated connection release and deferred cleanup; the model is not an LRU victim until slot destruction, and is eligible for ordinary idle replacement afterward. This is not GPU completion or real-model busy-conflict acceptance.
- Disabling actual slot retention reproduced a runtime assertion failure (`/tmp/fios-009-native-slot-retain-red.log`); restoration passes. The existing upstream embedded-source route-gate assertion initially failed because canonical-ID loading changed its searched expression (`/tmp/fios-009-native-route-regression-red.log`). Its assertion now checks the actual canonical dispatch expression while preserving the unknown-route-before-loading requirement; the detached-thread assertion also passes.
- `check-platform-native-http.mjs --isolated --binary ABS_FIXTURE --sha256 REVIEWED_FIXTURE_SHA` tests the actual candidate, not an HTTP mock: partial headers and incomplete bodies remain ingress-owned, observer inclusion is explicit, tunnel-marked activity is403, query-shaped management data stays inert and closed ingress ownership releases. Catalog remains empty before/after. **No model POST completes, no model loads and no inference runs.** The diagnostic remains `coverage:unknown`, never normalized/enrollable activity. Failing-first missing fixture `/tmp/fios-009-native-http-red.log`; first real pass `/tmp/fios-009-native-http-green.log`.
- The tracker now has **64 byte-exact global model entries** and256 request masks rather than per-request single-model storage. Primary plus auxiliary identities are copied under one mutex; duplicate auxiliary binding is idempotent, composed/decomposed Unicode IDs remain distinct, shared model owners aggregate coherently, retained slot ownership keeps every bound identity, and final ownership clears model storage. Invalid phase/ID, contradictory owner counts or a65th identity persistently fence certainty rather than truncate. Internal model counters are conservative request phases, **not GPU phases**, and model IDs are not exported by the diagnostic.
- Source hooks bind the ASR aligner before configuration parsing and again idempotently before lazy loading, and the diarizer before loading. Missing native-created TLS ownership refuses auxiliary binding and fences certainty. This closes those source identity gaps without claiming real auxiliary execution/terminal proof. **Eleven** pure Debug/ReleaseSafe tests pass; missing API red `/tmp/fios-009-native-auxiliary-red.log`, green `/tmp/fios-009-native-auxiliary-green.log`.
- Latest complete reproducible linked fixture: `/tmp/fios-009-linked-native-auxiliary-repro.log`, development-only artifact SHA `23c90f9f78cb3ea5cf498406d9450522db10502b2922311b6b3c175a0b312666` (deleted with fixture output). Observed compile peak7GiB is **build cost**, not controller/native runtime footprint evidence; filtered CPU-only test root peak12MiB is not full-agent acceptance. Earlier `/tmp/fios-009-linked-native-repro.log` predates auxiliary changes.

**Still open:** full upstream staging/release attestation and broad ABI/runtime compatibility; all enabled modality/WebSocket/error/background/device-terminal coverage; coherent process/registry epochs and trusted manager observation/control wiring; atomic maintenance/admission/quiescence and actual protected lifecycle/native non-preemption acceptance. Neither linked empty-model HTTP nor fake CPU registry state resolves G2 or T051. At that checkpoint whole-task count was13/55; T005 subsequently made that count14/55; the current count is17/55 after T035/T037/T038. No installed native application/configuration, production SQLite, real inference, public/LAN listener or RDMA/network setting was changed.


## Native source instance and competing preload protection

Native startup initializes a random128-bit source instance before the startup responder/listener/scheduler path. Entropy collection is outside tracker locks; tokens and coherent snapshots bind the instance. Duplicate/zero/late initialization and cross-instance token replay irreversibly fence certainty. The unknown-only diagnostic's new `source_instance` is a non-secret32-hex identifier, **not a management capability, enrolled process proof or observation sequence**. Twelve Debug/ReleaseSafe tracker tests pass. The actual HTTP fixture checks stable nonzero identity and rejects an older artifact lacking it; `/tmp/fios-009-native-instance-http-red.log`.

The pinned loader's CPU-preload failure path previously unconditionally called `markErrorLocked` after CPU preparation outside the mutex. That helper also releases the model's reservation, so a competing loader becoming loading/ready/evicting could have its state and bill overwritten. `recordPreloadFailure` now re-checks `.unloaded` while holding the registry mutex before recording failure. The actual CPU-only native test preserves each competing state's128-byte fixture reservation, verifies genuine unloaded failure behavior and exercises the actual same-model ready fast path with coexisting references. This is metadata-only native code, not model inference or a full cold/busy switch scenario. Failing old behavior `/tmp/fios-009-native-preload-race-red.log`; fixed `/tmp/fios-009-native-preload-race-green.log`. Latest full linked fixture `/tmp/fios-009-linked-native-preload-repro.log` passes5/5 filtered actual-root tests and empty-model HTTP.

Further source audit: WebSocket Responses stays on the originally borrowed model for the entire connection and calls its handler with that same pointer on every turn; response-local cleanup is synchronous but this conservatively pins ownership even between turns. Media `runGeneration` waits uncancelably for `GenRequest.done`; CPU-only `gen_sse.offload` joins worker/keepalive threads. These facts do not prove asynchronous device completion. In particular, MLX's global `get_streams()` is **not** an arbitrary-control-thread fence: Metal command encoders are thread-local (except explicitly global streams), and `get_command_encoder` throws for another thread's ordinary stream. A future terminal barrier must run on each actual device-owner thread, cover non-default/embedded/ANE backends and prevent new admission/registry transitions atomically; merely synchronizing the observer's default stream cannot establish quiescence. No partial/default-stream-only fence or sampled-idle authority was added. Trusted manager wiring, native maintenance/admission and actual G2/T051 acceptance remain open.

### Native ingress reservation fence (not quiescence)

The tracker now supports native-internal `pauseAdmissions`/`resumeAdmissions` with source-instance-bound monotonic one-use pause state. Pause and `enter` use the same mutex: no new connection reservation can cross a completed fence; already-reserved ingress and its auxiliary work may drain normally. Pause persists after all owners finish and never automatically reopens on time/manager death. Bad/foreign/old/replayed resume state does not reopen the gate; resume never clears uncertainty. The private pause sequence is not exposed through the HTTP diagnostic. AdmissionPause is **not authentication**: no model HTTP opcode, production issuer or trusted operator transport was added. A future enrolled bridge must authenticate before invoking these methods, persist desired maintenance before pausing, inspect registry/internal work, obtain all device-owner terminal barriers and bind any lifecycle operation to the exact current process/scope. Zero tracker owners is still not quiescence.

Fourteen Debug/ReleaseSafe tracker tests pass, including eight concurrent reservers, existing-request continuation and ticket replay/foreign-instance refusal. The actual CPU-only native root exercises the same pause/resume primitive. Latest reproducible linked fixture `/tmp/fios-009-linked-native-pause-repro.log` passes5/5 filtered actual-root tests plus empty-model HTTP; default HTTP reports `admissions_closed:false`. This is not installed native lifecycle, full all-client coverage or native inference acceptance. At that checkpoint whole-task count was14/55.

## Private native control and durable manager integration checkpoint

See [native-private-control.md](contracts/native-private-control.md) for exact32/64-byte framing, UID boundary, fixed private socket and limitations. Source companions now retain their reviewed repository basenames (`request_ownership.zig`, `control_protocol.zig`, `control_transport.zig`); server/scheduler import the same ownership module, not duplicate trackers. At that checkpoint hermetic/Sema checks bound all three companions and the exact two-file patch; the owner-thread extension below adds a reviewed build-graph change and companions.

The actual linked candidate enables its private Unix transport only with the explicit isolated-source marker and fixture build suffix. At that checkpoint it supported observe/pause/resume only: no shell, caller-selected PID/path, signal/force/stop, model identifiers or terminal/coverage authority. Native checks kernel peer UID and private0700/0600 permissions. Swift authenticates peer UID/PID/start, byte-exact kernel executable path and no-follow bounded SHA256 before sending actions. Wrong artifact hash cannot pause. Unknown/extra/trailing frames and foreign source instances cannot act; old tickets cannot reopen or clear uncertainty.

`NativeMaintenanceCoordinator` persists explicit operator desired state before emitting native work; absent desired rows do not authorize reopening. `AsyncNativeControl` has one connection/result slot off the heartbeat loop and never retries/falls back. Lost or contradictory outcomes stay unknown; subsequent reconciliation observes truth rather than replaying uncertain actions. Manager startup recovers an existing explicit maintenance row, native pause and source identity; task/observer callers cannot change it. Normal `ManagerRuntime.run` still supplies no native client. Only the isolated fixture currently issues one; production release/profile enrollment is unfinished.

Actual end-to-end `/tmp/fios-009-control-manager-linked.log`: real native executable codegen/link,5/5 filtered native-root tests, empty-model HTTP, real Swift pinned client and separate isolated manager/FIS9 journal all pass. Manager maintenance survives its termination/restart without reopening/replay; explicit resume works; status stays `native_activity:unsupported`, lifecycle `applied:false`, sandbox/model admission disabled. Artifact SHA6774359c657cbd71ac326e7afad05894c77033f1a070fb8f6b6e33e7ac1b9062 was deleted with disposable output. No production SQLite, installed native app/configuration, real model inference or network/RDMA change occurred. This receipt predates the additional contradictory-acknowledgement policy regression, which is separately logged.

All-client device/registry terminal ownership, atomic native quiescence reservation and protected lifecycle execution remain open; this transport/controller cannot manufacture them from zero counters. Fourteen whole tasks were complete at that checkpoint; subsequent T035/T037/T038 completion brings the current count to17/55. Source work is not G2/T051 or installed acceptance.


## Native Zig source-default call-path wrapper red→green checkpoint

Actual native-root `/tmp/fios-009-native-default-path-behavior-red.log`/`.status` exit1,5/6: raw CPU defaults lacked actual creation custody. The earlier `/tmp/fios-009-native-default-path-red.log` was a corrected Zig0.17 allocator API harness error, not behavioral evidence.

The fixed patch now9 paths adds `src/mlx.zig` to the prior eight: CPU/GPU getters use the genuine owned-default bridge only with the existing exact source marker/version suffix and nonroot/effective=real UID gate. Handles/default identity stay unchanged; custody failure uses the original raw getter without a receipt or inference retry. Actual-root test demands cloned-handle identity/creation custody and an absent-marker fresh thread stays raw/unregistered/unknown. `/tmp/fios-009-native-default-path-green.log`/`.status` exit0: actual native-root6/6 including default custody/identity and absent-marker raw/unknown fresh-thread path; genuine library/owner/default/two-owner/HTTP/control/Swift/manager restart pass. Artifact `6f7f721b7b5fc2290dd8f44eba61ecb22eccadcf46583a176ae569bd420ab343` deleted; installed runtime hashes unchanged. This wires native Zig call paths only in source fixtures, not plugin/embedded FFIs or a production profile; all-client coverage/lifecycle remain closed. Upstream staging guards preserved.

## Owned default mlx-c identity bridge ABI checkpoint

`fios_mlx_owned_default_c_stream` returns a genuine cloned mlx-c handle only for this actual thread's recorded default, creating/recording a default only when absent. Existing foreign/global defaults are refused, never adopted. CPU fixture demands two owned handles and public mlx-c default share one stream/index; assigned global default is refused. `/tmp/fios-009-owned-default-c-api-red.log` missing-symbol failure; `/tmp/fios-009-owned-default-c-api-green.log`/`.status` exit0: genuine default/owned/public-handle identity, CPU creation/index/sync/free, global/foreign/invalid refusal, native-root5/5 and prior owner/two-owner/HTTP/control/Swift/manager restart pass. Artifact `6c2705980763aeaa183c18d86f39a88e3866bb4c943a550b87487514cf022a81` deleted; installed runtime hashes unchanged. Native model/default call-site wrappers remain unwired, no inference or aggregate/lifecycle authority.

## Genuine owned mlx-c creation bridge ABI checkpoint

`fios_mlx_create_owned_c_stream` returns a genuine mlx-c handle to an actual newly-created current-owner stream, not an adopted caller index/pointer. Pending creation and owner/epoch bookkeeping bracket the real backend allocation. Genuine pinned `mlx/c/private/stream.h` factory creates the opaque handle; the caller uses normal `mlx_stream_free`. Wrong owner/invalid shape is refused and failure nulls output. CPU fixture uses genuine mlx-c index/synchronize/free, including an actual foreign thread and no inference. Missing implementation reproduced `/tmp/fios-009-owned-c-api-red.log` link failure; `/tmp/fios-009-owned-c-api-green.log`/`.status` exit0: genuine CPU index/synchronize/free and actual foreign-thread/invalid checks, native-root5/5, prior owner/default/two-owner checks and HTTP/control/Swift/manager restart pass. Artifact `893360701bbd74c6313fc3b51c181b9a32778d7968cdc6d256ada217ae26fbd5` deleted; installed runtime hashes unchanged. Both macOS roots include the pinned mlx-c source headers; native model/default-stream call paths remain unwired, all-client coverage unknown. No new wire opcode or normalized lifecycle authority.

## Bounded registry partial-probe epoch red→green checkpoint

Actual native-root regression `/tmp/fios-009-registry-borrow-aba-red.log`/`.status` exit1,4/5 exposed a borrow/release ABA missed by upstream state-only generation. New mutex-held `fios_probe_epoch` covers reviewed canonical/stub/default changes and production borrow/release paths, with irreversible exhaustion refusal. CPU-root tests cover same-state borrows, stub/default changes and repeated overflow fencing. Both pre/post quiet checks now use this bounded epoch; no registry mutex spans device synchronization, no complete coverage or atomic reservation is inferred. `/tmp/fios-009-registry-borrow-aba-green.log`/`.status` exit0: actual native-root5/5 (borrow/state ABA, stub/default and irreversible exhaustion), genuine linked libraries/MLX owner/default/two-owner checks and HTTP/control/Swift/manager restart pass. Artifact `f397571c2e6c53588e63c072c3c3d5062c8286919cc274c782828a77cae774c5` deleted; installed runtime hashes unchanged. Separate source guard log `/tmp/fios-009-registry-epoch-source-guards.log` exit0 binds the exact four reviewed production atomic refcount mutations and adjacent epoch advancement; this characterization does not replace coverage acceptance.

The reviewed fixed patch set is now8 paths: prior seven below plus `src/model_registry.zig`. Both source checkers require the exact set/content and preserve upstream staging guards. See backend matrix for additional non-MLX queues and errors that these registry checks do not cover.

## Source-only llama target/MTP bridge linkage checkpoint

At that checkpoint the reviewed patch fixed7 paths: `build.zig`, `lib/llama_shim/llama_shim.cpp`, `lib/llama_shim/llama_shim.h`, `src/arch/llama.zig`, `src/llama_ffi.zig`, `src/scheduler.zig`, `src/server.zig`. Both checkers enforce the exact set/content; upstream staging/release guards remain. Earlier three-file receipts below are historical.

`mlx_llama_ctx_terminal`/`LlamaContext.terminal` is a native-internal partial primitive, not private opcode3 or a complete-coverage source. It requires an exact retained context on a non-reusable creator-thread token and synchronizes target **and optional MTP draft**. Missing/wrong-owner context returns failure; no model loading, cache reset, replay, logs or lifecycle action. A new native CPU-root test invokes only a null context. Failing-first `/tmp/fios-009-llama-terminal-red.log`; `/tmp/fios-009-llama-terminal-green.log`/`.status` exit0: actual native-root5/5 including null-context refusal, genuine target/MTP bridge linkage, MLX owner/default/two-owner checks and HTTP/control/Swift/manager restart pass. Artifact `d8dff2c1864f2788ebb1186ac62d66e73778a88792f0ff3212d8c2b3c5761fa4` deleted; installed runtime hashes unchanged. No actual llama context/model/inference terminal acceptance. Backend-specific requirements are in [native-backend-terminality.md](native-backend-terminality.md).

## Partial MLX owner-thread barrier checkpoint

The reviewed patch now changes **`build.zig`, `src/server.zig`, `src/scheduler.zig`**. The build adds the genuine `device_owner_barrier.cpp` to executable/test macOS roots; it does **not** remove upstream staging/release guards. Four Zig companions (`request_ownership`, `control_protocol`, `control_transport`, `device_owner`) and the C++ source/header are byte-bound by checkers. The fixture additionally compiles/runs the genuine C++ helper with reviewed MLX headers/library, CPU/empty streams only; no replacement backend or inference.

Development private protocol is now **version2**, adding opcode3 for a partial MLX owner-stream probe. Native captures the actual inference thread's kernel ID before startup loads. A one-slot heap request runs there after ingress is closed/owners drained, queued/offloaded work/ANE builds are absent and registry loading/eviction/references are absent. The sender waits at most1.5s; timeout keeps its scheduler reference and occupied slot until actual completion/shutdown. The actual filtered native CPU root verifies timeout retention, second-request refusal and late completion cleanup. No queue/registry/tracker lock spans backend synchronization.

The genuine helper checks thread identity and explicit stream custody before synchronizing anything: every enumerated stream must have a genuine recorded creation owner, and only the current owner's matching subset is synchronized. Bounded pending reservations, non-reusable owner tags and a monotonic stream-creation epoch fence incomplete/changed sets without holding metadata locks across backend calls. Other live/retired owners remain unresolved; this is not an aggregate terminal receipt or native-model registry epoch. Arbitrary/foreign/global stream adoption is refused, even when the caller thread is correct. Explicit owned CPU creation and source-fixture-only CPU/GPU default initialization are implemented. The captured inference thread creates/records defaults before startup only if neither already exists, under the same nonroot marker/build-suffix gate; preexisting/assigned defaults are never adopted. Additional native/model/backend streams remain unsupported without separate ownership enrollment. An owned set synchronizes per stream, rejecting exceptions/changed sets and bounding256 streams. It does not synchronize embedded/ANE/non-MLX backends or manufacture other threads' terminal proofs. Admission/source changes or uncertainty invalidate the partial result. The strict Swift codec remains **unknown-only**, including a successful owner-stream result; neither manager reconciliation nor normal lifecycle issues this probe or consumes it as authority.

`/tmp/fios-009-device-owner-linked-green.log`: actual native-root5/5, genuine C++/MLX CPU/empty-stream/wrong-thread test, live source-owner probe (unsupported outcomes remain unknown), live-ingress blocking, real Swift client and manager restart integration pass. Native artifact `cc4f1e367e7464703412df433b13a0ebe10c4957f88af831164235dc61b3bd6e` was deleted with disposable output. This receipt precedes final protocol contradiction hardening; refreshed checks are recorded separately in validation. No real-model/GPU inference, installed native change or operational acceptance. Subsequent audit invalidates the earlier standalone CPU-sync/wrong-thread assertions: Zig optimized C++ defined `NDEBUG`. Actual Zig-root/live-control receipts remain separate. Always-enabled checks, `-UNDEBUG`/compile-time guard, deliberate exit77 witness and genuine owned CPU/unregistered/global-stream refusal now pass (`/tmp/fios-009-owned-stream-{green,negative}.log`); fresh linked evidence is recorded in validation. That native checkpoint was16/55; T038 owner/pressure wiring now brings the current count to17/55.

Refreshed `/tmp/fios-009-explicit-owner-linked.log`/`.status` exit0 establishes the always-enabled genuine owned CPU/empty/wrong-thread/unregistered/global-stream checks and deliberate failure witness, actual native-root5/5, HTTP/private control/Swift/manager restart. Live native inference-thread probe is partial outcome1/0 streams, global activity unknown. Disposable native artifact `68c2c31c7c3fbd0a7b1f32be8657197bcda182b3d75713efdceb78bb5605f0d4`; installed library pins unchanged. **17/55 complete; G2/T051 remain open.**

Earlier `/tmp/fios-009-owned-defaults-linked.log`/`.status` exit0: native-root5/5, real HTTP/control/Swift/manager restart and genuine inference-thread CPU+GPU default synchronization (`outcome1`, `streams2`). No arrays, weights or inference kernels; global activity remains unknown. Native artifact `e55fd8b3d9d1366a27753e1e3f8cf5cf7f4f3ce9dba2d40e793a3fd89eb2bde2` deleted, installed runtime hashes unchanged. Separate always-enabled assigned-global-default refusal (`/tmp/fios-009-owned-default-refusal.log`) prevents adopting a default merely because it is set on the current thread. This empty Metal-stream result does not cover additional owners/backends, atomic registry epochs, real model terminal completion or lifecycle.

Current `/tmp/fios-009-multi-owner-linked.log`/`.status` exit0: genuine two-CPU-owner custody/default-assignment/unknown-stream checks, actual native-root5/5, HTTP/control/Swift/manager restart. Each CPU owner synchronizes only its1 stream; the live inference owner synchronizes its2 explicit CPU/GPU defaults. Creation uses bounded reservations, non-reusable owner tags and a monotonic epoch, with no metadata lock across backend synchronization. Other live/retired owners remain unresolved: no aggregate/model-registry terminal receipt. Artifact `ead9d0c98ccac73bb6d17700ffa6c24d440ae2fb8073a83c2c8f945b88a92ffc` deleted; installed runtime hashes unchanged. Global activity unknown, no model/inference kernels,17/55 unchanged.

## Enclosing MIMO custody preflights — source increment

Current development source passes known warm-engine lifetime custody through Source/Module, stream-model/Transformer and LoadedModel cleanup before enclosing resets or frees. The engine predicate is mutex-protected; the outer calls are preflights, not an atomic reservation. A held-engine CPU regression and exact predicate bypass fail at the designated marker; optimized focused/upstream CPU tests pass. Ten supplementary source-edge checks reject individual missing delegations, but do not prove runtime model/context retention. Full combined native executable,12/12 ownership roots and private HTTP/control/manager checks pass; hashes and logs are in validation.md.

The native patch covers13 fixed paths. The separately pinned MIMO candidate covers exactly gpu_warm/module/root/source, and candidate receipts hash all four files separately from the binary. Other arches keep existing behavior without this candidate hook. No production lease issuer, all-backend coverage, deferred cleanup, atomic reservation, native terminality or installed acceptance follows. Current whole-task count remains37/55; earlier counts above are historical.

### Checked warm-owner retirement during destruction

Cleanup now goes beyond the earlier preflight: Engine.tryDestroy reports refusal from the held-ticket branch under its mutex, and reports success only after quit/join/backend/header destruction. Source only clears its warm pointer on that checked success. Module, stream-model, Transformer and LoadedModel initiate this retirement before enclosing reset/free; the operation is confined to destruction and never called by status or activity probes. Exact CPU result/lifetime bypasses and18 supplementary source-edge checks are recorded in validation.md. This closes the known warm-owner refusal handoff, without proving every raw caller/backend, bounded GPU failure recovery, atomic aggregate admission or native terminality. Journal uncertainty remains independent.

### Llama wrapper parent/context custody

The wrapper reserves an engine lease before FFI context creation and transfers that lease into the published context. Constructor failure releases only its own lease after native cleanup; a live/pending context prevents engine close. Context terminal synchronization borrows context lifetime. Destruction uses a caller-held close ticket to exclude new children, frees the exact known context, then commits engine close only after its parent lease is released. LoadedModel preserves refusal/uncertainty before enclosing cleanup. The disabled-platform stub refuses the same operations.

Three bounded metadata tests and a private close-edge bypass cover slots, replay, exhaustion and concurrent borrow/close. Supplemental source wiring fails before integration and passes after;14-path native semantic/full linked validation and unchanged MIMO composition are recorded in validation.md. These are not real llama context/model tests. Raw C FFI, stable outer-reference obligations, other callbacks/backends, aggregate admission and installed/native acceptance remain open. No initializer or lease here is a wire authentication/management capability or permission to clear inference uncertainty.

### DS4 wrapper parent/session custody

DS4 now uses the same bounded metadata lifetime: session construction borrows its engine before FFI, error cleanup holds that lease until native cleanup returns, and a published session keeps the engine alive through its own free. LoadedModel checks the exact known parent/child relation before checked teardown; seven fallible session operations borrow session custody. The constructor audit is against the pinned ds4.c source, which publishes its output only on success. No status path calls global DS4 synchronize or initializes a backend.

The disabled-platform stub refuses these operations. Sixteen fixed native paths are now source-bound; supplemental wiring and semantic/full linked receipts are in validation.md. No real DS4 model/session is exercised. Raw FFI, nonfallible raw-operation obligations, all participant/device proof and native admission remain open; this is not an all-client or terminal capability.


### DS4 serialized snapshot custody

The pinned native snapshot is an independently allocated serialized CPU blob; it does not retain a session or engine. Saving now owns a heap wrapper and frees any partially allocated native buffer on failure. Loading borrows both the snapshot and session; checked snapshot destruction refuses while a reader holds its lease. The snapshot may outlive the session and engine without blocking idle replacement. Existing native payload validation remains unchanged.

The actual optimized root regression uses a valid empty CPU snapshot and an external allocator witness: destroying a borrowed wrapper fails before dereferencing freed storage. This exercises empty-buffer cleanup, not a populated model snapshot, DS4 inference, backend synchronization or terminal authority. Raw-pointer callers still require a stable enclosing reference; a freed wrapper cannot be reused as a lease issuer.


### Llama fallible operation custody

Fallible engine tokenization/rendering, batched context steps and sequence
sync/eval/speculative operations borrow their exact engine/context lifetime for
the complete call. An unavailable lifetime returns a distinct error; the legacy
sync recovery path must propagate that refusal before logging/reset/retry. This
does not add any model request or retry to the Pydantic harness. Nonfallible raw
getters, borrowed template views and caller-owned stable outer references still
have separate lifetime obligations; these guards do not establish all-client
coverage, device completion or a native admission capability. These shared lifetime leases do not serialize concurrent backend operations; existing inference-owner/actor serialization remains required.


### DS4 fallible engine operation custody

Tokenization, single-turn/transcript encoding and detokenization retain their
engine lease through native calls, native token cleanup and copying of owned
results. A closing/uncertain/full lifetime refuses before backend access. These
shared leases prevent cleanup during the call; they do not serialize concurrent
backend operations or replace existing actor/thread ownership. Nonfallible raw
getters and stable enclosing-reference obligations remain separate. No global
DS4 synchronization, status-induced initialization or native authority is added.


### DS4 completion audit checkpoint (not an issuer)

The root native checkout pins DS4 submodule `9139e2ae58a41503968a500f36f75895c1ba63fc`.
Its tracked tree was unchanged during this read-only audit. That source identity
is separate from the installed native artifact and the six declared runtime
inputs in linked fixture receipts. Any DS4 changes need a separately reviewed
candidate/patch and input verification, preserving the canonical submodule.

The existing `ds4_gpu_synchronize` in `ds4_metal.m` calls `ds4_gpu_init` when cold,
can finish an open command batch and resets parallel-FFN state. It is unsuitable
for a readonly activity probe. The following independent work/resources were
found; this is an audit inventory, not an exhaustive coverage claim:

| Participant | Source anchor | Remaining completion obligation |
| --- | --- | --- |
| Main queue, open batch and pending buffers | `ds4_gpu_synchronize`, `ds4_gpu_end_commands` | Owner-thread exclusion, no cold initialization, checked native errors |
| Parallel FFN staging | `g_parallel_ffn_mode`, `g_parallel_ffn_stage` | Preserve live encoder/staging ownership; no status-induced reset |
| Tensor-parallel service and separate keepalive queue | `ds4_gpu_tp_shutdown` | Exact service ownership and checked joins; no RDMA/installed action authorized |
| Main-queue keepalive thread | `ds4_gpu_queue_keepalive_thread` | It submits buffers outside the ordinary pending-buffer list; a pending-list zero is insufficient |
| Expert pread pool | `g_stream_expert_pread_pool_active_workers` | Track queued/active work and exact lifetime before releasing buffers |
| Distributed session destruction | `ds4_session_free` | Failed remote acknowledgements currently print an error through a void destructor; not a terminal receipt |

`ds4_engine_close` frees weights before its later GPU cleanup; existing void
cleanup and unchecked join paths cannot be promoted to correlated terminal
proof. The current Zig custody wrappers protect known local lifetime edges but
do not certify these participants. No new global synchronize/status shortcut,
terminal issuer, all-client coverage, uncertainty release or native activation
follows from this audit. T002/T020/T021/T022 remain open.

### Checked llama retirement continuation

Context metadata allocation now finishes before native creation. The C bridge exposes creator-thread preflight and checked terminal retirement; Zig releases sequence metadata and parent custody only after checked success, retaining the closed lifetime and shared uncertainty on refusal. Null-pointer refusal and allocation failures are model-free fixture cases. Full linked15-root/HTTP/control validation passes; seven negative source omissions supplement it. This does not validate loaded contexts, legacy raw C callers, other backends or all-client native terminality. See validation.md for exact receipts.

### Non-fallible llama sequence operations

MTP-width, position, sample/argmax and reset now borrow context custody through their calls. Known unavailable custody returns existing failure/no-draft sentinels; reset retains its CPU mirror, and sampling retains RNG. Metadata-only closing/uncertain/uninitialized cases pass alongside the complete15-root linked fixture. These tickets require a valid outer reference before entry and do not enroll raw C callers or establish device/all-client terminality.

### Owned llama chat-template handoff

The embedded template is copied under an engine ticket and returned as allocator-owned data. Scheduler adoption no longer copies a borrowed native slice after custody has ended; copy/lifetime failure propagates. The native-disabled stub has the same API. Model-free refusal, source-edge omissions and full15-root/HTTP/control/manager integration pass; an actual loaded template/model is not acceptance-tested.

### Fallible engine metadata reads

EOS/EOG/vocabulary/MTP queries hold engine tickets and propagate lifetime refusal through their callers. HTTP vocabulary validation and scheduler token emission fail rather than substituting metadata. Context creation obtains optional MTP metadata before native publication, including nested-capacity refusal with exact parent-ticket restoration. Model-free unavailable-lifetime and full15-root linked checks pass; loaded-model metadata and enclosing all-client/backend ownership remain acceptance work.

### Terminal failure and trim refusal

C terminal exceptions now retain atomic sticky uncertainty. Zig terminal failure fences its lifetime and shared native tracking; releasing a local ticket cannot reopen them. Only native trim0/1 may change the CPU mirror; other statuses propagate lifetime refusal and skip cold retry. CPU-fence and optimized actual-root trim omissions reproduce exact witnesses; final full15-root integration passes. No loaded-context exception or device/all-client terminal proof is supplied.
