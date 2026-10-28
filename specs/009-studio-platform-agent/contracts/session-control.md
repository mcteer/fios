# Private session launch transport

Status: source component and isolated fake-launcher fixtures. The production
session entry point remains observation-only. This contract does not authorize
installation, native app launch/quit or a new policy issuer.

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
