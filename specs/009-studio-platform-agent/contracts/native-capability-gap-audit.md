# Native capability gap audit — 2026-11-14

This is a bounded functional source review for T002, T018–T022 and their downstream tasks. It grants no installation, coverage, admission or completion authority. Current task count remains39/55. The reviewed private source is the3736ed55 parent plus the explicitly recorded current overlays; its build receipts are selected-input evidence, not whole-repository/native provenance.

| Boundary | Existing implementation | Remaining acceptance gap |
| --- | --- | --- |
| Accepted HTTP connection | `host/http/request.zig` installs the original token in TLS and retains it through connection cleanup. `host/http/router.zig` resolves and binds the primary before `ensureLoaded`. | No exhaustive enabled-route/modality and slow-reader acceptance; partial primary diagnostics cannot attest all clients. |
| Administrative load | `host/http/router.zig` dispatches `/v1/load-model` before its normal binding; the original `host/api/models.zig` calls the loader without binding that ingress. | The administrative-load increment is locally validated: bind the exact resolved target before preparation and reuse it through a concurrent default change. This does not grant admission. |
| Native load/generation queues | Ordinary generation, shared engine books, and media/vision/embedding senders retain original groups and queue tickets; actual worker pickup activates tickets. Load and ANE completion retain their independent fences. | Queue accounting is implemented for these paths. Complete participant coverage, device-terminal proof and the trusted positive issuer remain missing; local acknowledgement/join is not terminal proof. |
| Companion model preparation | `host/api/audio.zig` has two secondary `ensureLoaded` calls for diarization and alignment. Existing `bindAuxiliaryCurrent` is not called by either original path. | Concrete missing model association before the ready/cold-load boundary; the audio companion increment passes its isolated/full-source validation separately. It does not establish full modality coverage. |
| Idle unload | Registry reserves an exact mutation before eviction. Producer preserves an original bound group, associates a single unbound ingress or reserves an internal root before queue publication. | Internal model metadata is not an authenticated native reservation, device proof or host-wide compatibility contract. |
| Compiled streamed read pool | `build/libs.zig` compiles the C pool; original stop discarded join failures, and the Zig wrapper freed worker storage after failed cleanup. | The streamed-pool increment adds checked refusal and parent/constructor retention; source validation is partial and does not close whole-native/loaded/installed acceptance. |
| Teardown | Scheduler shutdown and registry eviction consult retained custody and sticky uncertainty. SDK capture refuses missing registered ownership. | Creator/partial-start/error paths, CPU/transport/backend writers and public outcome propagation require complete review and native acceptance. Existing local receipts cannot certify them collectively. |
| Native control/primary activity | Authenticated five-phase activity and coupled registry v3/v4 transport, exact model rows, registry generation, claimability decoding and conservative manager normalization are implemented. | No positive all-client coverage issuer, physical residency/device-terminal proof or native proof issuer. Declared readiness, claimability and zero counters cannot grant these capabilities. |
| Manager admission | `NativeActivityCoherence` enforces an independent coverage ceiling. The broker, checked preparation export, private worker and exact native preparation consumer are connected through optional trusted ports. | The positive production source/proof/capacity issuer and all-client non-preemptive guard remain unfinished. The private CPU reservation transport is implemented; it cannot close the external-client race without those independent capabilities. |
| Installed lifecycle | Reviewed configuration factories and development release tooling retain their existing gates. | No reviewed installed all-client boundary, direct-server GUI handover or two-Studio acceptance. Development package staging cannot authorize these actions. |

The companion and administrative-load associations, streamed-pool cleanup refusal and watchdog uncertainty fence have now passed their separately recorded source validation. These repairs preserve the original root/correlation and ordinary unenrolled behavior. The diagnostic `primary_guard=false` remains unchanged. They do not supply the missing normalized producer, atomic admission or native proof issuer. This audit does not propose a new wire format, receipt authority or numerical engine.

T002 remains open until the complete native contract and operational evidence exist. T051 separately requires approved Studio scenarios; Core small-model development receipts cannot satisfy it. T055 also requires review/approval, exact merged-main CI and verified automatic application deployment, independently of native rollout.

## Bounded host load-call review

The current host source's serving calls to `ensureLoaded` are the normal router, the administrative models handler and the audio companion paths. `host/gpu_thread/scheduler.zig` and `host/engines/mlx.zig` forward to the engine; registry unit-test calls are separate. The normal router binds before loading; the administrative route returns earlier and needs its own exact-target association; the two audio paths require auxiliary associations. Source review of `responses/ws.zig` found its turn handling calls the existing response handler on the connection path; no detached writer is claimed from that read. These findings bound this specific host-call review, not every native/backend/internal load or asynchronous writer.

## Upstream capability refresh

On2026-11-14, the public [latest release](https://github.com/ddalcu/mlx-serve/releases/latest) still resolves to26.11.2/4e231ce. The public comparison then reported93 commits ahead at main218c76640228e3860f8a4a67075c9fcd1fa29cae. A bounded read of that exact revision's `src/host/api/admission.zig` and `src/host/registry/registry.zig` found prompt/context memory admission and registry load-memory reservations respectively. Those functions are not the required all-client ownership/device-terminal/atomic dispatch contract. This two-file review is not an exhaustive absence claim about upstream main, and neither upgrades the pinned candidate nor authorizes importing those changes.

## Persistent response and CPU worker boundaries

A subsequent seven-file source read is bound by `/private/tmp/fios-009-cpu-boundary-review-ianuagxs/review.json`, SHA2567687d3a71f80e4670d4860f9cc1b727e72f6b726564ecf1db7892f1c81a18b78. This is a source-read record, not a test or positive coverage receipt.

- The response WebSocket route reaches the existing exact-target bind/load/active edge before the upgrade. Its model borrow and original connection owner remain retained while the handler processes successive turns, until the connection handler returns. An idle socket therefore cannot be treated as an unowned resident model eligible for replacement while that borrow exists. This read does not establish per-turn terminal proof or whole slow-reader acceptance.
- `sdk/media/progress.zig` retains/enters the existing CPU offload origin, joins the job and optional keepalive thread, and uses an inline pure-CPU path after capture/spawn/entry refusal. The keepalive is transport work. This is not authority to execute GPU work on those CPU helpers or clear uncertainty.
- The inspected GGUF affine-conversion and NVFP4 bank-fill workers operate on host buffers and join before the caller creates/copies MLX arrays. Their normal join ordering does not by itself establish terminality for the subsequent MLX work.
- `RowGather.init` and `PrefetchPool.create` retain their successful thread count and join those workers on partial-start failure before freeing storage. Their ordinary destructors also join before free. No missing partial-start cleanup was found in these reads.
- The n-gram poster drains already queued host gathers before its loop exits; destruction joins before freeing the poster. This is not all concurrent callers, parent lifetime or native-device acceptance.

No source repair is justified solely by these reads. Backend/registry/process-generation proof issuance and the positive all-client compatibility ceiling remain unfinished; no task checkbox changes.

## Additional bounded participant read — 2026-11-15

Read-only receipt `/private/tmp/fios-009-participant-read-a5il1sif/review.json`, SHA256293d000d2d513317e9454714deeadeb8206a2e6abe66c8d7825f39ff613f84fd, binds six selected P34 source files. This is not a test, complete call-graph proof or native coverage receipt.

The reviewed SSD writer queues owned host-byte buffers rather than MLX handles. The QSA pooled-rope thread occurrence is inside a test. The sparse neighbor worker transforms CPU arrays and joins before returning. These reads justify no native ownership repair for those paths.

Distributed startup is different: `main` invokes `cluster_connect` before serve startup, and `connect` detaches `waitForWorker`, which reaches `Link.open`/`askForModel` native/distributed operations. Current HTTP scope instrumentation cannot be promoted to coverage of that participant. No transport/RDMA code, settings or real traffic was changed or run. Distributed/all-client compatibility and operational acceptance remain unproven; T002/T018/T020–T022/T051 stay open. The later internal preparation/ingress metadata link supplies no authority across that gap.


The configured distributed CLI paths now additionally set a sticky negative
marker before their existing entry calls/validation; the HTTP fixed getter
composes it without reading the unsynchronized peer pointer. This is an explicit
refusal for an unproven mode, not tracking/proof of those actors or any RDMA
operation. Exact source/CPU/native-empty enclosure scopes and the old-composition
baseline isolation are recorded in
[distributed-mode-negative](distributed-mode-negative.md). Serving admission
stays unsupported; the all-client contract remains unproven.

## Relocated streamed private-queue warmer — 2026-11-15

The current `sdk/weights/streamed/mimo/gpu_warm.zig` and its C include construct
and commit on an independent Metal queue. `glm5n/experts.zig` installs that
existing warmer, and the stream-source gate/host-wait paths arm it. The current
file lacks the older fcb4011 source's request-origin/retirement port. SDK
CommandEncoder custody and the seven other independently false backend flags
cannot establish coverage of this queue. This is a concrete bounded participant
gap, not proof of a missing mechanism in every upstream file.

The [streamed-warmer negative increment](streamed-warm-mode-negative.md) marks
construction before its C boundary and composes that sticky marker in the fixed
host getter. Strict CPU/module/object cases, default162/162, enabled semantic/
link and4 empty-model runtime checks pass. No numerical/worker/model-setting
behavior, actual guard activation or
native proof is added. Completing this participant's ownership/retirement port
and the full all-client contract remains required; T002/T018–T022 stay open.


### Later current-warmer qualification

The subsequent current ownership port is recorded in
[current-streamed-warm-origins](current-streamed-warm-origins.md), followed by a
separate ten-case genuine Metal supplement. Actual original request groups now
survive two event-blocked current warm chunks, retire after physical completion,
and remain quarantined on independent uncertainty or injected API failure after
real completion. This supersedes the earlier absence/CPU-only observation for
that specific port, without establishing complete all-client/producer coverage,
normalized native activity, positive model proof or admission. Serving code and
settings remain unchanged;39/55 whole tasks remain complete.

## Original preparation and readonly claimability continuation

The internal registry claim now has a bounded single-use lease bridge, private
source-fixture Unix reserve/withdraw transport, exact bound-chat consumption and
typed Core acknowledgements. Original receipt identity and launch-plan binding
remain separate from admission. The current native primary guard stays false;
these paths are not production native authority.

A subsequent source read found that v3's ready/transition/uncertainty flags do
not distinguish an owned unloaded target from an errored one. Version4 supplies
an explicit registry-computed claimability flag while preserving v3 encoding and
unknown claimability for old frames. Claimability is not capacity, complete
coverage or terminality. Current Core requests4 without downgrade.

The scoped preparation consistency helper requires an independent all-client
ceiling, current original lease, fresh matching root/registry capture, exactly
one original preparation owner, no competing work/transitions/uncertainty and
at most one ready declaration. It separates target from registry-ready identity
without changing generic conflicting-model unknown semantics. Subsequent work
implements the original-plan/journal-bound observation, readonly manager relay,
metadata3/preparation1 worker client and optional broker/factory preparation
mode. These use the original lease and independent all-client ceiling; unknown
global activity is not a fallback. The complete positive source/proof/capacity
issuer and production composition remain unfinished. See
[claimability](registry-claimability.md), [reservation](preparation-reservation.md),
[transport](preparation-transport.md) and the current
[worker preparation client](worker-preparation-client.md). Whole39/55 is unchanged.

## Current manager/worker frame compatibility

The Python worker previously accepted only the legacy v1/supported observation,
while the manager exports v2/all_clients-or-unknown activity. Strict v2 worker
validation now handles native versus manager sequence, coupled source age,
phase/model coherence, local uncertainty and correlated Unix envelope checks.
Actual current Swift export frames pass through the installed Python guard in
both build modes, with unknown/conflicting/preparing frames refused. This fixes
format compatibility; the production manager still has unknown coverage/activity
and remains closed. The separately implemented scoped preparation export and
broker/worker transport do not supply the missing source authority. See
[worker activity contract](worker-activity-v2.md) and
[worker preparation client](worker-preparation-client.md).

### Public v26.11.3 release delta (2026-11-20)

Follow-up: stock `src/host/http/router.zig` (SHA-256 `38060ea3fe6a0247eb25423e91c483ec05a148a7b21a123b3e26a9c51ab8b997`) explicitly returns health/catalog metadata before `scheduler.ensureLoaded`; this supports the scope of the no-inference inventory. The later `ensureLoaded`/deferred release covers handler model custody, and `admission.pinAutoContext` pins context sizing; neither is a caller-bound Spec009 reservation or original-request terminal receipt. LAN authentication/shared-model checks are access checks, not a complete native admission boundary. A patched candidate must cover WebSocket and media/embedding ingress as well as chat, and separately account for distributed participants noted above. This is a source receipt only, not runtime or installed qualification.

Offline source comparison of the 67 tracked `mlx-serve-26.11.2-*.patch` files found 93 unique touched paths, of which 32 existing files changed upstream and none were added/removed between the two source archives. Standalone `git apply --check` against fresh trees: 19 match both, 44 fail both (not an ordered-series test), 4 match only v26.11.2 (`build-input-preservation`, `h3-ane-cleanup-custody`, `plugin-load-custody`, `unload-origins`). No patches were applied or executed. Source archive receipts (v26.11.2 / immutable v26.11.3 commit): `a71c46f461bc055346014d6f30f1be2e0fd2447f3829528e88d2a12c9a7a95d3` / `f48a65d735a77fb2366b77d0000ff7f13794a505e66b67c1bab0dedc43500271`. Start ordered candidate reconstruction from the pinned prior parent chain, review the four demonstrated context regressions against semantic custody invariants, and separately audit the other touched paths; matching hunks cannot establish native qualification.

Remaining port order is constrained by ownership dependencies. Stock plugin `driver.zig` still directly calls `b.table.load` and uses `errdefer b.table.unload`, with `unbind` returning void; transplanting its higher-level custody patch without a checked destructor would falsely report retirement. H3 adds split/fused `Qkv` and full/low-rank `Proj` construction/destruction, and an image-only DiT without an audio stream; ranked construction and partial failure must preserve the new shape rather than transplant an old destructor wholesale. Stock `load_requests.zig` still invokes void `unloadResident` before `accountEvictedLocked`/`finalizeEvictionLocked`; prove the checked close/registry transition and all consequences before attaching an unload origin. These are source constraints, not positive proofs. Sequence: checked producer teardown → retain failed parents/resources → verified registry/accounting transition → attach and test origin/settlement; leave stock links and enrolled pins unchanged in the meantime.

v26.11.3 added a nonblocking `submitNow` used by scheduler-owned warm requests. Port the negative cleanup check to `submitWaiting`, before allocation/model borrow, not merely the blocking `submit` wrapper. This closes a local pre-existing-uncertainty refusal difference, not an atomic admission or warm ownership proof. `warm_requests.tick` can submit after the initiating caller departed; `endRequest` releases its slot and `end` destroys the twin prefix cache and queue item; `forget` and `stop` share that unchecked retirement. Checking uncertainty after `forget` can prevent further victim close/accounting but does not recover lost warm custody. Before claiming active coverage, independently bind original warm producer/root before queue publication or explicitly classify it as uncovered, and prove exact checked slot/twin retirement or retained parent with finite shutdown. Preserve queue-full nonblocking behavior; never force-load or run warmup in discovery.

The warm slot borrows `&w.twin`; `complete` only transfers it to the cleanup queue, and `drainSideQueues` returning `true` means work was dequeued, including quarantine. It does not say which exact slot released its checkout or no longer references the twin. A checked handoff must return an exact retirement result without dereferencing a freed slot, distinguishing never-published, released, and retained-on-refusal. Keep the original `Idle` and its twin on refusal and prevent `stop` from repeatedly trying the same refused item. Independently cover the eager `serve` path: its twin can outlive a stack frame only if ownership is moved to a retained heap object before submission. Model-free controls should exercise an original slot refusing cleanup, a different cleanup item in the same drain batch, successful exact retirement, and ownership preservation through stop/unload. Do not turn these local results into all-client coverage.

The public tag binds `90047978512c5a18ee277448812932350f2c7351`. The Git tag-to-tag comparison against v26.11.2 has 1,037 changed path entries; the following is a scoped source read, not a complete compatibility review or proof of the installed version. The HTTP server adds memory-attribution gauges and counts `submit_waiting` alongside the scheduler pending queue under its lock. These are sampled accounting, not a causal all-client activity envelope, original-request terminal evidence, or an atomic admission reservation. They cannot make zero an idle witness or settle retained uncertainty. The public app `ProcessRegistry.swift` and `src/host/lan/` paths are unchanged; that alone does not qualify installed handover, discover a serving endpoint, or justify changing pins.

The downloaded public `MLX-Serve.dmg` matched the release asset digest `8609126ac89cc1d03cf5715692b7aed1add7cf8dbc928f9c793b610c2e67a98c`. Both GUI and server executable hashes from the read-only image match the pre-reboot on-disk hashes on both Studios. This is packaged byte equality, not independent tag-to-build reproducibility, mapped-process byte attestation, or qualification of the native boundary.

### Bounded upstream recheck (2026-11-16)

The public latest release remains v26.11.2. Main92cecaaf83c47f7bcc81c21250d8e50a7bdfe462 is97 commits ahead of the pinned release and4 beyond the prior218c766 audit. The [four-commit comparison](https://github.com/ddalcu/mlx-serve/compare/218c76640228e3860f8a4a67075c9fcd1fa29cae...92cecaaf83c47f7bcc81c21250d8e50a7bdfe462) changes10 cache/prefill/accounting/sampling-related files. Those changed paths provide no new normalized activity/terminal/admission interface to adopt. This is a bounded comparison, not an exhaustive absence claim about all upstream source. No newer code or installed version was imported.

The optional SDK residency-refresh participant is separately documented in [sdk-residency-refresh.md](sdk-residency-refresh.md). Matched SDK/C binding/native build and empty-catalog checks now pass. Explicit
private background exclusion and the Core scalar ownership component also pass;
ordinary refresh retains its coverage gap. These selected component receipts
cannot close the positive all-client contract. See
[build exclusion](native-background-seal-build.md),
[constructor ordering](residency-constructor-refusal-order.md) and
[GPU scalar ownership](sdk-gpu-scalar-ownership.md).

## Current queue and transport reconciliation — 2026-11-16

Bounded source-read record
`/private/tmp/fios-009-queue-map-read-mz88qdev/receipt.json`, SHA256
`611794686be780f5fee3dda0b355f69d7ff64bc448e9c06f23ba195ce70c2b61`,
binds seven current native and five Swift files. It is a source read, not a new
test, exhaustive audit or positive coverage receipt. The current native source
is separately qualified by54b97159a326f36b1a1d296775246b71d9a37fe9c55c8eaec635865d3add84bc.

- `current_queued_origins` already captures exact-model tickets before sender
  publication, clones the worker union, activates original tickets and retires
  after acknowledgement. Generation, vision and embedding senders/workers use
  it. Shared engine books separately retain and activate original requests.
- Five-phase and registry transport already exist. The Swift client explicitly
  requests registry4 and refuses an older response rather than falling back.
  Decoding validates exact identities, phase totals, registry generation and
  claimability consistency; these remain declared registry metadata.
- `NativeRegistryActivity.conservativeActivity` deliberately supplies unknown
  coverage. The reviewed readonly source resolver already selects the exact
  authenticated peer. `NativeOwnedPreparationCoherence` requires an independent
  all-client ceiling before returning its narrow original-preparation result.
  None of these components supplies that ceiling or physical residency proof.

Historical notes saying media queues, five-phase transport or conservative
normalization are unimplemented describe earlier checkpoints. Do not implement
those paths again. The remaining integration is the audited positive coverage,
completion/capacity issuer, atomic all-client guard and eligible production
composition. Existing source fences remain independent and unchanged;39/55
whole tasks are complete.

### Bounded upstream recheck (2026-11-19)

Public latest release is still `v26.11.2`. Public main
`c1e256ada9228e0433e75e93b8b8a7167933ce75` is 14 commits ahead of the prior
`92cecaaf…` checkpoint; the comparison reports 241 changed paths. The selected
`src/host/api/submit.zig`, `src/host/registry/registry.zig`, and
`src/engines/mlx/admission/bills.zig` diffs cover local submit behavior, registry
path identity, and KV accounting. None of those selected changes exposes an
independently authenticated all-client activity source, exact-root terminal
proof or atomic all-client admission interface. This is not an exhaustive
review of the 241 paths. No upstream change was imported or qualified.

### Candidate positive completion boundary (not implemented)

A completion producer needs two distinct publication edges. The root must first stop accepting independent operations under the same lock used to begin them. Existing operations must still be able to hand off to legitimate descendant work; doing this by forbidding all retains in `responding` is incorrect. A descendant publication must be authorized by a live parent operation, and counted before releasing that parent, including deferred cancellation paths. Only after this graph closes may a backend completion issuer seal the tuple `(native epoch, correlation ID, root sequence)` against future publication. For each kind of backend submission, the original-root capability must survive command completion and any completion callback that can publish more work. An owner reference reaching zero or a single command buffer completing cannot substitute for closure of those edges.

A mock design test should interleave independent publication, valid descendant handoff after root closure, deferred cancel, mixed-root backend batches, and a late callback. It must also reject a matching request ID with a different root or process epoch. Until every dispatch path has an audited producer, no positive receipt or journal release is enabled. Closed admission for the original root is not an all-client reservation for a different request.

The alternative process-epoch reconciliation path needs its own fixture and issuer. Bind the original dispatch to a reviewed process identity at the time of dispatch, then verify absence of that exact identity through an independent trusted observer. A new listener/instance, endpoint refusal, PID alone, or a locally reaped child without the original binding is not substitute evidence. Test PID reuse with a different start identity, observer unavailability, and a simultaneous unrelated uncertain root. A receipt for one original process must not release records bound to another process, or records lacking the original binding. This remains a design requirement, not an enabled reconciler.

Current SDK mapping: `retainCurrent` expands thread-local root tokens into references; merge unions the contexts' root tokens before `retainTokens`. These carry root identity but not a distinct operation handle whose release can be checked. The design model uses such handles to reject stale-parent publication even when another operation on the same root remains live. Any native mapping must preserve and validate the parent capability at capture/merge/release, and cover callback-originated submissions before enabling a seal.

The reviewed `mlx-64ea011-owner-uncertainty.patch` already executes Metal completion work and explicit capture cleanup inside `FiosRequestOwnerScope`. Its `StreamThread.enqueue` wrapper also destroys the task's captures within that scope, because destruction itself may enqueue SDK work. In a future mapping, the callback operation must be issued before registering the handler and remain live through that destruction. Device completion can retire the device operation but not the callback's capability. This read verifies those wrapper boundaries only, not complete backend coverage or native proof.

The mock operation table now uses a fixed slot plus a nonwrapping generation and an independent table identity. Reuse of a slot changes the generation; exhaustion permanently retires that slot, and replacement tables reject old handles even when slot and generation coincide. Refusal is only safe if it prevents publication. A backend path that already published before discovering an untracked handoff must fence the original root, not treat the refused allocation as completion.

Candidate copied-handle boundary: the actor scope would install a checked operation handle alongside its existing root group; an SDK capture would read it while still on the actor thread and reserve the SDK child before publication. SDK merge would validate both owned contexts and reserve their union before either context can be released. Enter/leave would install only a copied handle and a unique frame ID, never make a borrowed token slice the source of operation identity. Existing SDK error handling retains root references and fences on context allocation failure; it cannot be changed to a successful local rollback without a separate guarantee that the SDK had not published work. This is a proposed mapping, not a change to the pinned workloads.

Background provenance is a separate question: the `FIF9` v3 residency-refresh flag is a negative diagnostic for the named SDK path, not a census. Work proven independent of a root must not be assigned to that root merely to make its reference accounting balance. Missing origin on a path that can inherit from a root, however, is uncertainty, not evidence of independent background work. A clear bit for the residency-refresh path does not establish that all other dispatch paths are tracked, and per-root local closure does not clear the gap.
