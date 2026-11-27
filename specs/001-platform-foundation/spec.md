# Feature Specification for the fios platform foundation

**Feature** · `001-platform-foundation`

**Created** · 2026-11-27

**Status** · Implemented and verified

**Input** · Establish the local development framework for a three-Mac model platform. Verify it through a native Mini sampler and a read-only dashboard in OrbStack. Retain the roadmap for later milestones.

## User Scenarios & Testing

### User Story 1 · Read the cluster inventory (F1, priority P1)

The local operator opens the dashboard on the Mini to see which hosts are configured and which have recent measurements. This is the first operational view of the cluster.

**Independent test** · Start with an empty observation directory and supply a valid Mini observation.

1. **Given** that no observation exists, **when** the operator opens the dashboard, **then** all three hosts appear with their configured roles and show **Awaiting sample**.
2. **Given** that the Mini has a valid sample at most 30 seconds old, **when** the operator refreshes, **then** the Mini shows **Reporting** with its observation time, physical memory, logical CPU count and one-minute load. Each Studio continues to show **Awaiting sample** until data is available.
3. **Given** that a host’s accepted sample is older than 30 seconds, **when** the operator refreshes, **then** the last observation is labeled **Stale sample** and excluded from the reporting count.

### User Story 2 · Read inventory as the local operator (F2, priority P1)

The sole operator reads the inventory from the Mini without signing in. Bootstrap access is limited to read-only operations on the local origin.

**Independent test** · Read the inventory locally, then repeat with a foreign origin, unsupported credentials and a write method.

1. **Given** a request from the Mini’s loopback interface with the expected local authority, **when** it reads the inventory, **then** it succeeds without credentials.
2. **Given** a foreign authority or browser origin, unsupported credentials, or a forwarded identity claim, **when** it requests inventory, **then** access is denied.
3. **Given** a write request or a principal without the required role, **when** it attempts to act on inventory, **then** the request is denied and inventory remains intact.

### User Story 3 · Reproduce the foundation (F3, priority P2)

A developer starts the local preview from a clean checkout, confirms the sample reaches the dashboard and opens the active specification and roadmap from Spec Kit.

**Independent test** · Use the quickstart on the Mini and resolve the active feature in Codex.

1. **Given** a clean checkout on a supported development Mac, **when** the developer follows the quickstart, **then** the native sampler and dashboard run in the documented local setup with no model weights or credentials.
2. **Given** the repository’s pinned Spec Kit setup, **when** the developer checks the active feature, **then** the tools resolve Spec 1 and its roadmap and the local verification suite runs.

### Edge Cases

- A malformed, oversized, future-dated or mismatched observation shows **Invalid sample**. Missing observations show **Awaiting sample**. The reporting count excludes both states.
- A sample at exactly 30 seconds is fresh. Freshness is evaluated when the operator requests the dashboard or inventory.
- A valid sample shows recent activity for the configured host. It supplies only the listed measurements. Free memory, model availability and RDMA health require their own observations.
- A stopped sampler ages into **Stale sample**. The dashboard still renders the configured inventory.
- The dashboard’s labels convey status in text and are readable at phone and desktop widths.

## Requirements

### Functional Requirements

- **FR-001 (F1)** Show the Mini and two Studios with a stable host ID, configured role and configured hardware. Label measurements separately.
- **FR-002 (F1)** Associate each observation with one host and a collection time. Display its physical memory, logical CPU count and one-minute load when the observation is valid.
- **FR-003 (F1)** Classify observations as **Reporting**, **Awaiting sample**, **Stale sample** or **Invalid sample** using the rules above. Count only reporting hosts. An invalid, absent or stale observation provides zero evidence for scheduling.
- **FR-004 (F2)** Allow inventory reads only through the local bootstrap operator boundary. Reject non-loopback traffic, foreign authority or origin, unsupported credentials, and forwarded identity claims.
- **FR-005 (F2)** Enforce authorization at the inventory access boundary. The bootstrap admin can read inventory. The user role has no admin authority. The foundation exposes no inventory writes or privileged actions.
- **FR-006 (F3)** Provide a repeatable local quickstart, pinned Spec Kit integration for Codex, active specification and roadmap, and runnable verification. Local startup requires neither model weights nor a token.
- **FR-007 (F3)** Record the model and runtime shortlist and verification conditions for later hardware and safety decisions in the research and roadmap.

### Key Entities

- **Host** · A configured cluster member with a stable ID, hardware and role.
- **Observation** · A host-specific sample with a collection timestamp and measured values.
- **Reporting state** · The derived status of a host’s latest observation at the time of the read.
- **Bootstrap operator** · The single trusted local admin identity for read-only inventory access.

## Success Criteria

### Measurable Outcomes

- **SC-001** The overview lists exactly three configured hosts. A fresh valid Mini observation results in one reporting host and two awaiting samples when the Studios have supplied no data.
- **SC-002** Every case in the observation-state acceptance scenarios displays the expected label and reporting count, including fresh at 30 seconds and stale at 31 seconds.
- **SC-003** Every rejected request case in the access scenarios fails without disclosure of inventory or a state change, and the permitted local read succeeds.
- **SC-004** On a supported clean checkout, the operator can obtain the first Mini observation, view the dashboard and resolve the active Spec 1 artifacts using the documented instructions without a credential or model download.

## Assumptions

- The initial deployment is the single-operator Mini preview. The Mini and its local workloads are trusted. The user’s OrbStack environment is the container target.
- The local sampler and dashboard are in scope. Remote Studio enrollment, model execution, job dispatch, public ingress and account migration each belong to a later milestone.
- The two Studio entries are inventory aliases. Actual host identities and transport qualification belong to enrollment and hardware milestones.
- Model revisions, footprint and throughput, search, sandbox containment and publication controls are evaluated in the relevant later milestone.

## Later Product Journeys

The roadmap retains the following product outcomes and acceptance evidence for later slices.

| ID / priority | Journey | Acceptance evidence for the subsequent slice |
| --- | --- | --- |
| P1 / first | General chat on the Mini and regular coding on a Studio | Stream tokens, stop generation, recover from backend loss, and report model revision and usage. Measure peak Mini model footprint at a bounded context under 6 GB. Retain resources for macOS, OrbStack and the UI. Chat-originated administration requires the same role check as any API action. |
| P2 / first | Dispatch work across the three native host services | Respect capability, free memory, existing reservations, warm weights, queue limits, model idle TTL and draining. Enqueue, cancel, retry and reconcile a lease after core/agent restart. An idle model unloads only after its last lease ends. |
| P3 / next | Serve one large model on both Studios | Reserve both nodes together and confirm the actual RDMA transport, matching artifacts and rank placement. On link/rank loss, fail the group, release both reservations and show degraded status. Compare against one Studio with a fixed workload. |
| P4 / next | Operate the cluster | Admin sees queue depth, loaded models, memory, health, throughput, first-token latency, errors, token totals and cost basis. Admin can drain, unload and stage/roll back approved software. Test denied user and model-originated actions. |
| P5 / next | Write and review code | A coding Project preserves source and review history. A defensive review identifies locations, risk, fixes and regression checks on supplied or generated code. Users explicitly request a bounded test run and retrieve sanitized results from an isolated Studio sandbox. |
| P6 / next | Plan an adult-table campaign | Reopen a Project after restart and resume from canon, characters, session log and player-safe handouts. Campaign, one-shot and session modes have distinct outputs. Permit mature fictional drug use, graphic fantasy violence and adult themes within the table's preferences. A player handout excludes GM-only notes. |
| P7 / next | Generate a D&D artifact | Select a Project, realistic or fantasy illustration, subject traits and a standard aspect ratio. Save approved art and generation metadata, export a handout and reopen it later. Support adult anatomy and nudity. Strictly block sexual depictions of minors or ambiguous youth, including fantasy species, on every path for every role. |
| P8 / next | Ground a response in current information | An explicitly enabled search returns dated results with source links. Distinguish retrieved evidence from model inference, show provider failure, and prevent retrieved instructions from invoking tools or disclosing private context. |
| P9 / last | Open the service to other adults | Replace bootstrap identity with Google OIDC sessions and revocable scoped API keys. Verify owner isolation and admin/user permissions at every ingress. Prove bootstrap is disabled before binding public ingress. |
