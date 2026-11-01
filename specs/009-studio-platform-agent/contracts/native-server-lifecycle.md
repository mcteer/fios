# Native MLX server lifecycle

The operator selected direct agent ownership on2026-11-01. This is the target
implementation for FR-003/US3. Opening MLXCore is not server recovery. Source
implementation is incomplete; no installed lifecycle acceptance is claimed.

## Ownership and configuration

The trusted manager owns the exact reviewed native `mlx-serve` child. OrbStack
continues to use its supported session lifecycle. Native server ownership does
not require the GUI to remain running; an open GUI is neither server readiness
nor permission to launch. Do not implement lifecycle through GUI scripting,
name/port-based process killing or a general shell command.

Installation must review a single handover from the existing GUI controller:
preserve its exact serving arguments, listener binding, credential source,
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

The source recovery journal's version2 record retains the last correlated
started acknowledgement per fixed service: operation ID, PID, canonical
decimal-string kernel start, image hash and original boot, under the same
reviewed profile. Clear the pending launch and persist this record in one
durable write. Version1 input has no such evidence; reading it cannot invent a
receipt. Reboot, later not-sent replies and manager reconstruction must not
reinterpret historical evidence as current ownership. Live identity, protected
profile/namespace and native lifecycle authority must still be established
before adoption or disruption. The record alone never clears native inference
uncertainty or unlocks another launch.

Stopped-state backup/restore retains the complete recovery file. Older binaries
which cannot read version2 must refuse it; do not remove the file, drop the
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
The durable stop-operation/controller bridge and control of a server surviving
manager death remain unfinished. A historical PID cannot be adopted into POSIX
child custody after reparenting; recovered control needs its own reviewed
identity-bound native mechanism. Private helper stop/relaunch tests supply none
of that installed authority.

Source/private-process fixtures must cover exit with GUI alive, no duplicate
launch, readiness loss versus loading, cancellation, manager restart, exhausted
budgets and retained native uncertainty. Separately reviewed installation must
prove preserved configuration, exclusive handover and rollback. Actual Studio
acceptance must show metadata-only recovery and the authorized activity/drain
scenarios. Core small-model results and private child relaunches cannot close
Studio lifecycle acceptance or T027/T049/T051.
