# Scoped platform/sandbox model access v1

## Boundary

Separate private installed Pydantic worker entry point under `src/agent/`, no listener/SQLite or host tools. Swift owns lifecycle/authorization/journal; Python owns every actual language-model POST. No direct Swift/Express/Docker-runner inference fallback. Existing007 worker IPCv2, search limits, auth, context and UI behavior are unchanged.009's pipe version1 is a distinct entry point, never a downgrade accepted by007.

Approved profile maps a canonical exact catalog identity to its independently verified native-local identity/endpoint. Preserve peer-qualified IDs in consumer/ownership records; any local ID translation is an explicit enrolled mapping checked against the host catalog, not arbitrary suffix stripping, default-model aliasing or model-generated selection. No cloud provider, arbitrary URL/header, automatic substitution, retry or second host.

009 task access names an exact approved model and checks its readiness/resource envelope. Ordinary native on-demand inference may replace an idle resident model. No loaded-only option is required; native in-use ownership must prevent conflicting active-model displacement at admission. Do not issue separate admin load/unload calls or synthetic warmups.008's future Gemma/delegation policy is separate and remains parked.

## Budgets and command/event lifecycle

- At most4 actual model POSTs/job, attempts0..3; at most1 active per job and2 active/uncertain manager-originated model requests/host (external native same-model concurrency is not prohibited).≤32 unresolved owned records/host is a separate safety bound.
- At most2 model-only jobs and2 sandbox jobs/host, at most2 live Python workers total; reserve512MiB/worker against host headroom before spawn. Poll worker RSS every1s; crossing512MiB initiates cancel/kill/reap within2s and retains uncertain native ownership. This is supervised pressure handling, not a claim that macOS prevents transient RSS overshoot. Release worker-memory reservation only after reaping; do not release native ownership on child exit.
- Per request:≤128000 UTF-16 input,≤64000 UTF-16 output,8192 max output tokens; job total≤256000 UTF-16 output. Text-only initially; images/tools/search/delegation disabled. Fixed system policy/canonical text context counts toward input. Reject unsupported capabilities before dispatch.
- Native first-response/stream-idle deadline180s, total request deadline180s, job absolute lifetime≤1800s. No budgets reset on reconnect/worker restart. On worker failure, output uncertainty is preserved and no automatic replay occurs.
- Worker command≤1MiB, event≤256KiB, text delta≤32Ki UTF-16, upstream SSE≤4MiB. Startup10s, pipe write10s, output drain/backpressure bounded; exceeding limits cancels, reports fixed error and retains uncertain native ownership when applicable. Cleanup TERM1s/KILL1.5s, reaped within2s.
- Parent authenticates active lease/grant, reserves per-job/host budget and persists `(job_id,attempt)` before issuing a one-use correlated dispatch permission expiring within5s. Permission binds exact model, host/endpoint, epoch and attempt. New lease renewal cannot revive a permission or request already cancelled.
- Child independently validates exact target readiness, native guard and permission, then emits `dispatched` at the actual POST boundary and a once-only usage summary. Permission/reservation is not proof of actual POST count; crash before a trustworthy boundary leaves accounting uncertain. No retries at Agent/SDK/HTTP levels.
- Completion requires a full valid response, upstream `[DONE]` for streaming, actual Agent completion and correlated parent processing. Only then release that request's ownership; late data after cancellation is discarded. If termination remains uncertain, retain row until native proof; never clear older uncertainty on a newer success.

External task/sandbox payloads use the control-plane begin/chunk/end protocol:≤64KiB frames,≤32KiB decoded input chunks and≤8Ki UTF-16 output chunks. The larger private Python frame limit never authorizes larger sandbox/control frames. Sandbox input/output remains ephemeral in bounded pipes/memory. Routine logs and the manager DB contain no prompt, task code, model output/reasoning or raw error bodies. Exporting task output is an explicit owner artifact operation, not automatic diagnostic persistence.

## Independent child native guard

The enrolled parent supplies fixed private environment metadata (never task frames): `FIOS_PLATFORM_GUARD_PATH` (only the private `observe.sock`), `FIOS_PLATFORM_HOST_ID`, `FIOS_PLATFORM_PROFILE_HASH`, `FIOS_PLATFORM_NATIVE_EPOCH`, `FIOS_PLATFORM_NATIVE_SEQUENCE`, `FIOS_PLATFORM_CANONICAL_MODEL` and `FIOS_PLATFORM_NATIVE_MODEL`. The exact canonical/native mapping is explicit; no suffix stripping. No runtime socket, broad caller environment or management capability is forwarded.

Immediately before the actual POST, the child independently reads the manager's bounded read-only activity projection over the UID-authenticated private Unix socket. It validates socket/directory ownership and permissions, framed JSON/correlation, enrolled host/endpoint/profile, expected manager/native epochs, nonregressing native sequence,≤5s age/≤1s future bound, coverage, bounded ownership counts and transition state. Unknown/unsupported/loading/busy-different-model refuses dispatch; idle replacement and same-model overlap remain allowed. The current internal12-field normalized projection is **not** a claim that the full future008 public activity contract/native adapter is complete.

The guard await is followed by another cancellation/permission-expiry check; a pre-send notification is not proof of actual POST. Missing enrollment fails closed. Activity remains advisory: accepted native in-use protection must close snapshot→dispatch races; neither socket authentication nor these child checks satisfy G2 by themselves.

## Model input has no control authority

Tool registrations are absent in this entry point. Generated text can be returned as task data but cannot invoke service operations, launch jobs, alter model/network policy, discover credentials or select another endpoint. Sandboxed code may act on returned text only inside its existing isolated resources; it has no management capability. Any future tool-enabled platform behavior requires a separate spec/permission review.

## Tests

Installed-distribution contract tests use fake model transports and network guards, never live discovery/inference by default. Cover exact-ID mapping, unknown model/capability, guard race refusal, once-only permission, every actual-POST bound, malformed/overlong input/SSE/output, missing DONE/Agent completion, cancellation before/after dispatch, worker crash, parent backpressure, stale/expired lease, source loss, no tools/retries and no secret propagation. A real platform task and sandbox-mediated task require separate explicit opt-in with an approved already-loaded small model and temporary resources; no huge cold benchmark.
