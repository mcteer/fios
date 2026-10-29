# Quickstart / validation guide — partial implementation

G1 and implementation authorization are resolved. Independent mock/disposable-process development proceeds now; G2 remains a native activation/acceptance gate. Commands below distinguish implemented tests from future acceptance. No sudo/SSH/reboot/model command is hidden in the mock path.

## 1. Gates and prerequisites

1. Review the accepted [governance-proposal.md](governance-proposal.md), constitution2.1.0 and ADR0003. No repeated implementation approval is needed; the16/16 specification checklist alone was never operational permission.
2. Confirm the two Studio identities and installed OS/MLX/OrbStack/CLI/signatures/caps with separately approved read-only inventory. Record hashes, source coverage and limits in a redacted compatibility record. Do not print environment, argv containing secrets, prompts or raw native logs.
3. Before native activation, prove the [native contract](contracts/activity.md) covers all clients and admission races. If missing, separately review native integration; continue independent implementation without turning on unsupported sampling or exposing metrics on LAN.
4. Install development toolchain versions from the release manifest; retain current locked Python and app dependencies. No native service installation is needed for mock tests.

## 2. Mock-first implementation validation

```sh
# Existing application baseline; mock-only test paths, not production SQLite.
npm ci
uv sync --locked --no-editable --reinstall-package fios-agent
npm test
npm run build
npx playwright test
npm audit
uvx --python 3.11.17 --from pip-audit==2.10.1 pip-audit --path .venv/lib/python3.11/site-packages
node scripts/check-agent-boundary.mjs
docker compose config --quiet

# Implemented dependency-free Swift tests (local XCTest/macros unavailable).
swift build --package-path platform/studio
node scripts/check-platform.mjs --mock
node scripts/check-platform.mjs --mock --release
# Explicit local disposable runtime measurements; uses existing fios:current, no pulls/models.
node scripts/check-platform.mjs --isolated-metrics
# Artifact-only staging/corruption/publication rehearsal; independently reviewed receipt required.
node scripts/check-platform-staging.mjs --isolated --release /ABSOLUTE/REVIEWED_RELEASE --sha256 REVIEWED_MANIFEST_SHA
node scripts/check-platform-process.mjs --isolated
node scripts/check-platform-boot.mjs --isolated
node scripts/check-platform-boot-state.mjs --isolated
node scripts/check-platform-manager-execution.mjs --mock --models
node scripts/check-platform-session.mjs --isolated
node scripts/check-platform-session-control.mjs --isolated
node scripts/check-platform-session-driver.mjs --isolated
node scripts/check-platform-supervisor-lock.mjs --isolated
node scripts/check-platform-supervisor-budget.mjs --isolated
node scripts/check-platform-watchdog.mjs --isolated
# Disposable local runtime fixture; existing immutable fios:current base only.
node scripts/check-platform-sandbox.mjs --isolated
# Full finite isolation/cgroup + lost-result/restart/owned-cleanup rehearsal.
node scripts/check-platform-container.mjs --isolated
node scripts/check-platform-runner.mjs --isolated
# Explicit image candidate producer; review metadata is not enrollment/approval.
node scripts/package-platform-sandbox.mjs --review /ABSOLUTE/REVIEW.json --sha256 INDEPENDENT_REVIEW_SHA256 --output /ABSOLUTE/PRIVATE_PARENT/NEW_CANDIDATE
node scripts/check-platform-runner.mjs --isolated --image sha256:ACTUAL_CANDIDATE_IMAGE_ID
node scripts/check-platform-attach.mjs --isolated
# Whole manager IPC/runner path; synthetic resource sources, no model calls.
node scripts/check-platform-manager-execution.mjs --isolated
# Also exercise installed no-tools workers against a fake native endpoint.
node scripts/check-platform-manager-execution.mjs --isolated --models
```

Expected: failing-first evidence for new policy/contracts, then passing Swift, installed-Python and isolated runtime tests. Unit networking is guarded; service lifecycle operations use fake adapters. Container rehearsal uses its own labeled temporary test namespace with no production mounts/socket passed to untrusted images; trusted host test driver owns runtime control. Confirm unrelated sentinel container/volume survives. Record actual counts and commands in validation; do not reuse008 counts as009 evidence.

`check-platform-container.mjs --isolated` builds only disposable images from the already-cached immutable `fios:current` ID, with build networking/pulls disabled. A finite hardened sibling listener has only an existing Docker-private bridge address and no published ports; the tested sandbox remains network-none. A private host file, container and empty uniquely named volume act as unchanged sentinels. Three separately reaped journal helpers exercise actual create/inspect/remove and result loss across restart; an absent private Unix endpoint injects transport loss without stopping OrbStack. Exact-ID absence releases only owned sandbox state, while a never-dispatched synthetic native claim remains uncertain. This does not establish daemon-reboot recovery, genuine native terminality, reviewed image/profile enrollment or either Studio's installed acceptance. On uncertainty, the driver retains its receipt/state/resources and performs no parent cleanup; inspect the reported private directory rather than pruning or replaying creation.

For the runtime endpoint postcheck's causal test, `node scripts/check-platform.mjs --mock --mutate-runtime-postcheck` must fail at `Successful local command hid a changed runtime endpoint`. It mutates only a private Core source copy and a generated fake endpoint; it does not contact the installed daemon. Ordinary `--mock`/`--mock --release` must pass the genuine command, metadata and attach checks.

Optional macOS source prerequisite, with the reviewed Zig0.17.0 executable: `node scripts/check-platform-native-startup.mjs --isolated --zig /ABS/zig`. It compiles libc-only disposable Debug/ReleaseSafe children, runs finite ownership/file-safety checks and removes only its private scratch. It does not start MLX/OrbStack or establish production singleton/native terminality. Adding `--mutate-lock` deliberately removes locking in a private copy and must fail the duplicate assertion.

## 2a. Implemented local CLI and explicit limits

Commands below require existing private development state and the built `studioctl`; they do not install/start native applications or mint model permission. Replace placeholders locally; never paste credentials into argv, environment, logs or this document.

```sh
studioctl --state /ABS/PRIVATE_STATE status
studioctl --state /ABS/PRIVATE_STATE activity
studioctl --state /ABS/PRIVATE_STATE resources
studioctl --state /ABS/PRIVATE_STATE supervisor
studioctl --state /ABS/PRIVATE_STATE task < /ABS/PRIVATE_TASK_REQUEST.json
studioctl --state /ABS/PRIVATE_STATE service mlx maintenance
studioctl --state /ABS/PRIVATE_STATE service orbstack stopped
```

`task` accepts one bounded versioned JSON request on stdin, including the authenticated task credential only in that private channel, and uses only `task.sock`. See [control-plane](contracts/control-plane.md), [model-access](contracts/model-access.md) and [sandbox-lifecycle](contracts/sandbox-lifecycle.md) for exact operations/payloads; never invent submit/retry flags or grant a model the operator socket. Ordinary manager enrollment remains unavailable; injected fixture success is not production task eligibility.

Fixed operator grammar is `service mlx|orbstack running|maintenance|stopped|drain`, `service SERVICE force prepare`, or `service SERVICE force confirm TOKEN SCOPE_DIGEST`. Desired changes persist with `applied:false`. Drain/force currently return `native_unsupported`, `applied:false`; no production scope issuer/actuator exists. A caller-provided digest does not create trusted affected scope. Malformed grammar exits2; refused requests exit1. `export` is fixed observation-only; SSH use additionally requires separately reviewed forced-command/no-forwarding enrollment, not a general shell.

Bounds: two sandboxes plus two model-only jobs;512MiB–2GiB and1–2CPU per sandbox,4 aggregate CPUs and64PIDs per sandbox; two512MiB private model workers/host, at most one active POST/job and two active-or-uncertain host requests; four POSTs/job,128000 input/64000 output UTF-16 units/request,256000 output UTF-16 units/job and8192 output tokens/request. Exact approved IDs only, no retries/failover/tools. RAM reserve is ceil(max(16GiB,20%)); CPU≤80%; disk≥10GiB after queued and retained commitments. Unknown/stale host/VM capacity or unmanaged runtime work cannot be converted into free resources. GPU observations are metadata, never idle/terminal proof.

Leases are30s with10s renewal,900s default task deadline/1800s maximum. Expiry/revocation/clock rollback irreversibly fences further dispatch and triggers exact-owned cancellation; it does not prove native completion. Artifacts are16MiB/job,4GiB/256 retained records,24h cleanup with bounded transfers and link/traversal/hash refusal. Cleanup uses full recorded IDs/nonces/labels and verified terminal/removal outcomes; never prune unrelated containers/volumes or clear native uncertainty on timeout, PID exit, reboot or zero owners.

For stopped-state backup/verification/fresh restore only:

```sh
studioctl --state /ABS/STOPPED_STATE backup-state --to /ABS/NEW_BACKUP
studioctl --state /ABS/NEW_BACKUP verify-backup --sha256 REVIEWED_DIGEST
studioctl --state /ABS/NEW_BACKUP restore-state --sha256 REVIEWED_DIGEST --to /ABS/NEW_STATE
```

If service-recovery metadata exists, the stopped bundle uses version2 and preserves its exact unresolved launch intents and start budgets; otherwise it retains version1. Verification/restore include that file and reject tampering. Older tools must refuse version2 rather than omit its state or clear pending launches. The recovery controller is not yet wired to a production session transport.

Both writer locks must be available. These commands preserve the separate platform journal and exports, reject foreign schemas/links/overwrite and never touch Fios SQLite or start the restored state. Journal-only `backup` is not a full export backup. Preserve artifacts/config and backups separately; incompatible rollback remains stopped/maintenance rather than discarding unresolved ownership. The installer is review-only and refuses application of incomplete development packages. See [deployment guidance](../../platform/studio/deployment/README.md); no sudo/SSH/reboot/lifecycle action follows from these examples.

008 remains parked at `3936da2`. Its eventual consumer must verify009's normalized authenticated source/process/epoch/coverage and admission contract; unavailable/unknown stays unavailable, not resident-only routing or silent fallback. No008 import/resume/deployment is implied.

## 3. Independently testable story scenarios

| Story | Scenario | Observable pass |
| --- | --- | --- |
| US1 | Fake boot before login, hang/exit, repeated failures, absent session | One manager, observable supervisor≤60s, bounded recovery≤30s, restart budget honored, explicit waiting session |
| US2 | Direct/tunnelled/manager activity, prepare/queue/stream/slow reader, races, source loss | All clients covered; stale/unknown never idle; same-model sharing; no conflicting active displacement; independent uncertainty |
| US3 | Maintenance, app identity/PID reuse, absent/hung services, unmanaged runtime work | Fixed operations only; no health inference; no unapproved kill/restart; force scope confirmation expires |
| US4 | Concurrent admission, resource loss, complete/cancel/expiry, uncertain create, runtime loss | Bounds enforced, no duplicate dispatch; network-none; owned cleanup≤60s after runtime available; unrelated resources retained |
| US5 | Installed worker + fixed sandbox pipe runner | Exact model and permission;4 POST limit, no tools/retry; expired lease cannot dispatch; bounded/reaped children; no secrets |

Additional hostile cases: model-only job/worker exhaustion, worker-memory pressure/reservations, chunk ordering/duplicate/hash/timeout/Unicode boundaries, fake labels, forged job/role, overflow/duplicate JSON keys, excessive connections, malicious stdout, symlink/export traversal, snapshot replay, clock changes, closed-but-running native request, still-running older request after newer completion, retained reservation after unknown create, and model text requesting control-plane access.

## 4. Separately authorized host acceptance

No live tests occur as a side effect of CI or planning. Give the user the exact host, operations, privilege requirements, active-work safety check, expected duration and rollback before asking for approval. Start with one Studio, not simultaneous disruptive tests.

- Boot/session and watchdog tests need explicit reboot/failure-injection approval. Preserve disk encryption and login settings; demonstrate supervisor before login and dependent services waiting when appropriate.
- Native source/admission tests need distinct approval for direct/tunnelled/manager requests, overlaps/cancellation/races and model resource envelopes. Never intentionally replace a busy model or start a huge cold model. Record source/native version and coverage gaps; fail acceptance if all-client coverage is absent.
- Resource and sandbox tests need permission for temporary container work, bounded images/input and controlled pressure fixtures. Real hardware stress or competing native workloads require their own envelope.
- Demonstrate one bounded platform model task and one sandbox model interaction using an explicitly approved exact already-loaded small identity, then revoke/clean up and verify absence. Mocks do not prove semantic model competence.

## 5. Release, rollback and uninstall rehearsal

Reviewed PR with six exact-head checks plus native mock/macOS package checks feeding the CI gate; independently green merged main. No PR-built container gets production credentials or a host runtime socket. Existing app delivery remains app-only; native rollout is a separately approved operation from reviewed artifacts.

Disable admission; revoke leases; reconcile owned containers/native requests; stop the manager only after safe state/explicit unresolved-work handling. Back up its separate DB/export manifest and previous executable/config with the manager stopped. Upgrade one host, verify signature/hash/schema/service identity and non-inference health. On failure restore compatible prior artifacts/state, preserving unresolved ownership rather than clearing it. If old version cannot preserve safety, remain in observation/maintenance mode and report blocked rollback.

Uninstall removes only009's verified jobs/binaries/owned ephemeral resources and dedicated keys after drain. Preserve exports/backups per retention/operator choice. Never remove MLX-Serve, OrbStack, existing Fios services, user login configuration or unrelated volumes. Do not re-enable005's installer. Capture exact artifact/revision, backup, rollback and verification in validation; do not call green CI a native deployment.

Manager execution source composition and fixture limits: [manager-execution.md](contracts/manager-execution.md). Public task execution remains disabled; these source fixtures do not enroll native activity/admission.
