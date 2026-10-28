# Native private ingress control — development transport

Status: source-fixture integration only; **not enrolled production control, all-client coverage or quiescence authority**. Installed MLX-Serve is unchanged. No public/LAN management listener is introduced.

## Activation and identity

The pinned source candidate enables the transport only when its build version ends in `-fios-source-fixture` and trusted launcher environment `FIOS_NATIVE_CONTROL` is exactly `isolated-source-fixture`. This value is an opt-in marker, not a credential. Other supplied values/builds refuse initialization. With no marker, no private directory/socket/thread is created. The candidate runs non-root.

The fixed endpoint is `$HOME/.fios-native-control/control.sock`, never a model/request-selected path. The containing leaf must be an actual directory owned by the native service UID with mode0700; socket mode is0600. Existing socket/files are never unlinked or adopted. The transport checks kernel `getpeereid` against the native service UID; this is the local trusted-operator boundary, not a defense against compromised arbitrary host execution as that UID. Generated sandbox code has neither this UID nor host mounts; installed private model workers have no host tools or caller-selected connection API. No role string in an HTTP body/stdout/control frame grants permission.

The manager client additionally authenticates the native socket's UID and kernel peer PID, expected process-start identity, kernel-reported byte-exact executable path and SHA256 of its bounded no-follow opened executable. Start/file identities bracket hashing; a failed check sends no action. Production enrollment must select this peer from reviewed native identity, never operator/model payloads. The ordinary manager entry point supplies no client; the source integration fixture is the only issuer so far.

## Finite binary framing

One request per connection. Client must half-close its write direction. Native waits for EOF before dispatch; truncated, overlong or concatenated frames do not act. Request32 bytes; response64 bytes; deadline2s per native connection; one serialized peer, backlog2. Descriptors are nonblocking/CLOEXEC and writes suppress SIGPIPE. There are no subprocesses, paths, argv, credentials, model IDs, force, signal, launch or stop fields.

Request (big endian integers):

| Offset | Bytes | Meaning |
|---|---:|---|
|0|4|ASCII `FIC9`|
|4|1|version2 (development-only; old version refused)|
|5|1|opcode0 observe,1 pause ingress,2 resume ingress,3 partial MLX owner-stream probe|
|6|2|zero reserved|
|8|8|pause sequence; zero except resume/owner probe, which require the exact current nonzero sequence|
|16|16|native source instance; observe bootstrap may use zero, actions require exact current nonzero instance|

Response:

| Offset | Bytes | Meaning |
|---|---:|---|
|0|4|ASCII `FIR9`|
|4|1|version2|
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

Manager decoding rejects unknown/coerced/inconsistent/bounded-count/padding/length/source identities. Its typed `NativeIngressStatus` is deliberately not `NativeSnapshot`; activity is always unknown. Responses have no complete-coverage/device-terminal field.

## Maintenance and restart

Native pause shares the request reservation mutex, prevents new ingress, and lets existing owners finish. No timeout or manager death reopens admission. Resume requires the exact current source instance and monotonic pause sequence; old/foreign/replayed state cannot reopen the fence or clear uncertainty.

The manager persists explicit operator desired state before emitting native work. An absent desired row is not authority to reopen a fence. One off-loop worker owns at most one connection/result, hashes/authenticates before sending and never retries or falls back. Desired changes during an operation are reconciled against the latest durable intent. Lost outcomes become unknown; subsequent reconciliation observes native truth instead of replaying the uncertain action. A manager restart can recover a native-held pause using authenticated observation. Task/observer sockets cannot change desired service state.

Confirmed closed/open ingress never means native service stopped/running, registry quiet, no external owners, device complete or inference uncertainty cleared. Lifecycle `applied` remains false; native activity and task admission remain unsupported. Ordinary stop/restart still requires an enrolled atomic registry/device-owner reservation and separate scope-bound lifecycle executor. The local operator transport adds no force bypass.

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
