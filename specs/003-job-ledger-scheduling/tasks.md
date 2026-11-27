# Tasks for Spec 3 · Core job ledger and scheduling

T001–T021 completed on fios-core. IDs below are local to this feature. See the [plan](plan.md), [worker and operator contracts](contracts/dispatch.md) and [acceptance guide](quickstart.md).

## Phase 1 · Setup

- [x] T001 Capture the fios-core preview baseline and existing enrollment checks in `specs/003-job-ledger-scheduling/tasks.md`. Assign run-owned ports, paths, jobs and cleanup handlers in `tests/fixtures/scheduling_worker.py`. FR-009, SC-005.

## Phase 2 · Foundations

- [x] T002 [P] Write storage contract tests in `tests/test_job_ledger.py` for private initialization, unique constraints, atomic rollback, bounded lock failure, incompatible schema and separate operation of enrollment on job-store failure. FR-002, FR-006.
- [x] T003 [P] Build the controlled-time, fixed-profile fake executor and capability fixtures in `tests/fixtures/scheduling_worker.py`. Support pause at ready/start/finish, simulated resident revisions, lost replies, interrupted execution and explicit cleanup. FR-004–FR-009.
- [x] T004 Implement the additive, private job schema, fixed-revision profile validation, transactions and indexes in `src/backend/job_ledger.py`. Implement [data-model.md](data-model.md) fields `Ledger.incarnation`, `Job.id`, `Job.owner`, `Job.request_key`, `Job.intent`, `Job.state` and `Event.position`. FR-001–FR-003.

## Phase 3 · US1 Submit and track (P1)

**Independent acceptance.** The native operator submits and reads one durable job, retries after restart, and encounters an attributable refusal when the queue is full.

- [x] T005 [P] [US1] Add concurrent submission, owner isolation, stable incarnation and deadline on ordinary restart, missing/stale submission incarnation, full queue, ordered pagination and retry-after-restart cases to `tests/test_job_ledger.py`. FR-001–FR-003, SC-001.
- [x] T006 [P] [US1] Exercise OS-peer checks, denied worker calls and typed request limits and a lost reply across client restart through the local CLI in `tests/macos/verify_scheduling.py`. FR-001, FR-002.
- [x] T007 [US1] Compare the required incarnation in the submission transaction before any lookup or mutation. Implement idempotency lookup before admission caps, canonical intent comparison, initial events, scoped list/get/history and error reasons in `src/backend/job_ledger.py`. Bound retained jobs and event volume while preserving active holds. FR-002, FR-003, SC-001.
- [x] T008 [US1] Connect opt-in initialization, job-context, submit, inspect, events and list operations to the native CLI/socket in `src/backend/enroll.py` and `src/backend/job_protocol.py`. Derive principal and action from the authenticated local peer. Preserve the original submission envelope for retries and surface ledger_changed without automatic resubmission. FR-001–FR-003, FR-009.

## Phase 4 · US2 Dispatch within capacity (P1)

**Independent acceptance.** Two fake peers on the Mini request work concurrently. One slot has at most one active reservation and paired preparation is all-or-none.

- [x] T009 [P] [US2] Add 100 competing-claim trials, pair readiness, injected commit failure, warm preference, stale capacity and precise headroom accounting in `tests/test_job_scheduler.py`. FR-004, FR-005, SC-002.
- [x] T010 [P] [US2] Add bounded wire tests in `tests/macos/verify_scheduling.py` for session replacement, legacy heartbeats, cross-slot grants, stale/replayed capacity and lost poll responses. FR-001, FR-004, FR-005, FR-009.
- [x] T011 [US2] Add authenticated capacity intake and current-session validation in `src/backend/job_protocol.py`, `src/backend/heartbeat.py` and `src/backend/enrollment.py`. Enforce opt-in synthetic loopback dispatch, independent traffic budgets and the existing private transport. Implement [data-model.md](data-model.md) field `Capacity.evidence`. FR-001, FR-004, FR-009.
- [x] T012 [US2] Implement admission and per-slot reservations in `src/backend/scheduler.py` and `src/backend/job_ledger.py`. Implement [data-model.md](data-model.md) fields `Attempt.generation`, `Reservation.slot` and `Reservation.grant`. Serialize heartbeat eligibility, memory checks, pairing, job state and grant/event persistence. FR-004, FR-005, SC-002.
- [x] T013 [US2] Implement poll, idempotent ready/start barrier and lease renewal in `src/backend/job_protocol.py` and `src/backend/scheduler.py`. Exercise the real TLS path with both fake peers in `tests/fixtures/scheduling_worker.py`. FR-004, FR-005, SC-002.

## Phase 5 · US3 Cancel, recover and account (P2)

**Independent acceptance.** A restart fences issued work, stale results cannot settle or release it, and cleanup unlocks a subsequent job. Metering deduplicates a replay.

- [x] T014 [P] [US3] Test cancel/finish races, partial pair failure, exact deadline, restart, revocation, lost cleanup acknowledgment, idle TTL versus dispatch, and stale challenge responses in `tests/test_job_scheduler.py`. FR-005, FR-006, FR-008, SC-003, SC-004.
- [x] T015 [P] [US3] Test missing vs zero counts, partial reports, paired reporting authority, duplicate and conflicting settlement, late generation, tariff units and unknown prices. Include mixed measured/estimated directions, invalid tags, estimated zero, unknown vs measured zero, partial measured totals, and an equal-value replay with a changed tag in `tests/test_job_scheduler.py`. FR-007, SC-003.
- [x] T016 [US3] Implement cancellation, expiry, stopping, startup fencing, durable cleanup holds and challenge-based reconciliation in `src/backend/scheduler.py`, `src/backend/job_protocol.py` and `src/backend/enroll.py`. Never recycle an uncertain allocation. FR-005, FR-006, SC-003.
- [x] T017 [US3] Implement atomic participant completion, designated metering, terminal receipts and per-direction measured/estimated/unknown validation and display, partial measured totals and measured-only pricing in `src/backend/job_ledger.py` and `src/backend/job_protocol.py`. Implement [data-model.md](data-model.md) field `Usage.counts`. FR-005, FR-007, SC-003.
- [x] T018 [US3] Implement exclusive idle unload, generation checks and fresh post-cleanup measurement in `src/backend/scheduler.py` and `tests/fixtures/scheduling_worker.py`. Verify worker self-stop and unload refusal after a new claim. FR-006, FR-008, SC-004.

## Phase 6 · Integrated qualification

- [x] T019 Add portable scheduling tests to `Makefile` and `.github/workflows/ci.yml`, including Spec 3 prerequisites and regression checks for Specs 1 and 2. Add a native `make scheduling-acceptance` runner in `tests/macos/verify_scheduling.py` for an isolated core, two workers, and teardown on interruption. FR-009, SC-001–SC-005.
- [x] T020 Implement offline staged restore with transactional incarnation rotation, invalidation of nonterminal jobs and durable quarantine in `src/backend/job_ledger.py` and `src/backend/enroll.py`. Rehearse disabling scheduling, restore interruption and repeated restores. After reconciliation, verify that restored queued work stays fenced and retries with both surviving and lost keys create no work. Test explicit new submission in `tests/macos/verify_scheduling.py` and pre-activation interruption in `tests/test_job_ledger.py`. Document limits, diagnostic outcomes, backup/restore and cleanup in `README.md`. FR-003, FR-006, FR-009, SC-003.
- [x] T021 Execute `make scheduling-test`, `make scheduling-acceptance` and `make check` on fios-core. Record actual outcomes, digest, coverage of all five success criteria, recovery and scoped cleanup in `specs/003-job-ledger-scheduling/tasks.md`. FR-009, SC-005.

## Dependencies and delivery

T001 precedes the independent test/store-fixture work T002 and T003. T004 follows T002. Complete foundations before US1. T005/T006, T009/T010 and T014/T015 can each be authored in parallel within their respective story. US1 ends at T008 and is the minimum operator-visible slice. US2 requires US1. US3 requires US2. Implement the numbered production tasks within each story in order. T019 and T020 follow US3. Both precede T021. A green CI run supplies portable verification, and T021 supplies native qualification. The separately gated Spec 2 rollout can proceed independently.

## Verification · 2026-11-27

- Baseline `9935ad7`, with the local enrollment preview responding before and after qualification. The approved execution path used synthetic loopback mode. Scheduler tests and native fixtures used private, disposable ledgers and identities.
- `make check` passed 37 tests and Compose validation. `make scheduling-test` passed 13 tests, including 100 synchronized contention trials, an injected paired-reservation rollback, submission conflicts, aging capacity, restart and cancellation fencing, revocation, and measured-only accounting.
- `make scheduling-acceptance` passed on fios-core for backend source SHA-256 `2b4701e2b2d34d3654957577a8117bad848751c3c43a914712b5d83f30da5a9d`. The operator CLI and two worker processes exercised mutual TLS, the pair start barrier, backpressure, recovery after a core crash, worker self-stop and an older snapshot restore. After the first restored slot cleared its hold, the scheduler still denied dispatch until the other slot reconciled. Both surviving and absent pre-restore keys were rejected.
- The existing Spec 2 acceptance run passed, including the 15-test Linux container and launchd recovery. Normal and SIGTERM scheduler teardown removed the child processes and temporary state. OrbStack retained the existing healthy preview and its image.
- Actual Studio rollout remains part of the separately gated enrollment work. Native dependency monitoring and restart, including OrbStack recovery, are scheduled under T009 in the foundation roadmap.
