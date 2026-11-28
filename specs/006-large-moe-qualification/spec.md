# Feature specification · Large MoE on the two Studios

**Feature** `006-large-moe-qualification` · **Created** 2026-11-27 · **Status** Implemented and hardware-qualified

An operator wants a large mixture-of-experts language model for private coding and campaign writing. A user should be able to select a qualified model knowing what workload it supports. The two Studios supply the model memory. The Mini coordinates requests, qualification and publication. [Roadmap](../roadmap.md#large-moe-on-the-studio-pair)

## Clarifications

### Session 2026-11-27

- Q: Which machines may execute a large MoE? → A: Only the two Studios together. The Mini manages the cluster and never participates in clustered inference. This applies to evaluation, serving, retries and recovery, including candidates that might fit on one Studio.

## User Scenarios & Testing

### US1 · Decide whether a candidate can be tried (P1)

An admin compares a preferred GLM conversion and a lower-memory Qwen alternative before transferring weights. This avoids expensive or unsafe attempts and lets the operator see exactly why an otherwise promising model was declined.

**Independent test.** Given a candidate whose estimated total fits the pair but whose heavier partition exceeds one host's safe budget, the admin sees that host's refusal and no weights are staged. Given one busy or stale host, a previously eligible trial cannot start using another host.

### US2 · Qualify the actual model under load (P1)

An admin runs a bounded workload while both Studios report their own measurements. The evidence must establish usable coding and writing quality, memory margin, response time, transport and fault recovery for the exact build.

**Independent test.** Given an eligible unpublished candidate and both Studios idle, run full-context generation, then interrupt a separate attempt. A good run has two reconciled receipts and a result for every quality gate. A missing sample, failed check or unresolved cleanup keeps the candidate unavailable. Trial prompts and generated text never enter user history.

### US3 · Use and withdraw the qualified model (P2)

A user chooses the large model in private chat. The admin can see its validated limits, withdraw a bad release immediately and return to a previous qualified revision.

**Independent test.** Given a qualified profile, send a coding request and reopen the answer from history. With one Studio unavailable the request can wait within its deadline or be cancelled. An interrupted turn produces no partial answer or duplicate usage. A regular user attempting to change the selected revision is denied.

### Edge cases

Cover changing available memory during load, asymmetric partitions, a loader temporarily materializing unsharded weights, swap growth, stale/replayed samples, link loss while the management route stays up, one rank returning late, two clients racing, an unavailable publication checker, and neither candidate qualifying.

## Requirements

### Functional requirements

- **FR-001** Restrict all large-MoE execution to the two distinct enrolled Studio slots together. Reserve both or neither. Deny single-host, Mini, duplicate-rank and substitute placement even if memory would permit it.
- **FR-002** Require the signed-off comparable-model Spec 005 hardware result for the current pair before staging large weights. After the Mini rehearsal and the 005 gate, the admin may authorize a bounded two-Studio architecture probe from reviewed metadata and per-host budgets. Full-weight acquisition requires a separate decision based on that probe passing and cleaning up, the candidate’s pinned weights, runtime, license, tokenizer, partition mapping, current disk space and per-host load budgets. Record the stage and reason for every refusal, including estimated single-host fit without executing it.
- **FR-003** Admit one active generation across the pair with at most 8,192 total tokens including at most 1,024 generated. Enforce a 32 GiB available-memory floor on **each** host during load, prefill and decode, normal pressure and no growth in used swap from the idle pretrial baseline. Stop both ranks on a violation or missing evidence.
- **FR-004** Require two authenticated, attempt-bound records of actual model traffic over the dedicated RDMA link. Reject partial, replayed, TCP-only, mixed or setup-only evidence. Verify the same rule during serving.
- **FR-005** Before evaluating a candidate, freeze the input set, scoring rubric, hardware limits and sampling settings. Measure launch to first model text on the reporting Studio. Measure submission to the first visible, policy-approved complete answer in the browser. Correlate both observations to the same hardware-backed fixture turn for each timed case. Record decode rate, per-host peak and available memory, swap, and coding and campaign-writing outcomes. Preserve report provenance and sanitized failure reasons.
- **FR-006** Only an admin may initiate trials, record reviewer verdicts, promote, withdraw or roll back. A trial cannot publish a conversation, bill usage or activate a model. Require real, passing and cleaned evidence for the exact profile before separate promotion. Invalidate on material changes to the weights, runtime, placement, operating system, policy or qualified limits.
- **FR-007** Offer a separate large-model choice in private chat/coding with its limits and availability. Reuse conversation ownership, cancellation, retention/deletion, content-based titles, publication checks for all roles, and one reporter's usage settlement.
- **FR-008** Fence on cancellation, pressure, loss of either rank or link, deadline, withdrawal or controller restart. Keep each affected Studio unavailable until its own cleanup and fresh capacity are proven. Support revision-checked rollback to a still-qualified predecessor.
- **FR-009** Validate control paths and synthetic faults on the Mini before Studio changes. Keep inference native on the Studios and preserve the service separation. Clean only trial-owned resources, preserve preview and history, and expose sanitized measurements to the admin.

### Key entities

Candidate profile, preflight decision, two-rank trial, per-host phase measurements, evaluation suite, qualification report and published model choice.

## Success Criteria

- **SC-001** Across the invalid-placement matrix and 100 competing submissions, zero large-model executions occur outside the exact Studio pair, zero partial reservations and at most one active generation.
- **SC-002** A releasable profile passes one cold and five consecutive warm runs plus a full-budget case reaching the 1,024 output limit within 8,192 total tokens. Every phase on each host meets FR-003. For every timed short turn require both the native first-text limit and the browser’s approved-answer limit. For the full-budget turn require the minimum native decode rate and the browser completion limit. Missing or mismatched observations fail the case.
- **SC-003** All fixed coding checks and publication controls pass. Four held-out campaign briefs each score at least 4/5 on each of canon fidelity, narrative clarity and session usability in blinded review against anchored criteria.
- **SC-004** All negative transport/evidence cases prevent publication. Each reachable rank stops within the existing 15-second lease plus two-second poll after a fault. Zero fenced answers or duplicate settlements appear.
- **SC-005** Before promotion, an isolated fixture principal completes the required timed private web turns using the exact candidate and actual publication checker. Denied role, withdrawal, restore, rollback and cleanup rehearsals preserve history, other aliases and preview health. Zero seeded private text strings appear in telemetry.
- **SC-006** Both primary candidates have a documented disposition (including deferred with reason after first success). At least one fully qualified real pair result is required to call delivery successful. If all fail, report the limiting evidence and leave the choice unavailable.

## Assumptions and boundaries

The present bootstrap has one local admin. Role-denial tests use a synthetic user. An independently serving small Mini model is outside this placement rule. This milestone follows comparable-model hardware qualification and covers private text generation only. Cluster operations (T009), live search, Deep Research, images, coding harness integration and public identity retain their roadmap scopes.
