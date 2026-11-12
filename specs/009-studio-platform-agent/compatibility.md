# Installed Studio compatibility — 2026-10-26

## Current read-only update inventory — 2026-11-12

With existing strict-host-key/batch SSH and finite fixed metadata commands, edge-b reports macOS27.2.1,256GiB RAM,Mac15,14/Apple M3 Ultra, MLX-Serve26.11.2 and OrbStack2.2.5. Current on-disk vendor server SHA256 is `6fdef72cfbc88c1ba3cf06546eccbf7fd571d0ec968801e8e4c78dcf03b6009e`; GUI executable SHA256 is `971145725dc1ef933f8b4f502dc7957dde09a75a8fe5cc3fbac9f5c2c42690a1`. Native-local health returns200. These are current file/version observations, not kernel-bound running-image, dependency or all-client contract attestation. Edge-a SSH fails before remote execution with `Host is down`; this is unknown connectivity, not idle, terminality or authority to recover it. Logs: `/private/tmp/fios-009-fios-edge-{a,b}.lab-inventory-20261112.log`.

Edge-b's own native-local catalog GET advertises ten IDs, including five peer-suffixed edge-a entries (`/private/tmp/fios-009-edge-b-catalog-20261112.log`). Peer advertisements do not prove edge-a readiness/locality and were not followed. The two previously documented exact large text candidate IDs remain advertised without substitution. No model, start/stop/restart, configuration, routing/RDMA or privilege action occurred.

The public26.11.2 tag resolves to `4e231ceebe63308cc038117d40b9f9b64bd0372e`; a clean private checkout at `/private/tmp/fios-009-upstream-26112-6ywcy8w4/source` supports read-only source review. Its `src/host/api/admission.zig` delegates prompt/context memory admission to the engine ABI; those reviewed functions are not an all-client host observation/quiescence contract. This limited check does not claim exhaustive absence of other facilities or close G2. Older26.10.3 native source fixtures and inventory remain explicitly historical/candidate inputs; no old receipt is promoted to installed26.11.2 compatibility or installed admission authority.


## Direct server ownership decision2026-11-01

The operator selected direct agent ownership of `mlx-serve`, rather than GUI
ownership through a control adapter. See [the lifecycle contract](contracts/native-server-lifecycle.md).
Read-only SSH process inventory at2026-11-01T16:51:52.674715Z found the native
server parented by MLXCore on both Studios: edge-a server63833/GUI63804 and
edge-b server2737/GUI2579, all UID501. Only PID/PPID/UID/executable metadata was
collected; no arguments, environment, model request or native action occurred.
Receipt: `/tmp/fios-009-serving-process-ownership-inventory.json`. These are
historical observations, not current ownership/absence, reviewed executable
identity or launch authority. No installed ownership handover has occurred.
The handover must preserve reviewed configuration and prevent competing GUI
launches, with separately reviewed installation/rollback; source implementation
continues independently.

Read-only cwd inventory at2026-11-01T19:31:18.496734Z found `/` for both
MLXCore and the native server on both Studios, with the same PID/UID/executable
metadata as the earlier snapshot. Receipt:
`/tmp/fios-009-serving-cwd-inventory.json`. Collection used only fixed process
metadata and cwd-only `lsof`, with before/after metadata comparison; it read no
arguments, environment, credentials or model data and performed no service
action. This is a historical cwd input for handover review, not process-start/
image attestation, current/native ownership, absence, readiness or admission
authority. The reviewed profile must retain an explicit cwd; do not assume
launchd/manager defaults reproduce it.

The inspected pinned upstream `ServerManager.start` calls its name/port-based
`killOrphanedServers` before launching the bundled child. A native startup lock
alone cannot prevent that GUI controller from first disrupting an agent-owned
server. Disabling GUI autostart alone is therefore insufficient for handover:
the reviewed installation must also address manual GUI lifecycle interference.
Do not enable managed ownership while the old GUI can still perform those
actions. This is an installation compatibility requirement, not permission to
patch/re-sign the installed GUI or change its settings now.

**Current scope (2026-10-31):** Native hardening and security-adjacent investigation are stopped at the operator’s request. The source matrices and receipts below are historical evidence, not instructions to resume that work. Ordinary functional implementation, native integration and correctness checks continue; installed activation and disruptive acceptance remain separately gated.

## Host/model roles clarified2026-10-31

Small models run only on `fios-core`, the24GiB M4-family Mac Mini. The two Studios (`fios-edge-a`/`fios-edge-b`) host larger models only. The local read-only observation reports hostname `fios-core.lab`, LocalHostName `fios-core`,25,769,803,776 memory bytes and CPU `Apple M4 Pro`. This identifies the development host for the fixed small-model source runner; it does not enroll a Studio or authorize any model/lifecycle change there.

The fixed Gemma source experiment now checks/binds core’s host profile in its plan/check/run receipts. Its small-model response/unsupported-image observations,12GiB process abort threshold, local12GiB VM-cap reading and24GiB-host performance measurements are core development evidence. They are not Studio resource sizing, large-model compatibility or Studio acceptance. Future Studio scenarios must use their reviewed larger exact model IDs and host-specific budgets, with installation/disruptive acceptance still separately gated.

## Hardware planning follow-up2026-10-31

Within the existing read-only inventory authorization, a fixed `sysctl -n hw.memsize hw.model machdep.cpu.brand_string` over existing strict-host-key SSH reports EdgeB RAM274,877,906,944 bytes (256GiB), hardware model `Mac15,14`, CPU `Apple M3 Ultra`. No model, application, runtime or configuration operation ran. EdgeA’s SSH connection to its existing `.lab` address failed before remote command execution with “Host is down”; current SSH availability/RAM are unknown, not evidence of native idle or power state. The operator subsequently reported rebooting EdgeA; this does not authorize agent-initiated lifecycle/acceptance work or retries during that reboot. After the operator reported it working again, one repeat of the same read-only hardware query succeeded with the existing SSH key:274,877,906,944 bytes (256GiB), `Mac15,14`, `Apple M3 Ultra`. No SSH/key/service/network setting was changed by the agent; the earlier connectivity error remains historical rather than current availability.

Offline planning with the confirmed EdgeB total retains the existing reserve formula:54,975,581,389 bytes (20% rounded up to a byte), displayed approximately51.2GiB. This is a planning calculation, not current free RAM, model fit, a reservation, global VM enrollment or Studio acceptance. The separate core24GiB figures remain core-only development data.

## Authorized read-only inventory

After the user reaffirmed proceeding in response to the explicit narrow amendment/read-only SSH proposal, used existing SSH authentication with `BatchMode=yes`, `StrictHostKeyChecking=yes`,5s connection timeout. No host-key enrollment, privilege escalation, process changes, service configuration or model workload.

| Observation | Edge A | Edge B |
| --- | --- | --- |
| Confirmed hostname | fios-edge-a | fios-edge-b |
| macOS |27.0.1 |27.0.1 |
| Architecture |arm64 |arm64 |
| MLX app / serving API version |26.10.3 /26.10.3 |26.10.3 /26.10.3 |
| MLX code identifier / team |com.dalcu.mlx-core / S77TW432YG |com.dalcu.mlx-core / S77TW432YG |
| MLX app executable SHA256 |26a368e8dc05c963ff8521d5ddef36a9103214387f4857ca436dba0e1fa6e3bf |26a368e8dc05c963ff8521d5ddef36a9103214387f4857ca436dba0e1fa6e3bf |
| OrbStack app version |2.2.5 |2.2.5 |
| OrbStack app executable SHA256 |48e096f309541c42ff9aa029dd1afae06bcae2875aa4a6c1ca273f79d44d9738 |48e096f309541c42ff9aa029dd1afae06bcae2875aa4a6c1ca273f79d44d9738 |
| Native-local `/health` |HTTP200 |HTTP200 |
| Native-local `/metrics.json` |HTTP200 |HTTP200 |

Local HTTP reads were fixed loopback URLs, no proxy, timeout2s and1MiB maximum response. Printed only status/version/key names, never metrics sessions, prompts, response text, credentials, process argv or native log bodies. App executable hashes do not attest the independently running native child/config/source.

## GPU and configured-VM-cap follow-up

Within the same authorized read-only SSH scope, queried only AGXAccelerator numeric PerformanceStatistics and, after `orbctl status` reported running, `orbctl config get memory_mib`. Fixed native commands, bounded capture, strict host keys and no privilege escalation. Only selected numeric facts were emitted; no raw registry/session/configuration/log bodies or credentials were recorded.

| Observation | Edge A | Edge B |
| --- | --- | --- |
| Readable Device Utilization % counters |1 |1 |
| Instantaneous GPU percentage |0.0 |0.0 |
| Configured OrbStack cap, MiB |16384 |16384 |
| Running Linux machines |0 |0 |
| Native orbctl/scli SHA256 |`b2793e99e3f452b86233d59cd5e503e069821224c022628f52521dc5b4bcab8a` |same |

The native orbctl alias resolves to `/Applications/OrbStack.app/Contents/MacOS/scli.app/Contents/MacOS/scli`; this is separate from the Docker multicall client. Subsequent fixed read-only hash/list queries recorded only its digest and the machine count, never machine names or raw inventory bodies. The development manifest now pins `orbctl_cli_sha256` separately from `docker_cli_sha256`; neither inventory pin grants enrollment.

This establishes actual target GPU-counter accessibility and a16GiB configured cap on both Studios. Zero here is an observed instantaneous counter, **not** all-client idle proof. The configured cap is **not** remaining usable VM capacity. No inference, remote containers, application restart, settings change or installation occurred. Fixed same-kernel memory readers and capacity-policy tests are described in telemetry-research.md; their production enrollment and continuous whole-VM coverage remain pending.

## Current serving/catalog preparation (2026-10-31)

A later authorized read-only inventory uses only fixed loopback native health/catalog GETs over existing strict-host-key SSH. Edge-a SSH works, but its native health read returns no HTTP response (curl000); no model/catalog call, restart or configuration action follows. Edge-b returns health/catalog200/status ok and advertises five unloaded entries, including the two large text candidates recorded in [native acceptance preparation](native-acceptance-preparation.md). Disk/resident/model capability metadata is not peak native memory, idle, locality/enrollment or acceptance proof. No model was loaded or invoked; existing profiles and services are unchanged. Logs: `/tmp/fios-009-studio-model-inventory-20261031.log`, `/tmp/fios-009-edge-b-text-model-metadata.log`.

## Gate G2: NOT SATISFIED

Both local metrics responses expose `counters`, `decode_serial`, `gauges`, `histograms`, `sessions`. Gauge keys include `process_start_time_seconds`, `requests_prefilling`, `requests_running`, `requests_waiting` and resource/token counters. No raw session content was logged. Loopback metric availability resolves access feasibility; it does **not** establish coherent per-request ownership or all-client idle semantics.

The version-aligned public source already inspected in research shows running/waiting sampled from scheduler counters, while model acquisition/preloading occurs elsewhere. The existing public metrics have not demonstrated coherent ingress→preparation→queue→compute→response-delivery ownership. A resident-only interface is not a user requirement and is no longer an acceptance prerequisite. Searches of the reviewed server source did not identify such a contract; absence of a search hit is not claimed as exhaustive proof that no internal facility exists. None of the documented/observed capabilities currently proves the required behavior.

Therefore T002 remains incomplete for native activation/acceptance. The mistaken dependency blocking all independent implementation has been removed; local implementation and mock testing proceed. Do not invent a green gate from zero counters or implement managed-only accounting and claim all-client correctness. No unsafe experiment was run to test this hypothesis.

## Required integration decision

A versioned native observation/admission integration is required if no supported existing API can provide the activity contract. Source-only integration/testing against pinned26.10.3 is already authorized (user reaffirmed2026-10-27); do not request that approval again. See `native-integration.md` for implemented development hooks and remaining technical acceptance gaps. It needs all-client ingress/preparation/queue/compute/response ownership, coherent model/instance/sequence, native non-preemption while allowing normal on-demand replacement of an idle resident model. This is a serving-software change, not a Docker/SSH access workaround. Do not patch/restart the installed native application, inject instrumentation, open metrics remotely or install a proxy pretending bypass clients cannot exist.

## Follow-up read-only child/runtime inventory

Using the same bounded strict-host-key SSH scope, queried only the11234 listener PID/executable path, executable hashes and filtered local Docker info. No process argv, environment, container configuration, raw sessions, model call or service change.

| Observation | Edge A | Edge B |
| --- | --- | --- |
| Listener executable | `/Applications/MLX-Serve.app/Contents/MacOS/mlx-serve` | same |
| Observed listener PID (ephemeral, not identity proof) |40245 |2737 |
| Listener executable SHA256 | `4c2416121c33011bddd0002f4179b7b0b1a273136a6f2041286c80285d422a62` | same |
| Docker multicall CLI SHA256 | `927c58aed356a37f08f2586a90df4c6d8c5e890060de95ac3d11301d03959463` | same |
| Explicit private Docker socket | `/Users/mcteer/.orbstack/run/docker.sock` | same |
| Docker server / OS / architecture |29.8.2 / linux / aarch64 |same |
| Reported runtime CPUs |32 |28 |
| Reported runtime memory bytes |16814260224 |16814907392 |

CLI is `/Applications/OrbStack.app/Contents/MacOS/xbin/docker-tools`, invoked through its fixed `docker` basename. Read-only daemon commands used explicit `--host unix://...` and `DOCKER_CONFIG=/var/empty`. These observations identify the actual listener file and runtime envelope; they do **not** prove source equivalence, all-client lifecycle coverage, configured-limit enforcement, PID start identity or caps surviving reboot. No runtime setting was altered or increased. Native G2 and live overlap/race/slow-reader acceptance remain pending; independent service/package implementation/testing continues.

### Native capture versus request sequence (source checkpoint)

The unknown-only source diagnostic now exposes `sample_sequence` independently from request-allocation `sequence`. Both are process-instance-bound. Sampling advances its own JSON-safe counter under the ownership mutex; request/admission tickets retain their original allocation/maintenance semantics. Exhaustion saturates and fences uncertainty. A future normalized adapter must use the capture counter for native observation replay checks, not mistake allocation stability for a repeated sample or refresh an old sample by assigning a manager sequence. Native capture timestamps, authenticated process/profile binding, full source/ABI/modalities/device coverage and native atomic admission remain separate unfinished integration; this diagnostic still reports unknown and cannot authorize model work or lifecycle changes.

### Primary admission edge (partial source protection)

The serving ownership singleton now enables a code-only guard that atomically checks and commits a registered primary identity before the current HTTP bind→prepare/load edge. Existing primary ownership includes preparation, compute/queue aggregation, response delivery and retained references. Same-primary callers may share; another primary waits for all earlier tracked owners to release (the current API refuses conflict rather than queues/retries). Auxiliary component identities stay attached to the original primary. Conflicts leave the earlier owner/uncertainty unchanged; already-uncertain or uninitialized tracking refuses new guarded binding. This is not a complete native compatibility contract: bypass registry/load/unload/preparation paths, all modalities/backends, true device terminality and installed source/profile proof remain unfinished. No all-client capability is issued and the diagnostic remains unknown. T002/T019/T022 remain open.

### Request ownership versus registry eviction (source checkpoint)

The opted-in serving registry now reserves an exact model-transition ticket under the same ownership mutex used by primary and auxiliary binding, before committing `.evicting`. A model with tracked owners (including a retained responding owner after backend refcount reaches zero) cannot be selected for explicit unload or forced/LRU/RAM eviction. Once reserved, new bindings to that exact identity fail until the matching transition ends. Tickets bind source instance, slot and monotonically increasing allocation; stale/foreign release cannot clear another transition or uncertainty. The registry retains tickets through its existing destruction/finalization or plan rollback. The serving pointer is installed under the registry mutex after scheduler initialization; standalone registry characterization remains unenrolled.

This closes a specific binding-versus-eviction race, not all-client non-preemption. Startup/warmup before enrollment, raw destructor/background/backend paths, cache transitions and true device completion still require audit/integration. Registry finalization is not elevated to device-terminal proof. Transition metadata is bounded to64 exact1024-byte identities, with uncertainty on exhaustion; it is not exported as normalized source coverage. Coverage remains unknown; T002/T019/T022 stay open. No installed native process/configuration or real model inference was changed.

### Scheduler preparation ownership (source checkpoint)

The serving scheduler now resolves a canonical registry identity without model effects, reserves a bounded internal preparation owner before the ready fast path or dropped-mutex CPU preparation, and retains it until the load call and its resource defers finish. Direct callers are checked against still-owned primaries. A current native parent must match its exact live token and requested primary/registered auxiliary membership; the child inherits that primary, retaining both primary and auxiliary identities independently. A load request with only preexisting ingress binds that original owner too, keeping the identity until its connection releases. Pre-fence parents may continue after maintenance closes new ingress; unrelated direct preparation cannot enter. Exhaustion/stale tokens never refund earlier ownership or uncertainty.

This represents internal load operations as additional conservative owners; the unknown-only diagnostic is not a disjoint normalized HTTP-request count. Startup before the serving-registry opt-in, raw backend/context/cache mutations and true device completion still require audit/integration. A ready borrowed pointer used after this method returns needs its caller's existing request/backend ownership; this wrapper alone does not prove every such caller covered. No all-client/source capability, terminal proof or installed activation is supplied. T002/T018/T019/T020/T022 remain open.

### Structured native refusals (source checkpoint)

Primary-binding failures in the common request and explicit-load handlers now use the same bounded response path as load failures. Recognized model conflicts/transitions return structured409 responses; maintenance and unavailable/uncertain/exhausted tracking return structured503 responses with fixed public types/messages. The formatter performs no owner release, retry, substitution or management action and includes no raw native error name or process/filesystem detail. Pre-header connection admission remains independently closed during a native pause; this change does not promise a parsed HTTP response before a request exists.

An HTTP refusal is not a correlated native not-sent/terminal proof for the manager ledger. It cannot clear old uncertainty, reset a model budget or supply all-client coverage. Startup/backend/device-terminal/native-profile/activation gates remain open; the development source diagnostic stays unknown.

### Supplier architecture evidence for the VM resource issuer

Reviewed2026-10-29: OrbStack's [architecture documentation](https://docs.orbstack.dev/architecture) describes one shared Linux kernel for Docker and Linux machines. Its [settings documentation](https://docs.orbstack.dev/settings) defines `memory_mib` as the combined container/machine memory limit. This supports the existing shared-kernel reader design; it does not establish a live host's enrollment, identity, unchanged procfs view, dynamic capacity or collection cost. The source's fixed authenticated guest reader must still prove the global procfs view, exact owned target/image/UID and kernel boot, and independently obtain the current configured cap under the reviewed runtime profile. No TUI output or undocumented JSON format is promoted into admission authority.

Next source integration is a root-reviewed resource policy bound to the existing opaque installed-runtime identity, exact reviewed architecture/version and immutable approved metadata images. A decoded document must remain metadata; only fixed-installed-manager/root-policy verification can construct the collector. Resource observation grants no MLX coverage, model/native lease or ordinary task execution. Public development startup and absent/invalid profiles remain unknown/disabled. Native installation, actual host-profile enrollment and combined collector acceptance remain separately gated. The finite bootstrap's ownership/lease/one-use/no-replay boundaries must be preserved; do not turn it into a recurring telemetry service or let task/model input select a probe command/image.

### Startup enrollment and actor-side load ownership

The serving registry now receives the request tracker before the startup responder and `Scheduler.init`, so startup loads no longer precede that enrollment. The association is retained on initialization failure/teardown; detaching it is not a way to refund uncertain ownership. Each actual `doLoadOnInferenceThread` call now reserves a preparation owner before its backend branches and installs that owner as thread-local context for the call. Queued loads carry their original connection-side preparation token, preserving its primary/auxiliary scope and correlation lineage across the thread hop. Startup uses an independent internal preparation root.

A pre-pause queued load may continue through its validated parent; a new unparented load is refused. The actor helper restores the previous thread-local context on return and drops only its own reference. A retained reference can keep the actor's original request lineage after the parent/connection has left. Real native root tests exercise this helper with no backend/model call; exact guard bypass fails at its runtime marker. Source ordering checks separately pin enrollment before initialization and guard placement before backend load branches. These are synchronous preparation/reference/wiring receipts, not proof of every backend's asynchronous retention or device terminality. Main-process pre-serve preparation, background/raw backend/cache paths, complete modalities and installed native acceptance remain open; G2/T002/T018/T019/T020/T022 are not completed by this increment.

### Vision and embedding actor context

Vision and embedding requests now capture their originating token before queue handoff. Both actor handlers reserve and activate a child scope before inspecting an encoder/transformer or running backend code. An enrolled handler without a parent refuses work; untracked non-serving callers retain their previous behavior. The scope restores the prior actor context and releases only its own reference after local cleanup, including error paths that notify the waiting caller before all defers finish. The retained scope does not depend on the caller's stack request remaining alive after notification.

Native root tests cover active child accounting, missing-parent refusal, an actual vision handler's no-encoder error path and conflicting vision/embedding requests rejected before backend access. They do not invoke model computation. Source checks separately pin capture before enqueue and actor scope before backend access. Removing the active transition fails its precise native runtime assertion. Generation/merged-batch attribution, complete asynchronous/backend/cache retention and device terminality remain separate unfinished work; this does not close G2 or T018/T019/T020/T022.

### Generation and merged callback origins

Generation senders now establish active scoped ownership before posting and hand that token to the actor. The actor validates and retains the entire bounded set of distinct origins before resource/backend work; a failed set refuses the callbacks and notifies waiting callers. The existing native merge callback remains available. Batch thread-local context represents every origin, and retained callbacks keep the whole set rather than the first request. Auxiliary binding likewise applies to every origin. Nested load/encoder scopes temporarily install their own context and restore the original batch afterward.

The retained set has a fixed capacity256, deduplicates repeated tokens and validates every token/reference limit under one tracker transaction before incrementing any reference. No allocator/I/O/callback runs under that lock. Native root cases exercise actual callback merge dispatch with no model computation, nested context restoration and retained ownership after connection references leave. Source wiring and the exact single-origin omission are checked separately. This is ownership/context infrastructure, not proof that every asynchronous backend/library operation captures it or that device work has completed; G2 and complete modality/backend/terminal acceptance remain open.

### Text actor context (partial source checkpoint)

Prefill and decode entry points install the union of retained slot origins before backend/resource work. Nested/interleaved passes restore the previous context; duplicate tokens coalesce, while missing/foreign owners, contradictory identities and overflow refuse entry. Retention validates the complete bounded token set before acquiring references. Metadata-only native tests exercise the context and missing-owner entry points; a deliberate second-origin omission fails its exact runtime assertion. This does not show that every asynchronous backend/cache/destructor path captures context or that device work has terminated. G2 and T022 remain open; no installed activation or native admission capability is issued.


### Llama uncertainty and actor retirement (partial source checkpoint)

The existing C++ context synchronization/MTP retirement failures now publish a
sticky noninitializing module getter to the native admission guard. Known
backend uncertainty also retains the original serving frame independently of
local reference retirement. Llama-bearing prefill/decode scopes preserve their
original tracker references in quarantine when that fixed getter is positive;
healthy retirement releases them. Model metadata is inspected only after all
actor owners are retained, keeping missing-owner refusal before resource access.

Genuine shim empty-metadata cases and actual scheduler/tracker policy cases
are separate evidence: the former establishes the negative getter's ordinary
refusal persistence, the latter reproduces old root loss and verifies original
reference retention/TLS restoration and real entry refusal. Neither exercises
a loaded Llama synchronization error or establishes all-client/backend/device
terminal coverage. The partial wire frame keeps its three declared sources.
G2/T002/T021/T022 and installed activation remain open.


The same scoped retirement now consumes the existing DS4 host/Metal negative
flags when actual model metadata names a DS4 engine. Cold genuine getters and
the unchanged original-reference retirement policy pass the selected native
case; actual entry reads stay after complete owner retention. C/Metal
participants and partial wire coverage are unchanged. Neither a cold zero nor
a successful core MLX regression is loaded DS4 completion/Studio acceptance;
G2 and full backend ownership remain open.


### Preparation retirement under known uncertainty (partial source checkpoint)

Load/encoder preparation now retains its exact correlated child when the
existing startup-enrolled backend probe reports independent uncertainty.
The query latches the tracker fence and runs its fixed native getter outside
the tracker lock; ordinary leave/snapshot remain callback-free. Native SDK
owner-module uncertainty joins the existing source-negative predicate. False
or missing probe evidence never provides terminal authority.

The actual metadata preparation scope reproduces prior owner/lineage loss and
then retains the original parent root under known-negative policy input.
Healthy local release leaves missing lineage explicitly unknown. These are
policy/reference cases without a loaded backend; asynchronous ownership and
device-terminal coverage/G2/installed activation remain unfinished.


All retained actors now consult their original tracker's enrolled negative
probe before retirement, covering media/MLX actors without Llama/DS4 kind bits.
The actual finish path reproduces prior original-root/lineage loss and retains
those references under known-negative metadata input. The immutable production
probe supplies native SDK/MIMO/other source fences; it is not model input.
Healthy local release stays separate from device completion, and late errors/
full asynchronous/native terminal/G2 acceptance remain unfinished.


### Nested merged-origin capture (partial source checkpoint)

A synchronous preparation with its actual current explicit parent now retains
the stable outer merged TLS group during native SDK metadata capture. The
scalar preparation child still spans CPU work; unrelated explicit parents do
not inherit the group. The genuine native capture API reproduces prior
first-only retention and, after the fix, preserves both original lineages even
after outer client/actor references retire. Capture deep-copies tokens; no new
borrowed-storage lifetime or native authority is introduced. The metadata case
creates no backend/model/GPU handle. Queued/other ancestry and full native/G2
acceptance remain incomplete.


### Queued merged-origin capture (partial source checkpoint)

Cold `ensureLoaded` now retains its complete caller group before registry
mutation, lends stable immutable storage through its uncancelable completion
wait and supplies it to the actual inference-thread load preparation. The
worker validates source/count/live tokens/phase/exact target membership before
installing group context. SDK capture independently copies/retains every root;
known backend uncertainty quarantines sender references after local completion.
The actual worker/native metadata case reproduces scalar loss, then passes with
both roots retained after caller retirement. No backend/model handle is used;
all ANE/other queue paths, native terminality and G2 remain unfinished. This adds
no wire-selected identity, installed capability or lifecycle authority.


### ANE worker and cold-build ownership (partial source checkpoint)

The separate cold-build wrapper now installs validated queued preparation and
retires it before publishing ready/failure. `runAneSlot` enters the existing
retained-owner context before cancellation/backend access and holds it through
error handling/checkpoint; its original enrolled negative source governs
retirement. Actual missing-owner entry fails first and the fixed selected
metadata cases pass4/4, with full executable/link success. These use no loaded
ANE model or runtime handle. CoreML/private completion, compile/lane workers,
full preflight/eviction and G2 remain unfinished; no all-client or lifecycle
authority follows.


### Cold preflight and explicit negative-source capture (partial source checkpoint)

The actual queued cold-load scope now precedes victim eviction, ANE admission
and wired-policy work. Its fixed ready/ANE disposition is published only after
scope retirement, before completion wake or ANE spawning can release borrowed
sender storage. The unchanged ready/loading/backend order remains intact.

Explicit ingress-v2/v3, primary/lineage and HTTP native diagnostic captures now
query the original startup-enrolled negative before final snapshot/timestamp.
Ordinary accounting snapshots/release stay callback-free. A native owner probe
refuses known uncertainty, request owners and retained model-change tickets
before its fixed barrier; final publication rechecks retained work, including
a ticket acquired during the barrier. This is partial stream observation,
never normalized all-client or terminal/admission authority.

Actual missing-negative and premature-barrier cases fail first. Three selected
protocol cases pass Debug/ReleaseSafe; full native build and a bounded headless
core-only exact Gemma cold-load POST pass. The original journal claim remains
uncertain after both processes reap. Whole G2, native all-client/backend/modalities
and installed Studio acceptance remain open; no resident/GPU-idle claim follows.


### Cached source uncertainty and conditional retirement (partial source checkpoint)

Native retirement now retains an already-latched source fence even when its
live enrolled getter is false. Actor/preparation/group reference release
validates the entire token set and checks that fence under the same tracker
lock; ordinary local CPU release stays callback-free and supplies no completion
proof. The native serving frame independently retains cached source uncertainty
when local owner count reaches0. The actual four-case metadata suite and full
native build pass, including an independently scheduled fence before retirement.

Actual model-free unfinished-GET shutdown now holds its original frame after
31.63s and continues holding after the original connection retires to0 local
owners. Finite private-fixture cleanup uses verified PID/UID/start identity and
explicit SIGKILL/reap, retaining unknown coverage/unproven terminality. That is
no installed force/stop authority or native completion receipt. Earlier graceful
exit-after-local-close results belong to their earlier source artifacts. G2
and complete native/Studio lifecycle acceptance remain unfinished.


### Exact error-target binding (partial source checkpoint)

Native error-name lookup now acquires the registry mutex before reading the
empty/marketing default. Both request and explicit-load failure paths reuse
the exact target already passed to loading, so a later default change cannot
redirect their diagnostic lookup. The existing model-free error-state case now
covers explicit original IDs and ordinary aliases after a default switch;
3/3 selected tests and full native build pass. No concurrent native failure,
model computation or all-client/native admission proof is claimed. G2 remains
open and earlier lifecycle/inference receipts retain their original artifacts.

### Serving MiMo warm-worker cleanup scope

The prior reviewed retirement patch enables the one-second original-worker
join only when fixture controls are selected. Actual `gpu_warm.install`
construction leaves that option off and therefore uses an unbounded join.
The separate cumulative `mlx-stream-fcb4011-serving-join.patch` adds a bounded
cleanup option used by the serving constructor. It shares the existing exact
worker join/retain/closed-rearm path while leaving fixture pause and lifetime
ticket APIs disabled. This is source-level cleanup containment only: shared
source uncertainty remains sticky after late original-worker cleanup, per-arm
request-origin attribution remains unfinished, and unrelated native backend
synchronization/all-client admission contracts remain open. Previous reviewed
patches and artifacts retain their own identities and results.

### MiMo warm request origins

The separate cumulative `mlx-stream-fcb4011-request-origins.patch` composes
bounded serving cleanup with a compiled native request-owner bridge exported
by the serving root. Hosts without that declaration retain their prior
component behavior and gain no ownership claim. Native `arm`/positive `hold`
capture and merge immutable original contexts under the engine metadata lock;
only actual native-created descriptors are accepted. Each committed chunk
gets its own copied context and temporary worker TLS scope, with at most two
in-flight chunks. The complete pending union remains bounded by the existing
256-token/4096-context native limits. Missing/failed/overflowed capture fences
source uncertainty before more submission. Callback cleanup uses cached-fence
conditional retirement, with no backend probe under the metadata lock.

The worker drains its final idle chunks before releasing the pending union,
so healthy completed requests do not wait for model destruction. Failed
retirement/TLS/capture and bounded join uncertainty preserve original contexts
and lineages after late local cleanup. Component fixtures prove this finite
private warm-queue scope only; all-client coverage, other MiMo background
lanes, complete device/context terminality, Studio model/resource acceptance
and native admission remain unfinished. No installed activation follows.

### DS4 normal request-buffer origins

`ds4-9139e2a-request-origins.patch` is a separate cumulative six-path source
variant. Its optional one-shot pre-initialization callback enrollment copies
the existing native seven-function context interface, rejecting adoption or
in-progress enrollment. Normal request buffer retrieval/compute/blit/event
encoding accumulates the full immutable context union. Normal submission seals
that buffer and its fixed metadata-only completion handler restores native TLS
before conditional context retirement. Abandoned attributed buffers fence and
quarantine; completed private object cleanup cannot erase cached uncertainty.
Empty next-batch placeholders acquire no request context before encoding.

Source defaults remain unenrolled. Explicit private native composition requires
its exact source document, the reviewed source SDK and the compile-only native
build option; the original source variant/receipts remain independently valid.
This does not enroll or certify independent raw keepalive buffers or TP/host
worker handoffs. Real DS4 initialization/normal producer execution and loaded
model/device-context acceptance remain unexecuted. The partial all-client
ceiling remains unknown and installed/native admission remains closed.

### Returned Llama decode errors

The shim now applies its existing creator-bound target+draft terminal primitive
to prefill/decode/MTP verification errors, including metadata failure inside a
decode batch. Refused completion latches the existing context/module fence and
preserves sequence/target/draft state. A failed partial draft cannot trim or
continue target verification until that check succeeds; healthy draft behavior
and the existing known-complete MTP-drop behavior are retained. Null preflight
alone has no context to retire and does not fence. Metadata checks and native
builds are not loaded-backend or all-client/device proof. The core model tree
contains no local GGUF artifact at this checkpoint; no new model is downloaded
or substituted, and loaded Llama acceptance remains open.

Source audit also confirms the ordinary DS4 CPU row-pool coordinator waits
for every worker callback before returning, including inline/nested work. Its
retained outer caller scope covers that synchronous lifetime; this is static
source analysis, not new host/model acceptance. TP exchange and independent
keepalive/provider contracts remain separately unfinished; no routing/RDMA or
new worker architecture is introduced by that observation.
