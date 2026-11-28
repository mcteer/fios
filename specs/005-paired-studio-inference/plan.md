# Implementation plan · Paired Studio inference

**Feature 005 · 2026-11-27** · [Specification](spec.md) · [Candidate comparison](research.md)

## Summary

Extend the private chat path with an explicit paired alias. The Mini reserves both Studios in the existing job ledger, admits one generation, and exposes an approved answer only when the two ranks complete. Start with synthetic processes on the Mini. Select a native runtime from an instrumented hardware trial on the connected Studios.

First release uses a model and pack that also complete the workload safely on one Studio. The [large MoE qualification milestone](../roadmap.md#large-moe-on-the-studio-pair) follows validation of this release.

## Technical context

Retain the repository's Python standard-library control plane, SQLite ledger and private conversation store, local OS-peer admin socket, enrolled worker mTLS, HTML/JavaScript chat and OrbStack web preview. Keep database files with their native service and out of the UI container. Each Mac keeps its dedicated management container and minimal native supervisor. Run inference as native macOS processes. The Mini neither loads a paired shard nor participates in the RDMA group. This design adds no general-purpose remote command or second scheduler.

## Constitution check

| Gate | Design and acceptance evidence |
| --- | --- |
| Measured capacity | Evaluate two session-bound observations, per-slot peak plus floor, normal pressure and exclusive holds in one admission transaction. A missing or stale observation yields zero eligible pairs. |
| Authority and publication | Only the local admin changes qualification. The enrolled reporter supplies bounded output, the peer supplies its execution receipt, and the Mini enforces policy on the complete transcript, answer and title. |
| Private topology | Bind inference HTTP to host loopback. Confine coordination traffic to pinned peer identities/endpoints and the dedicated pair link. Reject dynamic membership, wildcard exposure, unbounded remote execution or capability discovery outside this pair. |
| Core first | Pass native supervision and recovery plus a two-worker integration rehearsal on the Mini and record the result before installing or building on either Studio. |
| Cleanup | Identify trial resources by a run ID. Verify stop, idle capacity and existing preview health, then remove only run-owned environments, staged weights, tags and containers. |

Pre-research review found the existing single-host inference receipt rule insufficient. The following design extends it. Post-design review ties each gate to the [validation sequence](quickstart.md).

## Project structure and execution flow

1. Extend the existing catalog in `src/backend/model_catalog.py` with a versioned paired manifest and a joint attestation. Keep single-host manifests valid byte-for-byte. Add schema objects transactionally; do not reinterpret old single-host or synthetic evidence as paired qualification. Carry a placement revision through conversation submission and the worker protocol.
2. Extend `src/backend/scheduler.py`, `job_ledger.py` and `job_protocol.py`. Derive required slots, roles and per-host peaks from the immutable profile. Acquire both holds together. Specify prepare (validate local artifact, budget and peer), start (both ready), execution (observed two-rank transport), settlement and cleanup. Neither worker can submit work as its peer. Fail in place on lost authority.
3. Extend the harness under `src/agent/` with a native adapter for the selected runtime. Spawn a fixed local executable with an allowlisted argument vector and operator-owned manifest. Constrain any cross-host launcher to a pinned peer and a forced, grant-checking worker entry point. A candidate requiring general SSH credentials from the service is ineligible. Bound bring-up by job deadline, renew separately while inference blocks, terminate owned process groups within the lease deadline, verify exit and device quiescence, then refresh capacity.
4. Extend `src/backend/chat_dispatch.py` and `conversations.py` to admit only the reporter for prompt, append and publish. Use the existing full-answer and pending-title path. Stage policy-approved text privately, then expose through completed-job reconciliation. Accept the second rank's success independently of staged text. Require both valid execution receipts, policy-approved content and active profile at the successful ledger transition. Settle the reporter's tagged usage once there. Test cancellation during the checker and both receipt orders.
5. Extend `src/frontend/chat.html`, `chat.js` and the dashboard's existing read path to show the paired choice, queue/failure reason and private admin observations. Extend the local admin CLI for explicit qualification/promotion/withdrawal. Keep prompts, raw peer addresses and grants out of telemetry.

## First trial and transport verification

Use a local admin trial operation to submit a pinned candidate and fixture before an alias exists. The ledger owns the same two physical slots used by chat, including while a rank cleans up. Before measured peaks exist, apply each host’s reviewed trial ceiling and floor through the existing trial budget checks. Separate the trial result path from chat publication and billing. Hardware runs use the active reservation ledger even when candidate files, worker processes and reports are disposable. A disconnected test ledger is suitable only for synthetic hosts.

Each adapter translates observed model transfers into the same two-rank evidence contract. Implement a single acceptance predicate for serving and trials. Fail qualification if a pinned build cannot expose completed inference payload transfers or distinguish a fallback. Run a TCP-only control through the same verifier. The [pair contract](contracts/pair.md) specifies the observations and the [quickstart](quickstart.md) specifies the hardware controls.

## Threats, qualification and recovery

A stale worker can replay receipts, a candidate may auto-discover other machines, and a cable failure can conceal fallback to TCP. Pin the worker identity, incarnation, generation, revision and slot on every operation. Require per-attempt positive transport evidence from both ranks. Inject stale, forged and conflicting messages, unexpected membership, fake transport reports and an unavailable checker. Existing publication, ownership and deletion rules apply to all users.

Use the workload and thresholds in [quickstart.md](quickstart.md). Record reviewed package revisions, model pack hashes, licenses, macOS builds and per-rank measurements in the qualification report. Compare one Studio and the pair, including cold start and warm decode. Record an unsupported candidate even when its prerequisite prevents a safe run. Maintain one selected production adapter and keep experimental launchers in the trial harness.

Drain paired admission and take an offline ledger/content backup before schema rollout. Rehearse restoring the matched backup using existing incarnation fencing and reconciliation. To withdraw, disable the paired alias, fence both ranks and verify cleanup separately. Roll back to a previously qualified matching pair revision only through explicit admin action. Existing single-host service remains independently routable. The full operations dashboard, software updater and search-backed Deep Research have separate roadmap milestones.
