# Native MLX server lifecycle

The operator selected direct agent ownership on2026-11-01. This is the target
implementation for FR-003/US3. Opening MLXCore is not server recovery. Source
implementation is incomplete; no installed lifecycle acceptance is claimed.

## Ownership and configuration

The trusted agent owns the exact reviewed native `mlx-serve` child. The existing
supervisor is the intended physical custodian across manager restarts; the manager
retains durable policy and uses fixed authenticated local control. Its internal source
composition is tested, while public enrollment/activation remain incomplete; see [custody contract](native-serving-custody.md). OrbStack
continues to use its supported session lifecycle. Native server ownership does
not require the GUI to remain running; an open GUI is neither server readiness
nor permission to launch. Do not implement lifecycle through GUI scripting,
name/port-based process killing or a general shell command.

Installation must review a single handover from the existing GUI controller:
preserve its exact serving arguments, explicit working directory, listener binding, credential source,
model/cache paths and required framework environment; prevent GUI autostart or
manual GUI lifecycle from racing the agent. The installation plan must explain
the effects and reversal before any installed change. Do not copy raw process
arguments/environment into logs or silently choose CLI defaults. In particular,
the CLI's default listener must not introduce new network exposure. No model,
RDMA, native policy or credential change is implied.

The protected launch profile must bind the approved host/account, executable
and dependency identities, configuration revision and exclusive startup
namespace. Package hashes, a matching PID/path, a GUI exit or a scoped census
absence cannot issue that profile or prove ownership handover complete. Missing
or conflicting ownership leaves lifecycle unavailable and observation unknown.

## Observe and recover

Observe the actual server's kernel PID/start/image identity and independently
probe metadata readiness without inference. Distinguish absent, starting/model
loading, ready, unresponsive and unknown. A live GUI with a dead server must
report server failure. Loading is not a hung server; stale or conflicting
observations cannot trigger recovery. Keep these probes off the heartbeat.

Persist a bounded recovery reservation before dispatch. A start requires running
intent, the reviewed exclusive owner/profile, current namespace reservation,
credentials/session prerequisites where required and no unresolved earlier
launch. Retain the child before spawning; verify its identity after spawn and
verify API readiness separately. Readiness failure does not permit another
server. A manager restart must reconcile the original operation and verified
child; losing an in-memory Process reference cannot authorize another launch.

Restart is a composed operation: close new admission, reconcile/drain affected
work, obtain the identity-bound native lifecycle reservation, stop only the
verified owned instance, observe the required completion, then take a fresh
bounded start reservation and verify readiness. Native activity uncertainty
blocks ordinary disruption even if the child has been locally reaped. An
explicit force operation retains its separate affected-scope confirmation.
Do not use PID-only signals, sampled GPU idle or a successful HTTP health probe
as native terminality. Never adopt or kill an unrelated/manual server.

The source recovery journal's version3 record retains the last correlated
started acknowledgement per fixed service: operation ID, PID, canonical
decimal-string kernel start, image hash and original boot, under the same
reviewed profile. Clear the pending launch and persist this record in one
durable write. Version1 input has no such evidence; reading it cannot invent a
receipt. Version1/2 input cannot invent a pending stop. Reboot, later not-sent replies and manager reconstruction must not
reinterpret historical evidence as current ownership. Live identity, protected
profile/namespace and native lifecycle authority must still be established
before adoption or disruption. The record alone never clears native inference
uncertainty or unlocks another launch.

Stopped-state backup/restore retains the complete recovery file. Older binaries
which cannot read version3 must refuse it; do not remove the file, drop the
receipt or restore older ownership state merely to make a downgrade start.
Installed upgrade/rollback review must retain a compatible known-good binary
and reconcile current work. Development source migration is not permission for
an installed update.

Maintenance prevents recovery; stopped intent is durable intent until the
separate stop completes. Pre-dispatch cancellation seals validation; after
dispatch, timeout and missing history remain uncertain. Preserve the existing
restart budget and durable operation IDs across process/session restarts.

## Acceptance still required

The source owned-child stop primitive is not the installed controller. It
requires a separate retained native lifecycle reservation, whose callback only
revalidates that reservation. Pre-dispatch revocation keeps the real validator
slot until return. After dispatch, errors/timeouts stay uncertain; there is no
force/retry fallback. Identity and deadline are checked at the owned-child
signal edge; local exit is reported separately from native/device completion.
The source controller now persists an original-identity-bound pending stop
before dispatch, with a separate bounded attempt budget. Its one-use intent
has no installed producer. Restoration can only look up or revoke the original
ID; a cold actuator's missing history remains unknown and cannot unblock a new
launch. A failed acknowledgement write retains the pending record. The bridge
is wired into the manager only through internal code-only lifecycle ports
bound to its exact native start runtime. Migration holds disable these ports.
The producer must be nonblocking and consume separately prepared retained
native authority; it cannot do filesystem/hash/IPC work on the heartbeat.
Stopped intent can request a stop; running recovery needs fresh unavailable
health for the exact identity, ready session/credentials and no loading state.
Status reports `stop_pending`, not completed actuation. The public entry point
has no installed producer, so none of this activates installed lifecycle.
Internal supervisor custody now retains the original owned child across manager
death and replacement through fixed authenticated local control. Public installed
composition is still closed. A server surviving the entire supervisor/custodian's
death cannot be adopted into POSIX child custody from a historical PID; that
case still needs separately reviewed identity-bound native reconciliation.
Private helper custody tests supply no installed or native terminal authority.

Source/private-process fixtures must cover exit with GUI alive, no duplicate
launch, readiness loss versus loading, cancellation, manager restart, exhausted
budgets and retained native uncertainty. Separately reviewed installation must
prove preserved configuration, exclusive handover and rollback. Actual Studio
acceptance must show metadata-only recovery and the authorized activity/drain
scenarios. Core small-model results and private child relaunches cannot close
Studio lifecycle acceptance or T027/T049/T051.

Native recovery configuration correlation includes the exact fixed launch arguments,
noncredential environment and explicit cwd in addition to executable image pins.
API-key values are replaced with a named credential slot before hashing; changing
that channel still changes the profile. A changed configuration refuses existing
pending history without rewriting it. This does not enroll inputs or issue a
native reservation. Session-only recovery keeps its independent session profile.

Reviewed native launch inputs must retain exactly one supported credential
channel. The pinned server accepts two-token `--api-key <value>` or
`--api-key-env FIOS_MLX_SERVING_API_KEY`; its empty/unset environment behavior
would otherwise start without authentication. The code-only native constructor
now refuses missing/empty/duplicate channels and unsupported equals forms before
process dispatch. Private model-free process constructors remain isolated test
fixtures. This validates launch data; it is neither a protected profile loader
nor an authority producer and makes no interface authentication change.

Reviewed native inputs now require explicit literal bind-address and canonical
port arguments before construction. The agent cannot choose the native CLI's
wildcard/default listener by omission. This changes no live binding and does not
approve an explicit new LAN/public listener; preserved installed configuration
and handover still require independent review.


The protected source configuration can construct its read-only health collector
from the reviewed launch listener without resolving the serving credential.
The exact reviewed port is retained. IPv4/IPv6 wildcard listeners map only to
the corresponding local loopback family; explicit loopback uses the same family.
Other interface bindings refuse this collector until separately enrolled rather
than silently probing the default endpoint. This sends metadata GET /health
only, and process identity still brackets the probe. A matching health reply
is neither listening-socket ownership nor native lifecycle authority. Public
startup remains closed and installed configuration/handover remain unaccepted.


Native source health collection additionally brackets GET /health with a bounded
read-only kernel FD/socket association for the exact observed process PID/start.
The same listening descriptor, kernel generation and opaque socket/PCB identity
must remain associated with the local probe address/port across the request.
Missing metadata, truncation, unsupported family, socket sharing, multiple local
matches or a changed process/listener leaves the observation unknown. These
opaque identifiers never enter status/log output. The final socket sample is
included in the collector's total elapsed/freshness limits. This is positive
process/listener association only, not global listener exclusivity, response
cryptographic authentication, all-client activity or native lifecycle authority.
