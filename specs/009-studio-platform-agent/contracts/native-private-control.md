# Native private ingress control — development transport

## Manager status scope

`native_ingress_admissions` reports only this coordinator's ingress acknowledgement (`unconfigured`, `unknown`, `observing`, `changingAdmissions`, `admissionsClosed`, `admissionsOpen`). The separate `native_admissions` field remains `unsupported` while no audited atomic native reservation issuer is composed. A fresh authenticated ingress reply, private pause/resume acknowledgement or zero connection count cannot open native model admission, clear independent uncertainty or prove device completion. Earlier private status receipts used `native_admissions` for the ingress phase; those historical labels never provided native authority.


Status: source-fixture integration only; **not enrolled production control, all-client coverage or quiescence authority**. Installed MLX-Serve is unchanged. No public/LAN management listener is introduced.

## Activation and identity

The pinned source candidate enables the transport only when its build version ends in `-fios-source-fixture` and trusted launcher environment `FIOS_NATIVE_CONTROL` is exactly `isolated-source-fixture`. This value is an opt-in marker, not a credential. Other supplied values/builds refuse initialization. With no marker, no private directory/socket/thread is created. The candidate runs non-root.

The fixed endpoint is `$HOME/.fios-native-control/control.sock`, never a model/request-selected path. The containing leaf must be an actual directory owned by the native service UID with mode0700; socket mode is0600. Existing socket/files are never unlinked or adopted. The transport checks kernel `getpeereid` against the native service UID; this is the local trusted-operator boundary, not a defense against compromised arbitrary host execution as that UID. Generated sandbox code has neither this UID nor host mounts; installed private model workers have no host tools or caller-selected connection API. No role string in an HTTP body/stdout/control frame grants permission.

The manager client additionally authenticates the native socket's UID and kernel peer PID, expected process-start identity, kernel-reported byte-exact executable path and SHA256 of its bounded no-follow opened executable. Start/file identities bracket hashing and the reply; a failed pre-send check sends no action. A failed post-reply check leaves any action outcome unknown and does not authorize replay. Production enrollment must select this peer from reviewed native identity, never operator/model payloads. The ordinary manager entry point supplies no client; the source integration fixture is the only issuer so far.

## Finite binary framing

One request per connection. Client must half-close its write direction. Native waits for EOF before dispatch; truncated, overlong or concatenated frames do not act. Action request32 bytes; version2 response64 bytes or opt-in version3 response80 bytes (the separate readonly lineage extension below uses64/112 bytes); deadline2s per native connection; one serialized peer, backlog2. Descriptors are nonblocking/CLOEXEC and writes suppress SIGPIPE. There are no subprocesses, paths, argv, credentials, model IDs, force, signal, launch or stop fields.

Request (big endian integers):

| Offset | Bytes | Meaning |
|---|---:|---|
|0|4|ASCII `FIC9`|
|4|1|version2 or3 (development-only)|
|5|1|opcode0 observe,1 pause ingress,2 resume ingress,3 partial MLX owner-stream probe|
|6|2|zero reserved|
|8|8|pause sequence; zero except resume/owner probe, which require the exact current nonzero sequence|
|16|16|native source instance; observe bootstrap may use zero, actions require exact current nonzero instance|

Response:

| Offset | Bytes | Meaning |
|---|---:|---|
|0|4|ASCII `FIR9`|
|4|1|echo version2 or3|
|5|1|echo opcode|
|6|1|status0 ok,1 invalid,2 already-maintaining/refused pause,3 wrong instance|
|7|1|zero reserved|
|8|16|current source instance|
|24|8|current pause sequence, or zero when open|
|32|4|owned connection reservations|
|36|4|ingress|
|40|4|preparing|
|44|4|active|
|48|4|responding|
|52|4|tracked model identity count (not resident model count)|
|56|1|admissions closed, strict0/1|
|57|1|uncertainty fence, strict0/1|
|58|1|owner-stream outcome0 not requested,1 MLX owner streams synchronized (partial only),2 blocked,3 wrong owner thread,4 stream set changed,5 unsupported/failed,6 timed out|
|59|1|zero reserved|
|60|4|synchronized MLX streams,0–256; zero unless outcome1|

Version3 appends source capture metadata to the same64-byte base reply:

| Offset | Bytes | Meaning |
|---|---:|---|
|64|8|native tracker capture sequence, independent of request/pause sequence|
|72|8|source capture start time, Unix UTC milliseconds; `UINT64_MAX` means unavailable|

The source reads its real clock immediately before taking the final coherent tracker snapshot. Serialization and receipt do not refresh that time. The existing native client defaults to version2 for compatibility; trusted source fixtures may explicitly select version3. There is no protocol fallback/retry. Activity export forwards the actual source instance/sequence/time only while the received metadata remains current, with coverage still unknown.

Manager decoding rejects unknown/coerced/inconsistent/bounded-count/padding/length/source identities. Its typed `NativeIngressStatus` is deliberately not `NativeSnapshot`; activity is always unknown. Responses have no complete-coverage/device-terminal field.

## Maintenance and restart

Native pause shares the request reservation mutex, prevents new ingress, and lets existing owners finish. No timeout or manager death reopens admission. Resume requires the exact current source instance and monotonic pause sequence; old/foreign/replayed state cannot reopen the fence or clear uncertainty.

The manager persists explicit operator desired state before emitting native work. An absent desired row is not authority to reopen a fence. One off-loop worker owns at most one connection/result, hashes/authenticates before sending and never retries or falls back. Desired changes during an operation are reconciled against the latest durable intent. Lost outcomes become unknown; subsequent reconciliation observes native truth instead of replaying the uncertain action. A manager restart can recover a native-held pause using authenticated observation. Task/observer sockets cannot change desired service state.

With an explicitly configured native client, the existing2s manager cycle now schedules opcode0 observations when the single command/result slot is free. Periodic reads do not write desired state, pause/resume ingress or replay previous control intent; no client means no reads. Fresh reads retain the previous accepted diagnostic only under its original source/receipt clocks while the new reply is pending. Failure remains unavailable, and expiration still omits values. Explicit operator reconciliation arriving during a pending read takes over that same observation before any action; it does not open another connection or drop the intent. Matching acknowledged admission state can remain diagnostic for the same source instance; a changed source/state returns it to unknown without acting. This is not a retry of an uncertain action or native lifecycle authority.

Confirmed closed/open ingress never means native service stopped/running, registry quiet, no external owners, device complete or inference uncertainty cleared. Lifecycle `applied` remains false; activity is unknown for a configured adapter and unsupported when unconfigured, and task admission remains disabled. Ordinary stop/restart still requires an enrolled atomic registry/device-owner reservation and separate scope-bound lifecycle executor. The local operator transport adds no force bypass.

## Partial device-owner primitive

Opcode3 is source-fixture-only engineering, not a quiescence/lifecycle opcode. It queues one heap-owned request on the actual native inference thread whose kernel thread ID is captured before startup loading. The sender waits at most1.5s; timeout retains the scheduler reference and occupied slot until actual completion/shutdown, never resubmits or releases backend work. Existing owners, queued/offloaded work, ANE builds, registry loading/eviction/references, changed pause/source and uncertainty block the probe. No queue/registry/tracker mutex spans backend synchronization. Quiet state/references and bounded `fios_probe_epoch` are checked under the registry mutex before and after synchronization; changed epoch, borrows or sticky epoch exhaustion discard the partial result. Upstream UI generation missed complete borrow/release ABA (reproduced actual-root4/5 red); the independent partial epoch advances on reviewed canonical/stub/default and production borrow/release paths, never wraps. This is not every backend/metadata transition or an atomic reservation; actual native-root5/5 and refreshed genuine linked/live fixture pass (`/tmp/fios-009-registry-borrow-aba-green.log`).

After those logical/registry preconditions pass, a source-instance/pause-sequence-bound **scheduler-only actor hold** parks the inference loop after the partial probe, including later housekeeping and queued transitions. Failed/default-unavailable synchronization and sender timeout do not refund this hold. Foreign/older snapshots cannot release or rebind it. Only this same tracker's open state or a newer pause (possible only after exact resume) releases it. The no-hold path reads no tracker mutex. This is not an atomic registry/backend reservation: other actors, context/stream retirement and all backend terminal receipts still require independent coverage. Ordinary manager composition does not issue opcode3 or gain lifecycle authority.

The genuine MLX C++ helper verifies the actual owner thread and, before synchronizing anything, requires every enumerated stream to have a genuinely recorded creation owner. It validates the current thread's local set against that record and synchronizes ONLY that owner—not foreign registered streams. Creation has bounded reservations/non-reusable owner tags and a monotonic epoch; pending/unregistered/changed sets fail closed, without holding metadata locks across backend calls. Other live/retired owners remain unresolved; no aggregate terminal receipt is produced. It never adopts an arbitrary stream ID: public enumeration and caller-thread identity cannot prove ownership of foreign/global thread-unsafe encoders. Explicit genuine CPU creation and a source-fixture-only CPU/GPU default initializer are implemented. Under the same nonroot marker/build-suffix gate, the inference thread creates and records both defaults before startup work only when neither already exists. Preexisting/assigned defaults are never adopted. Additional model/foreign/backend streams remain unsupported unless separately enrolled; arrays, kernels and model completion are not exercised. For the current explicitly owned subset it synchronizes each stream (not just an observer/default stream), bounds the count and rejects a changed set or any exception. Other threads' encoders, embedded/ANE/non-MLX engines, background work and atomic registry/device epochs still need independent terminal proofs. Even outcome1 is ONLY a partial MLX observation; it never normalizes to complete coverage/native idle, clears an inference lease or enables lifecycle. The ordinary manager/coordinator does not issue opcode3.

## Evidence

- Latest `/tmp/fios-009-actor-hold-source-green.log`/`.status` and `/tmp/fios-009-actor-hold-linked.log`/`.status` exit0: Debug/ReleaseSafe actor-hold/refusal vectors, exact9-path source/Sema, actual native-root6/6 including failed/default-unavailable scheduler probe parking after sender timeout, genuine CPU/default/real mlx-c/two-owner checks and live private control/HTTP/Swift/manager recovery. Partial inference-owner synchronization remains2 explicit defaults with unknown global activity. Separate disabled-hold optimized witness fails as intended; initial obsolete-array-syntax harness errors are NOT failing-first behavioral evidence. Disposable artifact `6d86a4fe43fd065ba00c8e55fbc6f06266d49d8f65a44c31c3f0d0a58e301900` removed; installed hashes unchanged, no model/arrays/inference kernels or all-backend/atomic terminal authority.
- Prior `/tmp/fios-009-registry-borrow-aba-{red,green}.log`/`.status`: actual borrow/release-ABA regression4/5 red→5/5 green with bounded epoch, stub/default and sticky exhaustion guards; genuine library/MLX owner/default/two-owner and HTTP/control/Swift/manager restart pass. Artifact `f397571c2e6c53588e63c072c3c3d5062c8286919cc274c782828a77cae774c5` deleted; installed runtime hashes unchanged. Source characterization of the exact four production refcount mutations passes separately; no complete coverage or lifecycle authority.
- Prior `/tmp/fios-009-registry-generation-green.log`/`.status` exit0: actual native-root5/5 including registry state-ABA/borrow guards, genuine owner/default/two-owner checks and HTTP/control/Swift/manager restart. Native owner synchronizes2 explicit defaults; global activity stays unknown. Artifact `dc8f541b22f20438782c7560c24a9cb8f4431bf09af6b3844232291cabb1ec06` deleted; installed runtime hashes unchanged, no model/array/inference kernel or terminal authority.
- Prior multi-owner `/tmp/fios-009-multi-owner-linked.log`/`.status` exit0: genuine two-CPU-owner checks synchronize only each owner's1 stream, assigned-global-default refusal/negative witness, actual native-root5/5 and live HTTP/control/Swift/manager restart. Native inference owner still synchronizes2 CPU/GPU defaults; global activity stays unknown. Artifact `ead9d0c98ccac73bb6d17700ffa6c24d440ae2fb8073a83c2c8f945b88a92ffc` deleted; no model/inference kernels or aggregate terminal claim.
- Prior `/tmp/fios-009-owned-defaults-linked.log`/`.status` exit0: actual inference-thread probe explicitly creates/synchronizes CPU+GPU default streams (`outcome1`, `streams2`) in an empty-model source process, actual native-root5/5 and HTTP/private control/Swift/manager restart pass. No arrays, weights or inference kernels. Artifact `e55fd8b3d9d1366a27753e1e3f8cf5cf7f4f3ce9dba2d40e793a3fd89eb2bde2` deleted with disposable output; global activity stays unknown. Separate always-enabled `/tmp/fios-009-owned-default-refusal.log` confirms assigned global CPU defaults are refused, never adopted/synchronized.
- Previous `/tmp/fios-009-explicit-owner-linked.log`/`.status` exit0: always-enabled genuine owned CPU/empty/wrong-thread/unregistered/global-stream checks and deliberate exit77 witness; actual native-root5/5, live HTTP/private control/Swift/manager restart. Live native inference-thread probe is partial outcome1/0 streams with unknown global activity. Disposable artifact `68c2c31c7c3fbd0a7b1f32be8657197bcda182b3d75713efdceb78bb5605f0d4`; no GPU/model inference or terminal authority.
-14 Debug/ReleaseSafe ownership tests plus finite protocol tests.
- Strict Swift codec, bounded off-loop queue, durable maintenance/restart/lost-outcome tests; debug/optimized suites pass.
- Actual linked source fixture: native TCP partial ingress remains owned while private pause closes new ingress; private observation continues; resume and ticket replay are exercised.
- Actual Swift client checks expected native PID/start/path/hash; wrong hash cannot pause.
- Actual isolated manager with its own FIS9 journal: task-role refusal, async pause, maintenance surviving manager termination/restart, explicit resume; still unsupported native activity and `applied:false`.
- Earlier checkpoint `/tmp/fios-009-device-owner-linked-green.log`: actual root5/5, including retained one-slot probe on timeout/late completion; genuine C++/MLX CPU/empty-stream and wrong-thread test; live native-owner probe, ingress refusal, Swift unknown-only decoding and HTTP/control/manager integration. CPU/empty-stream is not GPU/model acceptance. Earlier standalone C++ `assert` checks were disabled by Zig's optimized `NDEBUG` default and are not accepted CPU-sync/wrong-thread evidence. New always-enabled owned/unregistered/global-stream checks and deliberate exit77 witness pass in `/tmp/fios-009-owned-stream-{green,negative}.log`; the linked fixture now enforces `-UNDEBUG`/a compile-time guard and verifies the negative witness. The reviewed patch now also adds the genuine C++ source to executable/test macOS build roots without removing upstream staging guards. Artifact is deleted with disposable output; no installed application or production database is changed.

Outstanding: production release/profile/issuer enrollment, broader peer/recovery/drain scenarios, all enabled backend/device terminal ownership, atomic native registry/quiescence reservation, protected service execution and operational acceptance.

## Readonly per-request lineage frame

A separate `FIQ9`/`FIP9` version1 namespace reads an opaque request ID's live ownership lineage. It cannot pause/resume admissions, invoke the partial owner-stream barrier, manage a service or resolve a journal record. The32-byte version2 action protocol above remains unchanged. The common transport accepts exactly one32-byte action or64-byte query followed by write-half-close, with the same UID, deadline and serialization bounds. A64-byte concatenation of old action frames is rejected, never treated as a query; overlong/truncated inputs do not act.

Query64 bytes:

| Offset | Bytes | Meaning |
|---|---:|---|
|0|4|ASCII `FIQ9`|
|4|1|version1|
|5–7|3|zero; no selectable operation|
|8|16|expected native source instance|
|24|32|opaque request correlation digest|
|56|8|reserved zero|

Reply112 bytes:

| Offset | Bytes | Meaning |
|---|---:|---|
|0|4|ASCII `FIP9`|
|4|1|version1|
|5|1|status:0 ok,1 invalid,3 wrong instance|
|6|1|found live lineage,0 or1|
|7|1|uncertain,0 or1|
|8|16|native source instance|
|24|32|exact correlation digest echo|
|56|8|shared native capture sequence|
|64|8|original ingress root sequence|
|72|8|sum of retained references|
|80|20|five u32 counts: owners, ingress, preparing, active, responding|
|100|12|reserved zero|

All integers are big endian. Root sequence is a full-width native token; do not serialize it as a JSON number. Capture sequence is bounded by the existing exact JSON-safe counter, but remains binary here. Root identity follows retained preparation descendants even after their original connection owner leaves. A sole live ingress may associate an ID; later reuse has a different root sequence. The header/hash derivation is defined in [model-access.md](model-access.md).

The Swift client verifies the same kernel PID/start/path/FD hash before sending and after receiving, within the original2s exchange deadline. It validates exact source/digest echo, reserved bytes, counter range, phase totals, references and root width. A found lineage has1..256 owners, a nonzero root and references between owners and owners×UInt32.max. Missing lineage requires uncertain=true, zero root/references/counts. Invalid/wrong-source replies throw; they never become absence. The sample retains the authenticated peer and the original pre-query wall timestamp; a clock rollback or age beyond5s refuses publication. Source collectors must call off-loop; kernel/filesystem calls themselves are not preempted by the elapsed checks.

This is request-lineage observation, not a terminal receipt, non-dispatch proof, all-client coverage, global idle, device completion or an admission lease. Missing/reused IDs, a reaped client, cancellation and a newer success do not clear old uncertainty. The public manager has no native enrollment issuer or journal-reconciliation hook for this result. The volatile consumer checks described below do not supply durable root binding or authoritative terminal/quiescence reconciliation; T021 and G2 stay open.

### Per-request volatile consumer

`NativeRequestLineageConsumer` derives the expected digest from the original durable inference scope/job/attempt and pins its native epoch plus the enrolled peer PID/start/path/SHA. It independently revalidates typed samples, requires strictly increasing accepted capture sequence and nonregressing original collection time, and applies5s age/1s future limits. A failed/unavailable query and a missing lineage return only `unknown`. They retain the last accepted counter and first observed native root; they do not reset replay state or allow a later ingress to replace the original request. Even an uncertain found sample retains its root conservatively.

Changing native instance, peer PID/start/path/SHA, request digest or a previously observed root permanently fences this consumer. A local wall-clock rollback also fences it; there is no reset/cleanup method. Stale/replayed/malformed samples remain unknown and cannot advance accepted state. A fresh coherent present lineage may return `live`, which is metadata about retained owners, never completion or admission authority.

The view is volatile and has no journal mutation or terminal/absent/not-sent state. It must not be used as a durable receipt, and reconstruction after manager restart must not forgive unresolved journal ownership or substitute a newly observed root for historical evidence. Durable root/proof correlation, process-generation completion authority, off-loop manager composition and positive terminal/quiescence receipts remain unfinished.

## Managed model POST instance binding

The native process instance reported by this control boundary can be carried as `X-Fios-Native-Instance` on the private worker's single model POST. Source format1 validates the optional expected instance before associating the opaque request correlation ID or acquiring/dispatching model work. Mismatch returns static409 `native_instance_changed`. Bound local-target format1 additionally requires an explicit exact registered local model ID (unloaded entries remain eligible for ordinary on-demand loading). Provider/LAN proxy targets return409 `native_target_not_local`; empty/default, reserved marketing name, mutable aliases and unregistered IDs return404 `native_target_not_found`. Header-absent legacy resolution remains unchanged. The expected value cannot replace the source's own instance, authenticate a caller, grant admission or prove idle/terminal work. The reviewed source capsule declares `native_expected_instance_guard_version:1` as a source-format prerequisite only; the actual empty-model restart fixture independently exercises its behavior. Unsupported older capsules refuse the journal-model scenario before model effects.

The capsule declares `native_bound_local_target_guard_version:1` as a source-format prerequisite, independently of runtime evidence. Journal-correlation requires the instance, exact-local and decoded-JSON format markers. A provider-enabled `--provider-source-fixture` build is allowed only with `--functional-build-only`; its receipt declares `provider_source_fixture:true` and `mas_build:false`, and model-review planning refuses it. The ordinary build retains `mas_build:true`. The local-dispatch fixture uses only an owned static mock provider, private loopback endpoints, empty model storage and an endpoint-restricted sandbox; it proves dispatch behavior without real inference or installed authority.

Bound JSON target format1 (`native_bound_target_json_version:1`) reads only the decoded top-level JSON `model` string, retains the parsed allocation through response handling and enforces the existing1024-byte model identity limit. Nested metadata cannot select the target; valid JSON escapes select the same identifier. Non-object/non-string or duplicate-field JSON returns400 `invalid_request_error`; an absent or unregistered target remains404. This format marker does not establish native admission authority.


## Optional tracked MLX component hold in the private source probe

The explicit atomic-component SDK candidate can register immutable compiled
acquire/release hooks before backend startup. Other SDK variants keep the
existing bridge-only behavior. No wire packet, model output or installed
configuration can register/replace these hooks.

The native owner probe first synchronizes its original bridge-owned streams,
then seals the already-tracked MLX stream-creation, host-queue and Metal-buffer
components. Sealing earlier would prevent synchronization from enqueueing its
own completion work. The original bridge token retains the additional source
ticket and release hooks. Explicit same-creator bridge release preflights its
irreversible epoch before releasing source gates, and clears neither record
until positive source release. Refused/repeated probes and foreign/stale release
retain the original gates. No timeout, age or local process reap releases them.

This remains partial source exclusion. It does not cover model/context/MIMO/
DS4/distributed participants, issue all-client/native terminality, clear native
uncertainty or activate installed lifecycle. The source-component metadata
retains coverage unknown/authority false. Existing binary protocol and its
partial owner-stream result are unchanged. The enclosing builder enables this
composition only for the verified cumulative atomic-component source patch;
older SDKs do not silently substitute an implementation.


## Readonly backend fence envelope

The existing local authenticated `/v1/fios/source-components` source observation
uses JSON component envelope3. Its exact fields are `schema_version`, `scope`,
`coverage`, `authority`, `mlx`, `mimo_warm_uncertain` and
`ds4_metal_uncertainty`. Scope is `independent_partial_backend_fences`, coverage
is `unknown` and authority is false. `mlx` retains the previous schema1/2
subdomain without changing its availability semantics. MIMO is a boolean or
null when unavailable; DS4 is a mask0..31 or null when unavailable. Null never
means false/zero. The mask maps pending buffer1, TP service2, TP GPU4,
ordinary keepalive8 and pread16. Loads are independent, not a coherent combined
backend snapshot. False/zero cannot establish idle, native completion or
admission authority. Envelope3 does not change private control protocol2/3.

The finite model-free backend-fence fixture correlates the HTTP source instance
with the original private control channel, checks increasing source sequence
and leaves the model catalog empty. It performs no control action. This is
source observation evidence, not installed process enrollment or all-client
coverage.


Envelope4 adds exactly `ds4_host_uncertainty` to envelope3, preserving the
existing MLX, MIMO and DS4 Metal fields. Host masks0..7 map CPU pool1,
page-in2 and selected-loader shutdown4; null means unavailable. Envelopes3
and4 have distinct exact schemas, so an older response never invents a host
observation. Host flags are independent atomic sticky loads, without mutexes,
initialization, joins, cleanup or reset. DS4_NO_GPU source builds omit GPU-only
host worker flags; absence/zero never establishes complete coverage. The
server's host field is available only for its enabled macOS DS4 build.


The opted-in MIMO warm-engine cleanup preflight now refuses metadata contention
with pthread_mutex_trylock in both fiosCanDestroy and tryDestroy. Refusal
leaves the engine/backend, quit state and independent source uncertainty
unchanged. A positive destruction path publishes quit/wake under the existing
lock rather than reacquiring it to signal. This only bounds the metadata
preflight; its subsequent actual worker/backend join is still a separate
unbounded retirement issue, not an all-client/device lifecycle reservation.
The normal unopted serving path is unchanged.


The subsequent opted-in MIMO retirement candidate retains at most one join
helper for each original warm worker. The helper checks the actual pthread_join
result and publishes it as its last engine access. The caller observes that
result for at most one monotonic second without holding metadata locks. A
timeout/clock failure/helper failure keeps the engine/backend and records sticky
source uncertainty; it does not cancel the worker, create another join or free
its context. Stop closes the local warm gate before waiting. Pending/failed
join state refuses fiosCanDestroy even with no lifetime ticket. A later explicit
original-owner cleanup may finish after a positive original-worker join; the
process source fence remains true. Failed detach retains its helper handle and
refuses cleanup. This is local warm-worker retirement only; unopted serving
behavior is unchanged, and no all-client/device terminal authority follows.


## Private readonly backend fences (version1)

An explicitly opted-in source client may query independent backend flags over
its existing UID/kernel-image-authenticated private Unix channel, without the
native serving key. FIC2/FIC3 and HTTP envelope4 remain unchanged. A32-byte
FIB9 request carries version1 at byte4, expected16-byte instance at8..24 and
zero reserved bytes. The64-byte FIF9 reply contains version1/status at4/5,
availability bits MIMO1/DS4 Metal2/DS4 host4 at6, MIMO boolean at7,
instance8..24, big-endian sample sequence24..32, source UTC milliseconds32..40,
Metal mask40..44, host mask44..48 and zero reserved48..64. Unavailable fields
have zero wire values and absent availability bits; unavailable time is UINT64_MAX.
Status0 succeeds,1 is invalid,3 is wrong instance. Masks are bounded31/7.

Source capture advances the source sequence; each reply has its own original
clock. The retained asynchronous observe worker reads ingress first and records
its receipt before querying backend fences. Backend observation cannot refresh
that older ingress receipt. A failed backend query does not replace a valid
ingress result. Both exchanges remain finite, with one retained worker slot and
no retry. Public startup remains unenrolled; this is an internal source opt-in.

Manager diagnostics independently require fresh source/receipt clocks within
5s with at most1s future tolerance, stable peer/source identity and increasing
source sequence. Unknown gaps retain the checkpoint and previously observed
sticky uncertainty; a later lower mask/cleared sticky flag fences the cache.
Missing providers remain null, not false/zero. These flags never enter a native
admission, lifecycle reservation or terminal proof. Coverage remains unknown,
authority false, and false/zero never establishes idle or all-client completion.

## Primary ownership observation (version1, source-only)

A separate readonly FIA9 version1 request uses32 bytes with expected source
instance8..24 and zero reserved5..8/24..32. FIT9 version1 reply is fixed66,624
bytes:64-byte header and64 records of1,040 bytes. Header status is byte5,
reserved6 is zero, uncertainty7 is boolean, instance8..24, original source
sequence24..32, original UTC capture milliseconds32..40, owned/ingress/
preparing/active/responding/model-count UInt32 values at40/44/48/52/56/60.
Unknown clock is UINT64_MAX. Each used record contains UInt16 ID byte-length,
two zero reserved bytes, UInt32 preparing/active/responding at4/8/12 and up to
1,024 exact ID bytes at16; remaining bytes/unused records are zero. Integers
are big-endian. At most256 ownership roots and64 primary model identities are
reported. Auxiliary association stays in the legacy source view.

This is conservative primary ownership attribution, including internal load
preparation roots and retained references, not disjoint HTTP request counts,
residency, execution/device phases or complete all-client coverage. Unbound
ingress has no invented model. Independent source clock/sequence and unknown
coverage remain mandatory; no native action, reservation or terminal proof is
created. The existing private channel authentication, single response and2s
transport deadline apply. FIC2/3, lineage and backend fence frames stay distinct.


The opted-in Swift client validates all primary IDs/phases and retains the
complete typed set internally. Its manager status view reports bounded aggregate
counts and model-identity count, without truncating/exporting the64×1024-byte
identity set into the existing64KiB status envelope. This remains separate from
normalized all-client activity. Original primary capture/receipt clocks and
sequence do not replace ingress metadata. Source gaps retain the original
checkpoint and sticky tracker uncertainty; source/peer/clock rollback or a
cleared sticky flag fences diagnostics. No state here releases journal claims.
The existing single retained observe worker may issue these distinct finite
reads; it creates no retry queue or native action from observations. Public
startup remains unenrolled; both optional diagnostic clients default off.


## Known backend uncertainty at native work edges

Native startup enrolls one fixed nonblocking readonly backend predicate before
any tracked request/model mutation. Primary binding, preparation, auxiliary
binding, execution entry and destructive model mutation consult it outside the
tracker mutex. A positive predicate sets the existing one-way tracker fence and
refuses new work; later false input/local cleanup cannot clear it. The source
predicate currently combines MIMO warm, DS4 Metal and DS4 host uncertainty.
Unavailable/zero flags grant no coverage, admission, capacity or idle proof.
Other backend/context/native contracts remain incomplete.

Snapshot/primary/lineage/backend queries never invoke this admission predicate
or import a fence as a read side effect. Existing response/reference-release
accounting remains possible and never clears uncertainty. This does not cancel
existing work or signal a process. It is a known-negative refusal, not an atomic
all-client/device-terminal reservation or a production authority issuer.

The source MLX composition can also enroll one fixed compiled uncertainty
getter. The SDK mirrors every existing sticky source-uncertainty assignment
into one lock-free atomic boolean; its getter performs no metadata lock,
initialization, backend operation, reset or quiescence probe. The bridge's
once-only getter registration is separate from its renderer and hold hooks.
Without the reviewed source hook it returns unavailable (-1), never healthy
capacity. A positive getter joins the existing negative native work-edge
predicate. Existing partial MLX diagnostics remain the observation surface;
no new private frame or normalized all-client capability is introduced.
False/unavailable results cannot authorize dispatch, replacement or terminality.
Older reviewed source headers omit this optional hook rather than substituting
an SDK declaration. The capsule's native_known_mlx_refusal_version is a declared
source-format marker, not evidence that all backends or installed code enroll.

## Optional native request owners in source MLX host callbacks

The reviewed source SDK can accept one fixed compiled hook tuple to capture,
enter, leave and release native owner contexts. It retains actual native tracker
references before posting host work, enters their immutable bounded owner set
on the actual callback thread and restores that thread's original TLS scope on
return. Nested SDK CPU enqueue inherits the originating set. The descriptor
survives callback cleanup and is released by the SDK's original shared lifetime;
no wire/model-selected pointer, role, code, command or endpoint is accepted.

Native context capacity is4096 fixed-size Retained descriptors, with64 nested
scope frames/thread and non-reused global UInt64 scope IDs. Descriptor payload
is bounded by4096 times its compiled size; allocator/thread overhead is separate,
not a hard process/GPU memory quota. Startup binds the original native IO once.
Hooks never run under the SDK's source-registry/queue mutexes. An absent scope
is unavailable, not evidence of no model work. No context/counter/clock reset,
lease timeout or later successful callback can clear recorded uncertainty.

Failed context capture preserves its already-retained original references;
failed contexts/descriptors remain quarantined. A scope-entry failure uses the
SDK stream's existing error channel. Native drain format3 additionally retains
serving state when the owner-context module has failed, independently of a
subsequent zero local count. This is conservative source failure handling, not
an authorized installed lifecycle/admission issuer or a completion proof.

Private development checkpoints used native_request_host_owners_version1/2;
the published source patch declares version3, including failure retention/stream
error handling and captured-task destruction inside the original scope.
These are source-format markers only. Existing private wire formats, unknown
all-client coverage and independent inference claims remain unchanged. Metal
callbacks/other native actors/backends and complete request terminality remain
separate technical work; host-queue completion never implies device completion.

## Optional native owners in source MLX Metal callbacks

Source format native_request_metal_owners_version1 adds native owner references
to registered Metal capture records and the original commit callback. Capture
happens outside SDK metadata locks. The actual callback takes its original owner
set once, enters/restores native TLS and destroys its actual retained payloads
inside that scope; destructor-enqueued CPU work inherits the same owner set.
Taking the owner set out of the record separates it from any longer Metal block
object lifetime. Capture, scope and cleanup failure remain conservative source
uncertainty, never a positive native or device terminal receipt.

This covers registered source SDK callbacks only, not every operation appended
to a reused buffer, raw/foreign SDK work, all native backends or a complete
native model/instance reservation. Null/unattributed contexts remain unknown.
No source marker, zero callback count, original local release or completed tiny
fixture grants all-client idle, device completion or installed admission.
