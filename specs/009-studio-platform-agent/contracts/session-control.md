# Private session launch transport

Status: source adapter wired into the session entry point, with isolated
fake-launcher fixtures. Development, unenrolled and one-shot runs remain
observation-only. No policy/manifests have been installed and no real native
application launch/quit is claimed. Installation and live acceptance remain
separately gated.

The trusted constructor receives the immutable reviewed manager executable and
the exact approved executable path/hash for each fixed service. No path, argv,
environment, endpoint or role can arrive in a request. A future production
issuer must derive these inputs from reviewed installation policy, independently
of session metadata and task/model data; it must preserve the fixed application
and bundle mappings in `SessionPlan`.

The helper exclusively owns its private0700 directory,0600 Unix socket and
generation descriptor. The descriptor bootstraps a connection; it cannot grant
authority. Both endpoints verify actual kernel peer UID/PID/start and pinned
image identity. Requests and responses use a four-byte big-endian length prefix,
one JSON value and EOF. Requests are at most1024 bytes, replies2048 bytes, with
a finite2s exchange and at most16 concurrent clients. Duplicate/unknown keys,
trailing bytes, malformed scalars and incomplete streams refuse before action.

A request has exactly `version:1`, canonical UUID `id`, `operation` (`launch` or
`lookup`), fixed `service` (`mlx` or `orbstack`), helper UUID `instance` and SHA256
`profile`. A reply binds version/id/service/instance/profile and a fixed status:
`not_sent`, `uncertain`, `wrong_instance`, `busy` or `started`. Only `started`
adds PID, canonical decimal-string process-start identity and approved SHA256.
Transport failure never becomes `not_sent`.

The helper consumes a launch ID before calling its local actuator. Its bounded
256-entry generation-local cache never repeats a consumed action; missing lookup
history is uncertain. Unresolved launch state blocks another start for that
service. Clock rollback permanently fences the generation. Only a correlated
local completion for an existing uncertain request may record `started`, after
independently verifying current UID, kernel path/start and approved executable
hash. That completion is not a wire operation; it cannot rewrite `not_sent`,
resolve another service/request/helper generation or bypass a clock fence.

The manager must persist its launch intent before sending and retain it across
timeout/helper restart/cache loss. A fresh presence/absence sample or elapsed
time cannot retire it. Session RPC does not establish native activity,
quiescence, readiness or model terminality, and cannot authorize ordinary quit.

`node scripts/check-platform-session-control.mjs --isolated` uses disposable
same-binary peers and a counter-only fake actuator. Its optional
`--mutate-eof` mode changes only a private temporary source copy and is expected
to fail specifically at the authenticated partial-stream non-dispatch check.
Neither mode invokes AppKit lifecycle, launchd, a model or a production runtime.

## Installation enrollment source boundary

`SessionEnrollmentDocument` accepts at most4096 bytes with exactly these fields:
`version:1`, `purpose:"reviewed_session_launch"`, nonzero integer `uid`, one of
the two approved Studio `host` names, canonical absolute `state_path`, and
lowercase SHA256 `review_sha256`, `manager_sha256`, `session_sha256`,
`mlx_application_sha256`, `orbstack_application_sha256`. The review hash identifies
the operator's review receipt; it is not automatic proof of whole-repository,
installed dependency or native all-client provenance. No executable path, role,
argv, environment, arbitrary host, tools or activation flag is accepted.

The separate `SessionEnrolledPolicy.load` source factory reads only
`/Library/Application Support/Fios/Studio/session-enrollment.json` through
`RootPolicyFile`; its initializer is private. Missing policy returns no enrolled
authority. Malformed/inaccessible policy or a different user/host/state refuses.
The factory verifies root-protected manager/helper executable paths and hashes,
then the calling entry point's actual UID/PID/start/kernel path/hash for its fixed
manager or session role. It constructs fixed `MLXCore` and `OrbStack` executable
pins. The session entry point calls the factory only for its long-running mode;
development executable paths cannot obtain enrollment even on an installed
Studio. No policy is generated or installed by these source fixtures.

Immutable-file checks reject writable or non-root parents, symlinks, explicit
ACL objects, hardlinked files, wrong permissions/hash and changed descriptor/name
metadata. These checks prove the current protected file, not mapped-code lifetime
or a completed release/enrollment. The reviewed installer must serialize updates,
stop old processes and establish the full approved artifact/resource provenance.
Ordinary lifecycle, native quiescence, inference and sandbox grants remain
independent; this launch-only document cannot establish them.

## Fixed actuator and asynchronous sequencing

`EnrolledSessionDriver` validates at most one application at a time off its
polling loop, with no validation queue and a10s pre-effect deadline. It checks
the complete bounded physical bundle (8192 entries/32 levels), root ownership,
non-writable permissions/no ACL, and resolves relative links only within the
collected tree (128 resolution steps). Root-owned read-only resource hardlinks
are safe because aliases share the inode's ownership/permissions; entry-point
executables and policy files remain single-link. Static Apple signature checks
cover all architectures, nested code and strict sealed resources, without the
network-access flag. Exact bundle/executable identities and the MLX team remain
pinned. These are current-file proofs subject to serialized immutable updates.

Only a correlated validation completion may claim one local dispatch edge. That
edge independently checks the current UTC clock and permanently refuses a
rollback; final/not-sent/already-dispatched requests cannot claim again. Validation
failure, expiry, lost GUI session or an already-running bundle returns a local
non-dispatch receipt before any application API call. Shutdown prevents pending
validation continuations from issuing an operation. After dispatch, an AppKit
error stays uncertain. A successful callback must pass actual PID/start/UID/path/
hash checks; duplicate callbacks are inert. No deadline or shutdown quits a
native app or clears native inference uncertainty.

The AppKit adapter lives only in `StudioSession`, using fixed bundle descriptors,
no caller arguments/environment, no new app instance, no activation and no
credential/login prompts. Core's public factory always performs enrollment and
the fixed validator; its code-only native adapter is not decoded from requests.
The internal Core constructor/ports are available to trusted compiled fixtures,
not the separate session target or a runtime policy selector. The legacy
observation file continues to grant no lifecycle authority; launch-only RPC
requires independent enrollment and kernel peer authentication.

`node scripts/check-platform-session-driver.mjs --isolated` runs the real driver
and kernel-authenticated RPC with a counter-only fake application API. It covers
one validator/no queue, delayed and duplicate success, validation/session/presence/
expiry refusal, post-dispatch error/wrong-process uncertainty, shutdown, clock
fencing and replay. It neither calls the enrolled factory nor opens a GUI app.
The separate signature fixture reads the genuine protected system Calculator
bundle without launching it. Neither fixture is installed/native lifecycle or
all-client/model acceptance.
