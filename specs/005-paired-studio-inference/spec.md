# Feature Specification · Paired Studio inference

**Feature 005 · 2026-11-27 · Roadmap T008**

A private chat user can choose a qualified model that runs one generation across the two M3 Ultra Studios over Thunderbolt 5 RDMA. The Mini owns admission, publication and history. The operator can tell whether both ranks ran, what transport carried the work and when each Studio is safe to reuse.

## Clarifications

### Session 2026-11-27

- Q: Must the first release demonstrate a model that exceeds one Studio’s safe budget? → A: Qualify with a comparable model first. Larger models can follow. The first promoted profile must complete the same workload safely on one Studio and on the pair using the same model, pack and settings.

## User Scenarios & Testing

### User Story 1 — Run a paired model (P1)

A user chooses a paired profile in the existing private chat. The result is one policy-checked assistant turn. The Mini and single-Studio choices remain independently usable.

**Independent test.** Submit the same request twice with its original key against two simulated workers on the Mini. Observe one job and one answer. Use the hardware qualification in US3 before enabling a real profile.

- Given a qualified profile and two available Studios, when the user submits, both ranks must join the same generation before any answer can be published.
- Given a busy Studio, the request waits within its original deadline. It cannot consume the other Studio alone or preempt an active job.
- Given an unsupported or withdrawn profile, the interface explains the unavailable choice and preserves the conversation.

### User Story 2 — Recover from interruption (P1)

An operator sees the affected pair and the reason for degradation. A user can stop their generation. Failure, cancellation and restart leave a verifiable path back to service.

**Independent test.** Interrupt either rank during startup and generation. Reconnect with a stale grant. Verify the attempt is fenced, the user receives one bounded outcome, and each host proves cleanup before accepting work again.

- When the cable fails or one member disappears, stop its surviving peer and suppress pending output. Missing evidence leaves the affected host unavailable.
- When the control plane restarts mid-generation, recover the durable holds and reconcile the old generation. A replayed completion cannot publish or charge twice.

### User Story 3 — Qualify and operate a profile (P2)

An admin evaluates the three candidate runtimes on the actual link, compares against a single Studio and enables a profile with reproducible evidence. Users can inspect availability and cannot change placement, artifacts or qualification state.

**Independent test.** Present a two-host run over TCP and a run with mismatched weights. Both fail qualification. A passing hardware report identifies the two distinct ranks, confirmed transport, per-host headroom and fixed-workload results.

Given a candidate with its alias disabled, the local admin can run a fixed qualification workload. A busy or stale Studio results in zero trial grants. While the trial owns the pair, competing work waits. A trial can produce a qualification report only. Serving a user requires a separate promotion.

### Edge cases

Test one stale capacity sample, conflicting device maps, pressure rising during preparation, partial launch, delayed second-rank success, asymmetric loss, disconnection during publication and an old rank returning after re-enrollment. If the baseline exceeds one Studio’s safe budget, record the refusal and choose a comparable model for the first release.

## Requirements

### Functional requirements

- **FR-001** Offer an explicitly identifiable paired profile through private chat only after qualification. Preserve existing model choices, local history, owner checks and publication policy.
- **FR-002** Admit both enrolled Studios atomically against fresh, session-bound observations, individual memory budgets and current holds. Bound queueing by the existing job deadline.
- **FR-003** Start only the pinned native rank assignments for one attempt after both workers acknowledge readiness. Require positive evidence of distinct ranks, matching manifests and actual RDMA for this generation before accepting its result.
- **FR-004** Accept output and usage once per attempt from the designated reporter, conditional on both ranks succeeding. Preserve unknown usage and suppress unapproved, partial or late text.
- **FR-005** Fence the group on cancellation, rank or link loss, lease expiry, profile withdrawal or restart. Each host stops its own processes on loss of authority and proves quiescence with a fresh capacity sample before reuse.
- **FR-006** Show queued, preparing, running, degraded, cleaning and available states as applicable, plus a bounded reason. Show rank, host, freshness and transport evidence to the admin. Keep private text, credentials and raw internal addresses out of operational reports.
- **FR-007** Restrict qualification, promotion and withdrawal to the local admin. Bind worker actions to enrolled identity, slot, session and grant. Arbitrary browser or model requests cannot select executables, downloads or peers.
- **FR-008** Compare MLX-Serve, EXO and native distributed MLX against a recorded workload on the actual pair. Record compatible model format, runtime revision, per-rank placement, quality, time to first answer, decode throughput, peak memory and recovery. Give a reproducible reason for any candidate that cannot safely reach inference.
- **FR-009** Qualify management, native execution boundaries, synthetic pair operation and recovery on fios-core before Studio builds or installations. Keep one management container per host, inference native, the web UI separate from persistent data services, and existing service ownership intact during cleanup.
- **FR-010** Keep the paired profile disabled until hardware qualification passes. Invalidate evidence after material profile, runtime, OS or topology change. Support withdrawal and rollback without changing the existing single-host aliases or deleting history.
- **FR-011** Allow the local admin to reserve an unpublished candidate for a bounded fixture trial. Use the same exclusive slots, readiness barrier, lease expiry and cleanup as serving. Deny trial submission from the browser and machine interfaces. Trial grants cannot read or publish conversations, settle user usage or activate an alias.

### Key entities

Paired profile, qualification report, job attempt, two per-slot grants, rank observations and cleanup receipts. All placement decisions belong to the Mini.

## Success Criteria

### Measurable outcomes

- **SC-001** In contention and duplicate-submission tests, no partial admission, duplicate job, duplicate answer or duplicate usage settlement occurs.
- **SC-002** Every accepted hardware generation provides two distinct rank receipts, verified RDMA evidence and a passing publication decision. A missing receipt, transport fallback or mismatch produces zero published answers.
- **SC-003** Under an injected disconnect or lease loss, a reachable rank stops by lease expiry plus one worker polling interval. A disconnected host receives zero capacity credit until verified clean.
- **SC-004** All three candidates receive a documented disposition. At least one passes one cold and five consecutive warm paired fixed-workload runs, a full-budget run and both rank-loss and link-loss recovery before promotion. Require a passing one-Studio baseline with the same model, pack, workload and settings before first promotion.
- **SC-005** The Mini rehearsal and hardware trial preserve the existing preview, history and model aliases. A regular user is denied every admin operation. Operational output contains none of the seeded private test strings.
- **SC-006** With the alias disabled, an authorized paired trial acquires both holds or none, including when it races a chat job. Cancellation or restart fences both grants. Denied submissions and replayed trial receipts produce zero chat turns, user usage or promotions.
- **SC-007** For each qualifying adapter the same verifier accepts matching evidence of RDMA model traffic from both ranks during generation and rejects a TCP-only control, setup-only traffic, mixed/fallback payload transport and receipts replayed from another attempt.

## Assumptions

Initial placement is the fixed edge-a/edge-b pair. Available memory is measured separately on each Studio. No throughput gain is assumed. A larger thinking model can later use this placement through the Deep Research milestone after live search and Studio operations. This feature delivers the inference path only.
