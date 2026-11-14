# Native serving custody across manager restart

This source boundary supports the operator-selected direct agent ownership of
`mlx-serve`. It does not use GUI ownership, adopt a historical PID or introduce
another persistent helper. The existing trusted supervisor is the intended
physical child custodian across manager restarts; the manager retains durable
service intent, native reservation policy and journal ownership. Installation
and public startup wiring remain gated and incomplete.

The current source includes the fixed command/reply codec, custody gate,
local/remote runtime interface and private Unix server/client. Internal supervisor composition is implemented through a code-only factory;
public startup and installed custody acceptance remain gated and incomplete. No installed custody socket, native
process action or supervisor activation follows from these source types.

## Fixed control data

Each command is at most2KiB, strict JSON with exact fields and no duplicate keys.
Version1/purpose `native_serving_custody` binds a canonical operation UUID,
custodian instance UUID, reviewed configuration profile and fixed native image
SHA256. Only six operations exist: `launch`, `lookup_launch`, `cancel_launch`,
`stop`, `lookup_stop`, `cancel_stop`. No packet supplies a role, host, endpoint,
executable path, argv, environment, credential, model policy or force approval.

Only launch/stop have a JSON-safe monotonic deadline in milliseconds; the local
runtime still independently checks its ten-second action window. Every stop
operation also binds the original launch ID, PID, canonical UInt64 kernel start,
boot and reviewed profile/image. A PID alone cannot identify a stop target.
Replies correlate instance/profile/operation/ID and distinguish historical
`started`, positive `not_sent`, local-only `local_exited` and `uncertain` outcomes.
Local exit is never native inference/device terminality.

## Custody and manager generations

Only the existing supervisor's own child tracking may bind a manager kernel
PID/start and the fixed reviewed manager executable. There is no enrollment
packet. The gate independently verifies that kernel peer identity off-loop and
rechecks its manager generation before dispatch. Hashing/IPC cannot run on the
supervisor heartbeat. Dispatch IDs are consumed before entering the runtime;
repeated actions return the original lookup result, never invoke a new action.
The cache is bounded to512 IDs and never ages uncertainty away.

Losing/changing the bound manager seals only work still in read-only validation.
The runtime retains its real validator slot through return. An already dispatched
operation, owned child and immutable result history survive connection/manager
loss. A new manager must reconcile the original durable operation IDs. Missing
custodian history remains unknown; it cannot acknowledge an old stop or unlock a
new launch. The supervisor itself dying still requires independent reconciliation;
a new supervisor may not adopt the orphan by PID or manufacture history.

Stop results and revocation additionally bind the full original launch receipt in
the runtime, including known non-dispatch outcomes. A reused stop ID with a changed
receipt returns unknown and cannot consume the original notification. This remains
separate from native inference claims and durable service acknowledgement.

The production constructor must retain protected configuration, exclusive GUI
handover/start namespace and independent native start/stop reservations. Authenticated
management transport supplies none of those native proofs. Ordinary disruption
still refuses unknown/external activity; no force or fallback operation is added.

## Evidence limits

Codec/gate tests use a genuine current test-process manager identity and synthetic
custody results. They test fixed fields, receipt correlation, once-only dispatch,
manager unbind/rebind and pre-dispatch revocation without any native/service action.
These are not actual supervisor/manager restart, installed enrollment, global
absence, all-client activity or Studio lifecycle acceptance.

The source Unix server has its own fixed private writer lock within the existing
supervisor state directory. It accepts at most16 finite connections, one retained
off-loop identity/action exchange and no unbounded request queue. Framing/flush
remain nonblocking on the supervisor loop. Each direction requires exactly one
frame and EOF; the client verifies the pinned custodian kernel/image identity
before sending and after the response. Socket/identity errors remain unknown.
The local client cannot retire a child or mint non-dispatch; only the custodian's
original owned-child/runtime history may supply those local outcomes. Descriptor
metadata stays historical on teardown and grants no native authority.

A separate finite fixture now exercises genuine Unix peer identities across
actual client-process death and replacement: the parent retains one original
private C child; the replacement restores the durable launch receipt, looks it
up and stops that same child, while the independent uncertain journal count
remains1. It does not execute the actual supervisor loop, installed manager
profile or native MLX server. Those acceptance claims remain separate.

The actual supervisor loop now accepts an internal code-only custody factory
after acquiring its existing singleton. It binds only its tracked manager child,
revokes validation before manager termination and preserves native custody across
manager replacement. A custody IPC failure leaves a sticky degraded state while
retaining the runtime/writer lock; a binding failure retains the already running
manager reference for watchdog control. Public startup passes no factory.

Debug/optimized finite fixtures run that actual supervisor loop and two actual
manager lifetimes around one original C serving child. The replacement restores
the journal, verifies the original launch over Unix RPC and stops the same child.
Both API readiness and native permits remain private-helper fixtures, and the
independent uncertain journal count remains1 after managers stop. This is source
composition evidence, not installed images, production profile/credential/native
lease issuance, whole-supervisor orphan recovery or Studio acceptance.

Protected configuration now distinguishes manager and supervisor entry roles
and pins both images. Only the supervisor-role configuration can construct the
native child runtime. The manager's source-only client factory derives its
expected profile without the serving secret, reads the fixed descriptor and
verifies the actual pinned supervisor. Static descriptor data is neither
current ownership nor native terminality; every exchange still authenticates
the peer, and lifecycle reservations remain independent. Public startup is
still closed, and positive installed-factory acceptance remains open.

Stopped-state backup now holds the fixed supervisor → serving-custody → manager
writer locks for its entire journal/export snapshot. A retained custody module
refuses backup even when the manager is stopped; no controller/custodian may
open while that fence is held. Restore creates fresh empty custody/other writer
locks and does not copy `serving-custody.json`, which is volatile peer metadata,
not a portable capability. These fences do not prove native inference/device
terminality, adopt an orphan, authorize installed updates or clear uncertainty.
Retain independent native reconciliation and reviewed installation/rollback gates.


The supervisor loop observes its original owned child's local exit independently
of manager connections, including after custody IPC degradation. A nonblocking
specific-child reap releases kernel resources only. An uncertain operation keeps
its phase, capacity, immutable result and durable pending record; neither a reap
nor a service acknowledgement clears independent native inference uncertainty.
