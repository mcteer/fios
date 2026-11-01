# Native serving custody across manager restart

This source boundary supports the operator-selected direct agent ownership of
`mlx-serve`. It does not use GUI ownership, adopt a historical PID or introduce
another persistent helper. The existing trusted supervisor is the intended
physical child custodian across manager restarts; the manager retains durable
service intent, native reservation policy and journal ownership. Installation
and public startup wiring remain gated and incomplete.

The current source includes the fixed command/reply codec, custody gate and
local/remote runtime interface. The private Unix server/client and supervisor
composition are still being implemented. No installed custody socket, native
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
