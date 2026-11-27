# Core job ledger and scheduling

**Feature** · 003 · 2026-11-27 · [Foundation roadmap T006](../001-platform-foundation/tasks.md#following-milestones)

## User Scenarios & Testing

### US1 · Submit and track a job (P1)

The local operator submits a bounded request and can look up its ID, owner, requested resources, state, attempts, usage and ordered history. A disconnected client can safely repeat a submission.

**Independent test.** Submit twice with the same owner, key and request. Both responses identify the same durable job. Changing the request under that key returns a conflict. A full queue rejects a new job with retry guidance. An unauthorized actor can neither inspect nor change another owner's job.

### US2 · Dispatch within observed capacity (P1)

The operator can tell why a job is queued. A worker with fresh, authenticated capacity evidence can claim an eligible job. A paired job reserves both Studios together and begins only once both participants are ready.

**Independent test.** Submit two jobs competing for one slot while both workers request work concurrently. Exactly one job may own that slot. With one worker stale, a paired job stays queued with neither slot reserved. Configured RAM and a physical-memory heartbeat alone give zero dispatchable capacity.

### US3 · Cancel, recover and account for work (P2)

The operator can cancel queued or running work and recover the ledger after interruption. The operator can distinguish a cancellation request from confirmed resource release. A disconnected worker cannot revive an obsolete attempt or publish its results.

**Independent test.** Stop the core after a lease grant. Restart it with a delayed completion in flight. The old completion fails, reservations remain held until cleanup is confirmed, and a duplicate accepted completion never doubles usage. A warm idle model can unload only when no job has claimed its memory.

### Edge cases

Cover lost responses after commit, partial readiness or failure of a pair, revoked or replaced worker identity, lease expiry during execution, unknown usage, cancellation racing completion, and a crash during cleanup. If cleanup evidence never arrives, the affected slot remains unavailable with a visible reason.

## Requirements

### Functional requirements

- **FR-001** Derive ownership and permissions from the caller. Support local operator submit, inspect and cancel. A worker can act only for its own current assignment. Administrative actions require the admin role.
- **FR-002** Persist a validated workload profile, resource class, owner, limits and optional Project reference. Within the current ledger incarnation, identical owner-scoped submission retries return the original job. Conflicting reuse fails. Ordinary restarts preserve this identity. Restoring a snapshot invalidates every prior submission envelope, including keys absent from the snapshot.
- **FR-003** Bound queued jobs per owner and globally, provide retry guidance at saturation and expose a bounded ordered history with the current waiting or terminal reason.
- **FR-004** Admit only against current authenticated capacity after host reserves, resident memory and workload demand are accounted for. Prefer an eligible warm host. Allow one active job per Studio and atomic all-or-none placement for pairs.
- **FR-005** Require a current assignment for readiness, start, renewal and completion. Fence expired or superseded attempts. A pair succeeds only after both participants finish the same attempt successfully.
- **FR-006** Support cancellation, expiry and restart recovery. Persist uncertain reservations until each affected worker proves the old work stopped. Show unresolved cleanup to the operator. After snapshot restore, prevent automatic dispatch of all restored nonterminal jobs, including jobs shown as queued that may since have run.
- **FR-007** Record authoritative input/output token counts once per attempt when supplied, preserve unknown values and distinguish estimates from measured usage. Label each input and output count as measured, estimated or unknown. Only measured counts contribute to measured totals or monetary charges. Display monetary cost only with an explicit priced unit, currency and tariff version.
- **FR-008** Serialize idle unloading with placement and remeasure capacity after unloading. A delayed idle action cannot unload a newly claimed model.
- **FR-009** Qualify scheduling with synthetic native workers on fios-core and preserve the existing enrollment and dashboard contracts. Clean up run-owned resources and verify preview health.

### Key entities

Job, workload profile, attempt, participant lease, reservation, worker capacity report, usage record and job event.

## Success Criteria

- **SC-001** Concurrent duplicate submissions and a retry after restart produce exactly one job and one creation event. A denied or over-limit new request creates zero jobs. After restoring an older snapshot and reopening admission, a pre-restore retry creates zero jobs, grants and usage, even if its key disappeared in the restore.
- **SC-002** Across 100 synchronized competing-claim trials, observe zero overlapping reservations or partial pair grants. Stale or missing capacity always prevents new placement.
- **SC-003** In controlled-clock tests, expiry, cancellation, restart and late messages produce zero unauthorized results, double charges or early releases. A job with unknown runtime outcome never re-executes automatically. A mixed measured/estimated completion and its duplicate retain both labels, with zero estimated tokens included in measured totals or charges.
- **SC-004** Replaying an idle expiry during admission produces either an exclusive unload or a job reservation. A worker returns to admission only with fresh post-cleanup evidence.
- **SC-005** On fios-core, two synthetic workers carry a job through submission, execution and completion. Demonstrate pair failure, backpressure, restart, cancellation and teardown while the existing preview stays healthy.

## Assumptions

T006 delivers scheduling semantics and a deterministic fake workload. Model execution, real distributed inference, real tariffs, public authentication and a browser submission UI belong to later milestones. The local operator uses the native CLI. Spec 2's real Studio rollout remains separately gated.

T009 adds host-local supervision of dependencies such as OrbStack. After a dependency recovers, dispatch still requires fresh readiness and capacity evidence and resolution of any outstanding cleanup holds. See the [operations roadmap](../001-platform-foundation/tasks.md#following-milestones).

## Clarifications · 2026-11-27

The roadmap and enrollment contract resolve three scope questions. T006 exercises paired reservations with two fake participants on the Mini. T008 qualifies actual paired inference. Spec 2's current reports contain physical memory, CPU count and load, so an authenticated worker must supply a separate capacity observation to become eligible. Finally, the roadmap requires fencing and reconciliation after timeout. An ambiguous execution remains held until the worker confirms cleanup. Ordinary restart preserves submission retries. After a snapshot restore the operator can inspect surviving jobs by ID. Starting work again requires an explicit new submission against the restored ledger.
