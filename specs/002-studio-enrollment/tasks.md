# Implementation tasks for authenticated Studio enrollment

These IDs are local to Spec 2. Together they deliver foundation roadmap milestone T005. T001–T021 are complete on fios-core. T022–T023 await approval of the live bindings and deployment. See the [plan](plan.md), [wire and operator interfaces](contracts/interfaces.md) and [validation guide](quickstart.md).

## Phase 1 · Setup on fios-core

- [x] T001 Record the foundation baseline, interpreter and TLS/SQLite/OpenSSL versions and preview health in `specs/002-studio-enrollment/tasks.md`. Reserve isolated output paths, unique launchd labels and ephemeral test ports. Start from the existing `make check` gate.
- [x] T002 Create a temporary, test-only CA and leaf fixture builder in `tests/enrollment_fixtures.py`. Generate valid, unknown, expired, wrong-purpose and wrong-name credentials locally. Register resource cleanup even on setup failure and never commit keys.

## Phase 2 · Shared prerequisites

- [x] T003 [P] Add local storage and failure tests, then implement explicit first-use initialization, transactions, unique slot/pin constraints, permanent retirement, bounded audit retention and fail-closed store errors in `tests/test_enrollment_store.py` and `src/backend/enrollment.py`. Verify that startup with a missing ledger fails without creating it. Implement [data-model.md](data-model.md) fields `Binding.node`, `Binding.machine`, `Binding.pin` and `Binding.state`.
- [x] T004 [P] Test and implement worker and core TLS contexts, explicit trust stores, leaf purpose and SAN checks, fixed management-address policy and isolated test configuration in `tests/test_studio_enrollment.py` and `src/backend/machine_tls.py`. Assert a false core receives zero heartbeat payload bytes and a failed trust check never falls back to plaintext.

## Phase 3 · US1 Enroll an approved Studio (P1, first demonstrable slice)

**Independent check.** Approve one synthetic worker, see it reporting via the local dashboard, then show an unknown, expired or cross-slot credential leaves its accepted sample and freshness intact.

- [x] T005 [P] [US1] Add failing real-TLS and local CLI acceptance tests in `tests/test_studio_enrollment.py` for approve, conflicts, wrong operator, two slots sharing an identity, unauthorized certificates, cross-slot claims, successful first report, and forbidden worker/admin routes.
- [x] T006 [P] [US1] Add dashboard contract tests in `tests/test_studio_enrollment.py` for first reporting worker, Not enrolled and Awaiting sample labels, local authorization, and the Mini still usable with the native enrollment service offline.
- [x] T007 [US1] Wire the offline `init --state-dir PATH` entry point and test refusal to initialize an existing path in `tests/test_studio_enrollment.py`. Implement owner-only Unix socket access, OS peer identity to admin role, explicit approve/status and sanitized outcomes in `src/backend/enroll.py` and `src/backend/enrollment.py`. Validate public leaf, machine SAN and operator-selected pin on approval. Refuse stale expected state and ambiguous assignments.
- [x] T008 [US1] Implement the private session and heartbeat routes with atomic authorization/acceptance in `src/backend/heartbeat.py` and `src/backend/enrollment.py`. Implement [data-model.md](data-model.md) fields `Session.id`, `Session.highest`, `Heartbeat.version`, `Heartbeat.node`, `Heartbeat.session`, `Heartbeat.sequence`, `Heartbeat.sampled_at`, `Heartbeat.memory_bytes`, `Heartbeat.logical_cpus`, `Heartbeat.load_1m` and `Observation.deadline`. Enforce the contract's size, framing and timeout limits.
- [x] T009 [US1] Add outbound authenticated session creation and first native heartbeat in `src/backend/host_agent.py` and `src/backend/worker.py`, reusing the macOS sampler and preserving the existing Mini CLI. Verify one accepted real-TLS report with a synthetic measurement via the normal worker entry point.
- [x] T010 [US1] Connect the native read-only snapshot to the local dashboard in `src/backend/heartbeat.py`, `src/backend/core.py`, `src/backend/studio_inventory.py` and `src/frontend/dashboard.py`. Preserve the Mini path and v1 response shape, add Studio enrollment fields and labels, and ignore legacy Studio files. Adjust only the intentionally changed Studio display expectations in `tests/test_foundation.py`.

## Phase 4 · US2 See current worker telemetry (P1)

**Independent check.** Feed both synthetic workers, stop one, advance a controlled clock across the 30-second deadline and confirm only its row goes stale. Compare the entire last-good observation and deadline before and after a rejected update.

- [x] T011 [P] [US2] Test two-worker correlation, duplicate and regressing sequences, gaps, retired sessions, malformed and oversized messages, clock limits, future-time clamping and expiry through the collector entry point in `tests/test_studio_enrollment.py`. Include disconnect after acceptance, missing reply and delayed retry.
- [x] T012 [P] [US2] Exercise HTTP and rendered inventory in `tests/test_studio_enrollment.py` with controlled clocks, stale values retained, accurate reporting counts, forged local Studio files ignored, and malformed or unavailable native snapshot handled while the Mini remains readable.
- [x] T013 [US2] Complete per-slot sampling cadence, bounded retry/jitter, discarded offline samples and sequence advancement after lost replies in `src/backend/worker.py`, and enforce elapsed-time expiry through sleep/wake in `src/backend/enrollment.py`. Exercise timing through the worker client and the local read endpoint.
- [x] T014 [US2] Exercise and enforce overload isolation, bounded queues, deadlines, per-slot request budgets and redacted rejection counters in `src/backend/heartbeat.py` and `tests/test_studio_enrollment.py`. Verify rejected input cannot update any slot, another good peer can progress under a single worker's excess reports, and admin/inventory reads remain responsive.

## Phase 5 · US3 Recover or withdraw trust (P2)

**Independent check.** Restart the core with active and revoked slots, rotate one worker while the other keeps reporting, and restore the supervised worker after an exit. Old pins and sessions stay denied.

- [x] T015 [P] [US3] Specify lifecycle behavior in `tests/test_studio_enrollment.py`: race acceptance against rotate/revoke, failed durable commit, idempotent admin retries, retired pins after restart, explicit re-enrollment, new report required after restart, anchor rollover and emergency trust removal.
- [x] T016 [P] [US3] Add per-run user-domain supervision checks in `tests/macos/verify_supervision.py`. Capture original and replacement PID, healthy recovery time and cleanup after termination. Verify the stale interval separately with controlled elapsed time in `tests/test_studio_enrollment.py`. Verify the supervisor and workers tolerate network interruption without a restart loop.
- [x] T017 [US3] Implement durable rotate/revoke, session invalidation, expected-state checks, audit and recovery in `src/backend/enrollment.py` and `src/backend/enroll.py`. Validate core restart and reject unsafe restore or retired credentials. Confirm the unaffected worker retains its session during an individual binding change.
- [x] T018 [US3] Package foreground services with launchd templates `ops/launchd/local.fios.worker.plist` and `ops/launchd/local.fios.enrollment.plist`. Document offline issuance, owner-only paths, supported interpreter, planned two-root rollover, compromised-root recovery and per-host rollback in `README.md`. Qualify core reload and both directions of trust retirement with synthetic roots.

## Phase 6 · Qualification, cleanup and gated rollout

- [x] T019 Add `make enrollment-test` for the portable enrollment suite in `Makefile` and run it with both features' Spec Kit checks in `.github/workflows/ci.yml`. Keep the existing foundation suite and pinned CI safeguards. Provide the OpenSSL test prerequisite and native modules to the test runner without adding signer material or native management code to the UI image.
- [x] T020 Implement `make enrollment-acceptance` in `Makefile` with an isolated runner in `tests/macos/verify_enrollment.py`. Package the agent on fios-core, exercise launchd, OrbStack and two native worker processes with synthetic identities, and tear down exact run-owned artifacts on success, error and interrupt.
- [x] T021 Run Gate A on fios-core and record revision/digest, baseline and final health, launchd recovery, first/final sample times, two-slot isolation, trust lifecycle checks, and teardown evidence in `specs/002-studio-enrollment/tasks.md`. Confirm no temporary keys, jobs, containers or tags remain and the existing preview still works. A failed gate stops Studio work.
- [ ] T022 After T021 and operator approval of the live identity bindings, trust anchor, private addresses and deployment, verify the approved artifact on edge-a only. Record authorization, digest, native job health, advancing heartbeat, local Mini access and recovery/rollback outcome in `specs/002-studio-enrollment/tasks.md`.
- [ ] T023 After edge-a passes, repeat the approved rollout on edge-b and record its independent evidence and both workers' simultaneous reporting in `specs/002-studio-enrollment/tasks.md`. Verify task-owned staging cleanup on both hosts and Mini dashboard health.

## Dependencies and incremental delivery

T001 → T002 → T003/T004. After both prerequisites, US1 tests T005 and T006 can run in parallel. T007–T010 complete the first end-to-end slice. For US2, T011 and T012 cover disjoint boundaries in parallel before T013/T014. For US3, T015 and T016 can be authored in parallel on the completed telemetry path before T017/T018. T019 and T020 follow the completed stories, then T021 → T022 → T023. A portable CI run cannot satisfy T021. Partial delivery through T010 demonstrates enrollment on the Mini only.

## Evidence and resumption

### 2026-11-27 · fios-core qualification passed

- Baseline checkout `23ba003` plus this implementation. Python 3.15.2, OpenSSL 4.1.0 and SQLite 3.54.1. OrbStack context `orbstack`. The existing preview returned `ok` before and after qualification.
- `make check` passed with 24 tests, including nine foundation tests. Both features passed Spec Kit prerequisite checks. Both launchd templates passed `plutil -lint`.
- `make enrollment-acceptance` passed for native source SHA-256 `d634fc36b0496c23fd8c988507edb7e15d35fa0951253b93ab23fec981715261`. The isolated Linux container passed 15 enrollment tests. The isolated OrbStack dashboard displayed both synthetic native workers in 0.25 s. launchd replaced worker PID 12162 with 12191 and the next sampled timestamp advanced from 1795814161 to 1795814163. A worker reconnected 2.04 s after the collector was ready with its PID unchanged.
- Qualification covered the collector restart barrier, leaf rotation, revocation and denial after restart, with independent recovery for the other worker. Portable tests covered root rollover and emergency cutoff, clock boundaries, malformed and replayed traffic, state durability and an interrupted commit.
- Normal and SIGTERM teardown removed the generated identities, test ledger, staged source, launchd jobs, containers and image tags. The original preview and native sampler remained healthy.
- Next executable task is T022 after operator approval of the real Studio mappings, management route, trust anchor and live deployment. The evidence above uses synthetic credentials and the Mini's user launchd domain. System LaunchDaemon startup on either Studio remains for Gate B.
