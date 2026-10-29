# Installed Studio compatibility — 2026-10-26

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
