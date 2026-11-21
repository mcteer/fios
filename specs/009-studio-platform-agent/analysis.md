# Specification analysis — 2026-10-26

**Scope**: spec, conditional plan,55-task backlog, data model, contracts, research and active constitution2.0.0/AGENTS. Two read-only analysis passes; supported document remediation occurred **between** passes under the user's explicit authorization. This file records their results afterward; analysis itself did not modify artifacts.

**Historical planning disposition**: Documentation complete with implementation HOLD under constitution2.0.0. Four document findings resolved. **Current disposition**: G1 resolved under explicitly approved constitution2.1.0/ADR0003; implementation/testing underway. G2 gates native activation/acceptance only, not independent development. See [validation.md](validation.md); no full009 acceptance or008-unblocking claim.

## Findings

| ID | Category | Severity | Location(s) | Finding / recommendation | Final state |
| --- | --- | --- | --- | --- | --- |
| G1 | Constitution alignment | CRITICAL | plan Constitution Check; spec Assumptions; active constitution§4/5 and AGENTS support/daemon rules | Requested native support and sandbox execution exceed active policy. Approve a separate scoped versioned constitution/AGENTS amendment with affected-spec review; do not reinterpret or dilute current policy during analysis. | RESOLVED after this planning analysis: explicit scoped approval/constitution2.1.0/ADR0003; T001 complete |
| G2 | Dependency/feasibility | HIGH | research§3; activity contract; T002 | Inspected sampled queue gauges do not prove all-client ingress/preparation/response ownership or native admission guard. Verify supported installed capability; source-only integration/testing is now authorized (reaffirmed2026-10-27), without another approval request for that scope. No managed-only/GPU/loaded-state substitution. | OPEN native activation/acceptance gate; T002 no longer blocks independent implementation; full live acceptance remains T051 |
| U1 | Resource underspecification | HIGH | data-model shared rules; model-access budgets; control-plane model-only jobs; T006/031/034/041/044/045 | Model-only jobs bypassed sandbox slot limits and lacked worker-memory accounting. | RESOLVED:2 model-only+2 sandbox jobs/host,2 worker processes,512MiB reservation each,1s RSS checks/bounded cleanup, active/uncertain native requests counted separately |
| I1 | Contract inconsistency | MEDIUM | control-plane framing vs sandbox input/model-access limits; T007/032/037/041/045 |64KiB control frames could not carry the declared input/model/artifact payloads without an explicit transfer protocol. | RESOLVED: begin/chunk/end,32KiB decoded chunks,64KiB frame,hash/length/index checks,10s input/30s artifact deadline,8Ki UTF-16 outbound model chunks, cumulative bounds/no budget reset |
| I2 | Status inconsistency | LOW | requirements checklist Notes | Historical12/16 unanswered-question note read as current despite A/A/A answers. | RESOLVED: current16/16 review added; old note explicitly historical/superseded |
| I3 | Acceptance inconsistency | MEDIUM | spec US1 scenario2/SC-001 vs watchdog contract | Unconditional30s restart wording conflicted with exhausted finite restart budget. | RESOLVED: recovery bound applies while budget remains; exhausted budget must report degradation without another start |

## Coverage summary

Representative covering tasks below; tasks.md contains the full many-to-many references. All requirements/success criteria require buildable validation work and are included.

| Requirement | Has task? | Task IDs | Notes |
| --- | --- | --- | --- |
| FR-001 | Yes | T001,T003,T012,T014–T016 | Native authority gated |
| FR-002 | Yes | T012–T017 | Boot/watchdog/session |
| FR-003 | Yes | T009,T025–T029 | Identity, drain, maintenance |
| FR-004 | Yes | T002,T018,T020,T023 | All-client coverage gate |
| FR-005 | Yes | T006,T019,T021–T022,T041,T044 | Per-request uncertainty/native race guard |
| FR-006 | Yes | T005,T007,T018,T023–T024,T054 | Readonly future008 contract;008 parked |
| FR-007 | Yes | T008,T031,T034,T038,T052 | Host/VM/sensor limits |
| FR-008 | Yes | T001,T009,T033,T036,T048 | Governed isolated execution |
| FR-009 | Yes | T006,T031,T034–T035,T038,T052 | Atomic bounded admission |
| FR-010 | Yes | T006,T015,T032,T035–T036,T038,T050 | Ownership/cleanup/restart |
| FR-011 | Yes | T006,T032,T037 | Bounded exported artifacts |
| FR-012 | Yes | T007,T032–T033,T036,T045,T048 | No sandbox external network |
| FR-013 | Yes | T002,T021–T022,T040–T046 | Pydantic/exact-model/budgets |
| FR-014 | Yes | T001,T007,T028,T033,T043,T045,T048 | No model management authority |
| FR-015 | Yes | T007,T009,T024,T028,T037,T040,T042,T048 | Roles/credentials/framing |
| FR-016 | Yes | T010,T017,T023,T029,T037,T048 | Redacted events/privacy |
| FR-017 | Yes | T001–T003,T016,T049–T050,T054–T055 | Operator install/backup/rollback |
| FR-018 | Yes | T004,T011,T017,T024,T030,T039,T046–T048,T050–T055 | Mock/native/release distinctions |
| SC-001 | Yes | T012–T014,T017,T049,T051–T052 | Boot/recovery bounds |
| SC-002 | Yes | T002,T018–T022,T051 | All-client native acceptance |
| SC-003 | Yes | T025–T028,T030,T049,T051 | Safe lifecycle |
| SC-004 | Yes | T008,T031,T034–T035,T038–T039,T051–T052 | Capacity enforcement |
| SC-005 | Yes | T032,T035–T036,T038–T039,T049–T052 | Cleanup/rollback |
| SC-006 | Yes | T032–T033,T036–T037,T039,T045,T047–T048,T051 | Isolation/security |
| SC-007 | Yes | T021,T040–T041,T043–T044,T047,T051 | Bounded task inference |
| SC-008 | Yes | T002,T018,T023–T024,T051,T054–T055 | Tested contract, not008 activation |

**Unmapped tasks**: None. Setup/gates and cross-cutting tasks have explicit requirement references. Tasks referencing new code point to the planned package/layout; no implementation file is falsely claimed to exist.

## Metrics

- Requirements:18 functional +8 success criteria =26.
- Tasks:55, all unchecked; setup3 + foundation8 + US1 6 + US2 7 + US3 6 + US4 9 + US5 8 + cross-cutting8.
- Requirement coverage:26/26 (**100%**); task mapping55/55.
- Clarification questions:3 asked,3 answered A/A/A, each recorded once.
- Spec checklist:12/16→16/16;4 newly passing,0 regressions,0 unchecked. This does not override G1/G2.
- Pass1 findings:1 CRITICAL,2 HIGH,2 MEDIUM,1 LOW. Pass2 open:1 CRITICAL +1 HIGH;4 remediated.
- Unresolved product placeholders:0. Remaining document ambiguity/duplication findings:0. External evidence/approval gates:2.
- Validation: task sequence/labels/paths, mapping, scenario numbering, local links, markdown fences/whitespace, and `git diff --check` passed. No runtime/test acceptance claimed.

## Clarification coverage

| Category | Status | Disposition |
| --- | --- | --- |
| Functional scope/behavior | Resolved | A/A/A and five independent stories |
| Domain/data model | Clear | Bounded identity, ownership, state, retention |
| Interaction/UX flow | Clear | CLI/status and task capability; no new frontend UI |
| Nonfunctional quality | Resolved | Boot/activity/isolation bounds; worker/job limits remediated |
| Integration/external dependencies | Deferred | G2 installed native evidence; implementation method cannot be fabricated |
| Edge cases/failure handling | Clear | Explicit uncertainty, leases, restarts, races and cleanup |
| Constraints/tradeoffs | Deferred | G1 explicit policy review before implementation |
| Terminology/consistency | Clear | Native activity versus residency; owned ledger versus all-client evidence |
| Completion signals | Clear | Mock/source/live/release distinct; no008 resumption |
| Misc/placeholders | Clear | No unresolved product markers |

## Next actions

1. Obtain explicit G1 review of the proposed narrow governance amendment; apply separately and re-analyze. No policy file changed in this pass.
2. Resolve G2 with approved installed-host inventory and native source/capability evidence. Native changes or live experiments remain separately gated. Do not request a huge cold model to test feasibility.
3. Only after those gates and implementation authorization, run implementation against this backlog. Re-run analysis if the approved authority or native integration changes design/contracts.008 remains parked throughout.

No hooks configured. No push, PR, merge or deployment performed by this documentation work.
