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
node scripts/check-agent-container.mjs
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
# Private IPC/source/never-dispatched-intent rehearsal only; no native/runtime/model action.
node scripts/check-platform-drain.mjs --isolated
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

Finite private failure checks for the current teardown/durability boundaries:

```sh
node scripts/check-platform.mjs --mock --mutate-command-reap
node scripts/check-platform.mjs --mock --mutate-service-ack-durability
```

Each command must exit nonzero at its exact runtime witness: `COMMAND_SLOT_RELEASED_UNPROVEN_CHILD` or `SERVICE_RECOVERY_ACK_PUBLISHED_BEFORE_DURABILITY`. A compiler error or timeout is not evidence. The first uses a metadata-only Process double naming the live test PID and never signals it; the second fails an actual atomic rename inside disposable state. Production source is unchanged. Normal Debug/optimized suites must pass. A local child exit releases only proven local process capacity; a durable launch acknowledgement clears only that correlated service intent. Neither proves native request completion or an absent daemon effect.

Optional macOS source prerequisite, with the reviewed Zig0.17.0 executable: `node scripts/check-platform-native-startup.mjs --isolated --zig /ABS/zig`. It compiles libc-only disposable Debug/ReleaseSafe children, runs finite ownership/file-safety checks and removes only its private scratch. It does not start MLX/OrbStack or establish production singleton/native terminality. Adding `--mutate-lock` deliberately removes locking in a private copy and must fail the duplicate assertion.

The separate future-installed startup path has a finite private harness:

    node scripts/check-platform-native-installed-startup.mjs --isolated --zig /ABS/zig

It uses a substituted disposable namespace/owner, real process locking and an
exact private flock-omission witness. It never accesses an installed lock,
starts MLX or grants native authority. See
[the startup reservation contract](contracts/native-startup-reservation.md).


To check source dependency composition after reviewing the exact MIMO candidate:

```sh
node scripts/check-platform-native-fixture.mjs --source /ABS/DISPOSABLE_NATIVE --zig /ABS/PINNED_ZIG --webp-source /ABS/PINNED_WEBP --metal-cpp-zip /ABS/PINNED_METAL_ZIP --ds4-build /ABS/FRESH_DS4_BUILD/candidate.json --ds4-sha256 EXACT_DS4_BUILD_RECEIPT_SHA --mimo-source /ABS/DISPOSABLE_MIMO_CANDIDATE
```

Both source checkouts must resolve beneath `/private/tmp`, belong to the development user and retain their reviewed commits. The optional candidate must match exactly the repository's `mlx-stream-fcb4011-retirement.patch` at its pinned plugin revision; altered tracked inputs are refused before compilation. The native build's existing dependency option selects it without modifying the canonical submodule. The fixture brackets its declared commit/patch/modified-source inputs and all installed runtime hashes, runs seventeen actual native root cases plus private HTTP/control/manager checks, and emits the temporary binary digest separately from candidate inputs. No real model runs. Omitting `--mimo-source` retains the clean upstream MIMO dependency; the reviewed DS4 source input remains explicit. Successful compilation/runtime fixtures do not establish all-client/Metal/model retirement, complete context lifetime or production enrollment; candidate pause control stays default-disabled.

The separate candidate’s CPU lifetime witness is finite and never runs a model or Metal kernel:

```sh
node scripts/check-platform-mimo.mjs --source /ABS/DISPOSABLE_NATIVE --zig /ABS/PINNED_ZIG --mimo-source /ABS/DISPOSABLE_MIMO_CANDIDATE --mutation-lifetime
```

This wrapper must exit0 only after its private optimized bypass actually fails `FIO_MIMO_DESTROY_DROPPED_HELD_ENGINE` with9pass/1fail of10, then restores source. Ordinary invocation and `--debug` require10 focused cases plus13 upstream passes/1 explicitly skipped GPU-window case. Lifetime release drops custody only; it never proves native terminality. The candidate now carries known-custody preflights through Source, Module, stream model, Transformer and LoadedModel before cleanup. The source checks verify each delegation and reject individual omissions; they are not runtime model/context acceptance. Atomic lifetime reservation, deferred cleanup and complete backend ownership remain unfinished. The reviewed candidate surface is now exactly four files: gpu_warm/module/root/source under src/arch/mimo_v2.

Appending `--mutation-enclosing-custody` to the six-argument MIMO CPU command must reproduce9pass/1fail of10 at `FIO_MIMO_ENCLOSING_CUSTODY_ACCEPTED_HELD_ENGINE` and restore source. It checks the actual engine custody predicate; supplementary source checks cover the enclosing delegation chain. Neither result proves an atomic backend reservation.

Appending `--mutation-destruction-result` to the MIMO CPU command must reproduce9pass/1fail of10 at `FIO_MIMO_DESTRUCTION_REFUSAL_REPORTED_SUCCESS`, then restore source. The actual Engine test checks false while held and true after release/destruction. Current cleanup uses this checked result before clearing the warm pointer or freeing enclosing fields; it does not make status probes destructive or resolve independent native uncertainty.

For the retained-CPU cleanup guard, append `--mutation-retained-cpu-cleanup` to the native fixture command with its explicit DS4 receipt (without the MIMO option). The wrapper succeeds only after actual16pass/1fail of17 at `FIO_RETAINED_CPU_STATE_DROPPED_BORROW` and exact source restoration. Positive native-root runs require17/17. Static handoff checks additionally reject entry writes before checked transfer or fallible `try` work afterward; those text checks are supplementary, not real-model/backend acceptance.

For resident-unload custody, append `--mutation-resident-unload` to the same command, retaining the DS4 receipt. It requires actual16pass/1fail of17 at `FIO_RESIDENT_REFUSAL_REPORTED_MEMORY_FREE` and source restoration. The positive metadata case verifies explicit request errors, eviction refusal and retained bytes after borrower release; it does not run a model or establish backend terminality.

For durable service-scope regressions, `node scripts/check-platform.mjs --mock --mutate-force-request-identity` must exit nonzero at `FORCE_ACCEPTED_SUBSTITUTED_DURABLE_REQUEST`; `--mutate-drain-uncertainty-count` must exit nonzero at `DRAIN_ACCEPTED_SUBSTITUTED_DURABLE_REQUEST`. Each mutates only its disposable copied Swift source. Compiler failures are not runtime evidence. These cases validate exact durable request IDs and confer no native force/terminal authority.

Normalized activity policy cases live in `tests/fixtures/platform/activity.json`; Debug/optimized mock runs must execute all31 named vectors. `node scripts/check-platform.mjs --mock --mutate-activity-coverage` must exit nonzero at `ACTIVITY_FIXTURE_MISMATCH: source-ceiling-unknown`. This is an independent source-ceiling witness, not native/backend coverage or an admission grant.

Native object-lifetime metadata checks: `node scripts/check-platform-backend-lifetime.mjs --zig /ABS/PINNED_ZIG`, then append `--release` for ReleaseSafe or `--mutation-close-edge` for the precise held-child close bypass. The mutation wrapper requires its exact runtime marker and one failing selected case. These finite CPU-only checks run no backend/model and issue no native terminal/admission capability.

Private worker fixture timing: `node scripts/check-platform-worker-permission-fixture.mjs --isolated` requires one mocked POST followed by completion after the dispatch permission expires; append `--expect-expired` to require zero POSTs when readiness consumes that permission. Imports complete before the shorter test permission is issued. All real model/network transports remain blocked; production permission/deadline rules are unchanged.

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

Reviewed PR with all seven exact-head checks successful, including the aggregate CI gate; independently green merged main. No PR-built container gets production credentials or a host runtime socket. Existing app delivery remains app-only; native rollout is a separately approved operation from reviewed artifacts.

Disable admission; revoke leases; reconcile owned containers/native requests; stop the manager only after safe state/explicit unresolved-work handling. Back up its separate DB/export manifest and previous executable/config with the manager stopped. Upgrade one host, verify signature/hash/schema/service identity and non-inference health. On failure restore compatible prior artifacts/state, preserving unresolved ownership rather than clearing it. If old version cannot preserve safety, remain in observation/maintenance mode and report blocked rollback.

Uninstall removes only009's verified jobs/binaries/owned ephemeral resources and dedicated keys after drain. Preserve exports/backups per retention/operator choice. Never remove MLX-Serve, OrbStack, existing Fios services, user login configuration or unrelated volumes. Do not re-enable005's installer. Capture exact artifact/revision, backup, rollback and verification in validation; do not call green CI a native deployment.

Manager execution source composition and fixture limits: [manager-execution.md](contracts/manager-execution.md). Public task execution remains disabled; these source fixtures do not enroll native activity/admission.


For the serialized DS4 snapshot CPU-custody regression, run the existing finite
`check-platform-native-fixture.mjs` command with `--root-tests-only`, then with
`--mutation-ds4-snapshot-free`. The latter privately removes the exact destruction
guard, requires the allocator-observed runtime failure and restores source.
These runs use an empty CPU blob, no session/model, and confer no native admission
or installation authority. Do not run source mutations concurrently.

### Model-free llama draft retirement refusal

```sh
node scripts/check-platform-llama-retirement.mjs --isolated --source /ABS/DISPOSABLE_NATIVE
```

Requires the exact canonical root patch in a private disposable checkout and the pinned genuine llama library/headers already obtained by the source fixture. Compiles the actual C++ bridge in Debug/optimized mode, with empty CPU metadata and no context/model creation. The network-denied process checks sticky failure, reset/operation/retirement refusal and a private exact sticky-assignment omission. The replacement logger callback only suppresses output; no backend symbol is substituted. This is not loaded-context, native terminality, installed lifecycle or all-client acceptance. Each child has a5s alarm and10s harness timeout; uncertain process termination retains fixture state.

The metadata lifetime checker also accepts `--mutation-fence` for its precise sticky-uncertainty omission (expected runtime failure asserted by the driver). The linked native fixture accepts `--mutation-llama-trim-status` after its fixed input pairs/optional MIMO pair; it requires14pass/1fail of15 and FIO_LLAMA_TRIM_REFUSAL_ACCEPTED, restores source and emits no model/terminal authority. Run these sequentially with any other user of the disposable native source.

The optional private source capsule and fixed local Gemma preparation/check/explicit-run flow are documented in [native-model-source-review.md](contracts/native-model-source-review.md). Preparation and empty checks perform zero model POSTs. The operator granted blanket real-inference authorization for009 on2026-10-30; do not request it again within this work. Explicit finite run commands and one-use plans still apply. Do not interpret a capsule, plan, source fixture, model response or successful process reap as native admission/terminal authority.

### DS4 CPU pread participant source fixture

```sh
node scripts/check-platform-ds4-pread.mjs --isolated --source /ABS/PRIVATE_REVIEWED_DS4_CANDIDATE
```

The candidate must be pinned9139e2a with exactly the reviewed one-file pread-retirement patch. This runs bounded Debug/optimized CPU source-fragment checks, owned-file pread and real pthread joins, including explicit private scheduling/fault instrumentation. It performs no model/GPU/runtime action. Failures retain the private fixture state. The component is unwired and does not replace legacy cleanup or certify all-writer/device completion; see [the audit](native-backend-terminality.md).

### DS4 genuine keepalive producer source fixture

```sh
node scripts/check-platform-ds4-keepalive.mjs --isolated --source /ABS/PRIVATE_REVIEWED_DS4_KEEPALIVE_CANDIDATE --developer-dir /Applications/Xcode.app/Contents/Developer
```

This requires the exact9139e2a keepalive patch and signed Apple clang/SDK27.2. It runs the original fixed1KiB kernel on genuine private Metal objects, a real event gate, checked CPU-thread retirement and explicit private timing/fault instrumentation. No model, installed service or cluster action occurs. Each test has a finite deadline and independent event-release guard; failures retain private diagnostic state. GPU source-fragment success does not prove all device/backend/context participants or grant native admission. The pread and keepalive candidates remain independent, not silently composed.

### Explicit DS4 composition and full-module development checks

```sh
node scripts/check-platform-ds4-pread.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4 --composed
node scripts/check-platform-ds4-keepalive.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4 --developer-dir /Applications/Xcode.app/Contents/Developer --composed
node scripts/check-platform-ds4-build.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4 --developer-dir /Applications/Xcode.app/Contents/Developer
node scripts/check-platform-ds4-module.mjs --isolated --build /ABS/FRESH_BUILD/candidate.json --sha256 EXACT_BUILD_RECEIPT_SHA --developer-dir /Applications/Xcode.app/Contents/Developer
node scripts/check-platform-ds4-parent.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4
node scripts/check-platform-ds4-cpu.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4
node scripts/check-platform-ds4-service-thread.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4
node scripts/check-platform-ds4-session.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4
node scripts/check-platform-ds4-peer.mjs --isolated --source /ABS/PRIVATE_COMPOSED_DS4
node scripts/check-platform-ds4-selected.mjs --isolated --build /ABS/FRESH_BUILD/candidate.json --sha256 EXACT_BUILD_RECEIPT_SHA --developer-dir /Applications/Xcode.app/Contents/Developer
node scripts/check-platform-ds4-selected-ownership.mjs --isolated --build /ABS/FRESH_BUILD/candidate.json --sha256 EXACT_BUILD_RECEIPT_SHA --developer-dir /Applications/Xcode.app/Contents/Developer
node scripts/check-platform-ds4-selected-event.mjs --isolated --build /ABS/FRESH_BUILD/candidate.json --sha256 EXACT_BUILD_RECEIPT_SHA --developer-dir /Applications/Xcode.app/Contents/Developer
node scripts/check-platform-ds4-pagein.mjs --isolated --build /ABS/FRESH_BUILD/candidate.json --sha256 EXACT_BUILD_RECEIPT_SHA --developer-dir /Applications/Xcode.app/Contents/Developer
```

Only the reviewed cumulative participant patch is accepted. The build always uses a fresh private checkout, two compiler jobs and a180s deadline; it never executes/installs its benchmark. The separate module command is an explicit model-free development fixture: it verifies source/object/compiler bytes, compiles the whole genuine Metal module, links genuine built C objects and runs the original initializer/shader library/warm kernel/checked known producer under a120s deadline. A second complete-module executable (also120s) injects a software wait failure only after actual buffers complete, checking retained pending resources/accounting, sticky refusal and guarded command entry/cleanup; it is not a hardware-error test. A third complete-module executable runs three cold metadata-only sequence-boundary cases (10s each), including refusal before backend initialization and the last valid generation; no GPU/model is initialized by these cases. It opens no model/session, does not certify other participants or native device completion, and retains diagnostics. Neither command grants ordinary runtime/admission/lifecycle/installation authority; receipts describe declared inputs, not whole-native provenance.

The cumulative patch is restricted to exactly `ds4.c`, `ds4.h`, `ds4_gpu.h`, `ds4_gpu_tp.h`, `ds4_metal.m` and `ds4_tp.c`; standalone component candidates still modify only `ds4_metal.m`. The parent command compiles actual parent function text against explicit mock types/callees, checks refused teardown reaches no destructive calls, and includes null/empty controls. Its 30s compile/5s process bounds use no model, transport or GPU. This is source control-flow evidence, not real parent ABI, RDMA retirement, successful slab lifetime or all-writer terminality. Checked local TP success does not authorize native activation.

The CPU command compiles the actual pool fragment in Debug/optimized modes with genuine pthreads, held inline/parallel callbacks, nested row coverage and an injected acknowledgement failure after actual join. Each process has a10s deadline; the unrelated model-table initialization is stubbed. It also checks initializing-thread tokens, sixteen genuine thread lifetimes, private token exhaustion and two precise guard omissions. This is local creator evidence, not all CPU writers/creator domains, bounded native join deadlines or installation authority.

The service-thread command compiles the actual registration/predicate fragment with genuine pthreads at-O0/-O3. It requires observed reuse of a departed pthread handle's byte representation; lack of observed reuse refuses coverage rather than passing. Registration belongs to thread-local lifetime, never a stale global handle. This is CPU fragment evidence, not GPU completion or native authority.

The selected-event command compiles the complete genuine Metal module and links verified C objects. A real selected-readback event/command buffer supplies the positive completion control. Private UINT64_MAX initialization then checks refusal before zero encoding, retained event/batch/pending state, sticky refusal after a private counter reset, parent release refusal and cold no-initialization. A private checkpoint stops zero before any invalid Metal encode; this is software counter-boundary evidence, not natural exhaustion or hardware-error acceptance. Compile/process limits are120s/90s; no model is opened or inferred. All-client/device terminality and installation remain unproven.

The session command compiles actual destructor function text against explicit CPU-only mock layouts/callees, testing failed send/ack/transport, retained accounting, sticky session/parent custody and local successful-destruction control. It performs no peer, network or RDMA action and does not prove peer/GPU retirement. The selected-loader command compiles the complete real C source and links verified genuine objects. All four cases obtain a genuine GPU tensor and completed selected-readback event from public APIs, then submit an explicitly invalid empty NULL-model/layer payload; the real worker rejects it before model/GPU expert work. Private checkpoints hold the worker, its creator’s consumer frame or preparation before creation. A software EAGAIN refusal creates no phantom worker and is followed by a separate healthy empty enqueue. Start and finish stay on the same actual creator thread; a foreign observer only queries the held consumer. No SDK handle is manufactured. Custody covers preparation, mailbox work, completed results and the consumer frame; no model inference, valid-model competence, worker retirement or atomic all-writer admission is proved. Its idle local thread ends with the one-shot fixture process; process exit is not a native terminal receipt.

The selected-ownership command compiles the complete C source without function instrumentation and uses actual issued job tickets, genuine GPU primitives and the same invalid empty-model payload. First/initialized foreign pthreads and stale same-creator copies must refuse without consuming the current result; its creator then consumes it. Source-owned non-reusable thread/ticket IDs provide that local identity. A private last-ticket/exhaustion case tests refusal without wrap; it is not natural lifetime exhaustion. Each process is90s bounded and no model is opened/inferred. This is local job-custody evidence, not worker retirement, valid-model competence, all-client/device authority or installed acceptance.

The peer command compiles actual table/ACK/worker-cleanup source against explicit mock CPU layouts/callees in Debug/optimized mode. It checks refusal retention, failure ACK status, heap-custody/transport retention, successful local controls and sticky no-retry, without creating a peer/socket/native context or exercising RDMA. Session source guards also cover known CPU/TP/selected busy state before mutations. Append `--mutation-tp-busy-guard` or `--mutation-cpu-busy-guard` to the session command for the exact private caller-guard omission witness. These are source-control-flow cases, not native parent ABI or distributed/GPU retirement.

The native-root fixture now requires the explicit hash-bound DS4 build receipt immediately after its four fixed input pairs. It independently checks the candidate's pin, exact six-path patch and bytes of all154 declared source files, then redirects only11 explicit DS4 include/C/ObjC build paths in its disposable graph. The canonical submodule stays unchanged; original embedded shaders are unchanged by the reviewed patch. The root genuinely recompiles the selected sources rather than reusing the benchmark objects. The selected-dependency receipt is retained in its output/private capsule inputs. The root fixture fixes `DEVELOPER_DIR` to the reviewed Xcode, verifies SDK27.2 and limits build jobs to two. A checked-C-ABI dependency is required; an unmodified canonical DS4 source tree cannot satisfy the new checked engine/session destructor symbols. These are declared source/build receipts, not installed/native/all-writer provenance.

### Private source-built MLX composition

The shared-event source check optionally retains its restored library, matching source-built JACCL dependency and metallib as data-only development inputs:

```sh
node scripts/check-platform-mlx-metal.mjs --isolated --source /ABS/REVIEWED_MLX --cmake /ABS/PINNED_CMAKE --json-source /ABS/PINNED_JSON --fmt-source /ABS/PINNED_FMT --metal-cpp-zip /ABS/PINNED_ARCHIVE --developer-dir /Applications/Xcode.app/Contents/Developer --shared-events --review-output /ABS/PRIVATE_PARENT/NEW_SDK
node scripts/check-platform-native-fixture.mjs --source /ABS/PRIVATE_NATIVE --zig /ABS/PINNED_ZIG --webp-source /ABS/PINNED_WEBP --metal-cpp-zip /ABS/PINNED_ARCHIVE --ds4-build /ABS/FRESH_DS4_BUILD/candidate.json --ds4-sha256 EXACT_DS4_BUILD_RECEIPT_SHA --mimo-source /ABS/REVIEWED_MIMO --mlx-dependency /ABS/NEW_SDK/candidate.json --mlx-sha256 EXACT_SDK_RECEIPT_SHA --mlx-source /ABS/REVIEWED_MLX --review-output /ABS/PRIVATE_PARENT/NEW_CAPSULE
```

Only SDK27.0/Metal32023.921 and SDK27.2/Metal32023.922 are accepted. Retained review builds include the genuine Safetensors loader and verify a CPU scalar roundtrip; GGUF remains disabled in this narrowly scoped development library. The strict reader accepts only canonical, bounded, zero-authority metadata and the exact reviewed seven-path source patch/dependency identities. It rejects missing/extra/changed files, changed header/source, forged authority and unsupported compiler pairing. The native fixture retains the original installed/staged inputs, selects source libraries only in its private generated build and review capsule, and binds their identities separately from the installed-bundle bracket. A private C++ initializer calls the genuine source metadata-enablement API before main; late adoption exits78. It never loads a model or grants all-client/terminal/native lifecycle authority. Real-model checks use a fresh finite one-use plan under the standing inference authorization above; generated text stays out of logs. No distributed/RDMA operation or native installation is part of this flow.

The same source-model runner optionally accepts the fixed suffix `--scenario same-model-pair` on **all three** plan/check/run commands. Its printed commands include that suffix. This case makes exactly two same-ID attempts with independent opaque request correlations and a server concurrency of2; all other time/memory/context/output bounds remain unchanged. Readonly A/B/A lineage samples use absolute500ms query deadlines and prove retained source ownership only. They do not grant GPU terminality, all-client coverage or a model/job/lifecycle lease. Failed or missing metadata remains unknown; successful new responses never clear earlier independent uncertainty.

New source-composed capsules may declare `source_component_diagnostics:true`. The runner then samples authenticated loopback `/v1/fios/source-components` before/during/after the request. The actual X-MLX-LAN tunnel marker is rejected. Optional provider absence stays unavailable/unknown; only a compiled private initializer can register the genuine renderer once. The view has unknown coverage and no authority even with agreeing epochs and zero counters. SDK uncertainty is reported and retained independently of successful HTTP/SSE responses. These getters neither initialize/synchronize a backend nor issue/release native holds; their counts do not cover all contexts, arrays, media or other backends.

The page-in command compiles the actual complete C module against a verified154-input build and genuine linked objects. Sixteen bounded private cases use empty ranges, real pthread creation/joins and software EIO only after real joins: selected/layer, single/parallel, partial create,64-job exhaustion, a worker held beyond its original caller's stack frame, foreign/stale-owner refusal, creator-thread churn and explicit non-wrapping owner/job counter boundaries. The private scheduling checkpoint changes no model bytes and opens no model, network or RDMA connection. Heap job/range/worker vectors stay anchored on uncertain retirement; parent-close refusal has a separate source-mock guard-omission witness. Creator and job IDs are non-reusable within this local registry; the test receipt distinguishes observed allocator reuse from stale-copy refusal. This does not establish cross-backend creator coverage, native deadlines, all-writer/GPU or admission authority.

### Isolated owned-container removal check

```sh
node scripts/check-platform-sandbox-removal.mjs --isolated --base sha256:EXACT_REVIEWED_CACHED_DEVELOPMENT_IMAGE
```

This explicit one-shot command checks the existing Running OrbStack instance and pinned local CLI, builds a finite no-model hold image without network/pulls, and uses the actual Swift adapter with512MiB/1CPU/64PID/network-none/readonly/cap-drop/no-new-privileges limits. It verifies running/malformed refusal in separate fake-CLI tests, actual daemon plain-rm running refusal, a TERM-ignoring owned process receiving10s stop grace, then plain full-ID removal and a successful exact-ID absence query within60s. It also rejects default zero from an actually unstarted container and verifies a separate fixed fast invocation's genuine zero exit using bounded completion timestamps. A lost CLI stop reply is retained as uncertain until fresh owned-state/absence observations. The source/compiler/binary receipt covers declared runtime/fixture inputs only. The private image stays unapproved; failure retains exact identity/state without automatic cleanup. No native model/service/VM activation or installed acceptance follows.
