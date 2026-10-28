# Implementation Plan: Studio Platform Management Agent

**Branch**: `009-studio-platform-agent` | **Date**: 2026-10-26 | **Spec**: [spec.md](spec.md)
**Input**: Clarified A/A/A specification. Documentation/research only; no implementation or Studio operations authorized by this plan.
**Status**: Implementation authorized; G1 resolved by constitution2.1.0/ADR0003. Native activation/acceptance gate **HOLD** remains for G2 authoritative-native-activity compatibility; independent local implementation/testing proceeds; see compatibility.md. The original gate review below is historical; current authority is recorded in ADR0003. A complete plan is not permission to bypass either gate.

## Summary

Build an independently supervised, unprivileged native management boundary on each of the two Studios. It observes/manages the installed MLX-Serve and OrbStack lifecycles, exports redacted all-client activity, admits finite network-isolated temporary sandboxes, and mediates bounded exact-model inference through private Pydantic workers. Native supervision is necessary because OrbStack cannot recover itself from a container. Do not restore005's installer or change006's existing Compose services.

The controller is deterministic. Models and sandbox code have no authority over service lifecycle, admission policy, credentials or other jobs. No generic host shell API, public listener, model download, load/unload admin call, remote shell from a sandbox or recursive agent is added. Existing Fios app,007 inference/search budgets, SQLite and UI remain unchanged.008 stays parked.

## Technical Context

**Language/Version**: Swift6.4 / SwiftPM, macOS arm64; CPython3.11.17 and the existing locked Pydantic AI2.61.0 distribution for a separate private platform-task worker. No new Python dependencies or change to007 worker protocol.
**Primary Dependencies**: macOS Foundation, Darwin, Security/CryptoKit, SQLite3 system library; launchd; installed, identity-checked OrbStack Docker CLI using its explicit user Unix socket. No third-party Swift dependency in the first design. Toolchain/SDK and installed service/CLI identities must be pinned in the release manifest before build acceptance.
**Storage**: A separate manager-owned SQLite database per Studio, one writer process; watchdog owns a separate atomic restart-budget file. Neither opens Fios SQLite. Root-owned immutable installation/config plus private0700 state/0600 files under an operator-approved local path. See [data-model.md](data-model.md).
**Testing**: Swift Testing/XCTest; existing noneditable installed Python tests; isolated Docker fixtures for sandbox lifecycle/isolation; source-level native coverage review plus separately authorized native acceptance. Never use the production container runtime for destructive tests.
**Target Platform**: The two designated arm64 macOS Studios, initially assumed EdgeA/EdgeB; OS/runtime identities verified before any rollout. No new Linux VM, Kubernetes or replacement of OrbStack.
**Project Type**: Native supervised control service + restricted local CLI/IPC + private model worker + disposable OCI sandbox image. No frontend redesign.
**Performance Goals**: Supervisor observable within60s after macOS can execute it, before user login; manager restart within30s of hang detection; telemetry every2s with5s maximum age/1s future tolerance; cleanup within60s of runtime availability. Targets require measurement, not source-only claims.
**Constraints**: Network-none sandboxes; fixed allowlisted host operations; native inference only; no automatic inference replay; per-host2 sandbox slots plus2 model-only job slots (4 jobs total), at most2 supervised model workers with512MiB reservation each; bounded leases, memory, CPU, disk/output and model usage specified in contracts. Controller target≤256MiB RSS and≤5% of one CPU averaged over idle5min, excluding per-job workers; degradation disables admissions rather than weakening limits.
**Scale/Scope**: Exactly two enrolled Studios initially; one manager authority per host/runtime, one model resident per deployed host as a compatibility prerequisite, same-model concurrent native requests allowed. No global scheduler quorum or speculative cross-host placement.

## Constitution Check

| Principle / policy | Pre-design | Post-design / gate |
| --- | --- | --- |
| Specification first | PASS: five stories,18FR,8SC, A/A/A | PASS for docs; implementation partially underway; see task/validation records |
| Purpose-built frontend | PASS | No changes to frontend,007 semantics or retired001 |
| Native inference / cluster approval | PASS for design only | G2/HOLD: native observation/non-preemption must be proven; no server/RDMA/config changes authorized |
| Secure by default / disable arbitrary execution | **ERROR G1**: requested sandbox execution exceeds current blanket prohibition | RESOLVED: approved narrow [governance change](governance-proposal.md), constitution2.1.0 and ADR0003; operational gates remain |
| Persistent/reproducible deployment | G1: native manager not described by existing Compose-only deployment | Scoped native architecture authorized; release manifests/installer still incomplete; existing Compose unchanged; backups/drain/rollback required |
| Verify honestly | PASS | Explicit mock/source/native gates; metrics are not yet authoritative all-client evidence |
| AGENTS: all support services containerized; daemon authority only existing controller | **ERROR G1** | RESOLVED: explicit narrow native platform exception approved; runtime authority remains restricted to trusted manager |
| Harness boundary | PASS subject to G1 | New private per-job Pydantic entry point, no SQLite/listener or host tools;007 path untouched |

G1 was resolved by the separately approved constitution/AGENTS update. G2 remains a native activation/acceptance gate, not a prerequisite for independent local implementation/testing. Its compatibility record must cover the installed native serving lifecycle; a denied/missing/incomplete source cannot become a managed-only substitute. No native acceptance is claimed.

## Architecture and trust boundaries

1. **Boot supervisor**: root-installed launchd job runs as the approved nonroot service user, not root. A minimal watchdog starts exactly one manager process, tracks durable restart budget (3 starts/10min, minimum10s spacing), and requires progress from the actual control/event loop. Manager heartbeat2s;6s without progress triggers bounded terminate/reap/restart. Budget exhaustion leaves an observable degraded supervisor, not an exit/restart storm. No model/runtime dependency. Disk unlock may precede OS execution; login must not be required for supervisor status.
2. **Session adapter**: a minimal approved-user login component performs only fixed identity-checked GUI/service-start operations when macOS requires that session. Absent session → `waiting_session`; locked credentials → `waiting_credentials`. It cannot dispatch workloads or accept arbitrary paths/argv. Prefer supported CLI lifecycle when possible; do not change existing login settings automatically.
3. **Manager**: serialized state transitions/reservations, fixed service operations, resource sampling, native-activity adapter, runtime reconciliation and role-separated Unix-socket IPC. No TCP listener. Runtime commands use absolute verified executable paths and argv, never a shell; pin `DOCKER_HOST` to the approved local OrbStack socket and discard caller environment/context overrides. Management authority is daemon-wide despite label checks and remains a trusted boundary.
4. **Authoritative activity**: read-only native-local adapter, not remote metrics exposure. Existing metrics are candidate diagnostic inputs only; see [research.md](research.md). A trusted source must cover preparation, native request ownership, queue/compute and response delivery for every client, carry epoch/sequence/freshness, and distinguish model identity. Gaps force `unknown`. Native admission/refcount protection, not observation freshness, must close read/dispatch races.
5. **Sandbox**: already-present digest-pinned arm64 image, network `none`, no port/mount/socket/host namespace, nonroot, read-only root, cap-drop-all/no-new-privileges, bounded tmpfs workspace. Manager attaches a bounded framed stdin/stdout channel to a fixed image runner. Untrusted code runs only inside this sandbox; runtime authority never crosses into it. Model requests are data on this channel, not network calls from the sandbox.
6. **Model worker**: a separate short-lived installed Pydantic worker accepts one exact-model request at a time over bounded pipes. No tools, retries, fallback or listener. It calls only the approved native loopback serving endpoint after readiness/budget/ownership checks. A sandbox runner can request model assistance within its lease but cannot specify arbitrary URLs/headers/provider settings or gain manager operations. Platform-only tasks use the same mediation without a sandbox.
7. **Consumer export**: local read-only socket/CLI initially. A future008 consumer may use a separately reviewed forced-command observation-only SSH key over the existing SSH service, host-key-pinned, no shell/PTY/forwarding/environment overrides. This is a proposed deployment option, not authorization to edit SSH today. No general SSH credentials enter app/observer/sandbox; no new LAN port.009 supplies a tested adapter/contract fixture, not an008 routing implementation.

## Admission and operational policy

- Admission is host-local and serialized. A requester explicitly selects one eligible Studio using observations; a rejected/uncertain attempt is not dispatched elsewhere. Job IDs are idempotency keys; mismatched reuse rejects. Snapshot export is advisory, never a reservation for a native switch.
- Use the finite bounds and state transitions in [sandbox-lifecycle.md](contracts/sandbox-lifecycle.md) and [model-access.md](contracts/model-access.md). Available physical memory is not multiplied by VM/container accounting; full outstanding reservations are conservatively deducted even if some use is already sampled. Unknown critical telemetry rejects new work.
- Runtime limits are enforcement, not a promise against arbitrary unrelated host consumers. Preserve existing OrbStack VM limits; use the lesser of host headroom and verified VM remaining capacity. Do not increase caps to satisfy a job.
- External MLX requests may arrive at any time. Native in-use protection remains mandatory; resource pressure closes admission and terminates owned sandboxes under the documented policy, not native active inference. Explicitly authorized exact-target platform inference may use native on-demand loading and replace an idle resident model. No resident-only API is required; no load/unload admin operation or synthetic warmup is issued.
- Deliberate maintenance persists across restarts. Absent service recovery is bounded; hung-service recovery cannot silently kill active/unknown MLX or unrelated runtime work. Force requires an operator-confirmed exact affected scope and is never available to models/tasks.
- Restart converts outstanding model requests to uncertain and resumes owned-resource reconciliation. Expired leases revoke capabilities even while runtime cleanup is unavailable. Successful later inference never clears earlier uncertainty. Never delete unrelated containers/images/volumes.

## Project Structure

### Documentation (this feature)

```text
specs/009-studio-platform-agent/
├── spec.md
├── plan.md
├── research.md
├── governance-proposal.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── control-plane.md
│   ├── activity.md
│   ├── sandbox-lifecycle.md
│   └── model-access.md
├── tasks.md
├── analysis.md
├── validation.md
└── checklists/requirements.md
```

### Planned source (not created by this planning pass)

```text
platform/studio/
├── Package.swift
├── Sources/
│   ├── StudioCore/           # schemas, journal, policy, adapters
│   ├── StudioSupervisor/     # bounded watchdog, startup fence
│   ├── StudioManager/        # serialized controller and IPC
│   ├── StudioSession/        # fixed user-session operations only
│   ├── StudioCLI/            # local operator/read-only export commands
│   └── CSQLite/              # SDK system module; no bundled SQLite
├── Tests/StudioTests/        # deterministic unit/contract/recovery tests
├── deployment/              # versioned plists, policy/release manifests
└── sandbox/                 # pinned Dockerfile and fixed pipe runner
src/agent/fios_agent/platform_worker.py
src/agent/fios_agent/platform_protocol.py
tests/agent/test_platform_worker.py
tests/fixtures/platform/     # shared safe protocol/lifecycle/native fixtures
scripts/check-platform.mjs
scripts/check-platform-container.mjs
scripts/install-platform.mjs # new explicit operator tool; NOT install-deployment.mjs
```

**Structure Decision**: Separate platform package and per-job entry point to avoid broadening007's trust boundary. Separate per-Studio DB and lifecycle policies; no copy of008 partial routing code. The existing app-only deployment controller never installs native artifacts.

## Phases, delivery and validation

- **Phase0 research/gates**: source/doc evidence, threat boundary, candidate adapter coverage audit, scoped governance proposal and operator inventory/compatibility record. All current findings are in research; live validation remains pending. No fabrication of installed binary attestation.
- **Phase1 design**: data model, role/IPC, activity, sandbox and model contracts, plus [quickstart](quickstart.md). Complete as conditional design; G1 is resolved; G2 gates native activation/acceptance rather than independent implementation/testing.
- **Phase2 tasks**: setup/gates → shared foundations → independent story increments → security/rollback/resource and release evidence. Generated separately in [tasks.md](tasks.md).
- **MVP**: supervision + all-client observation and safe native admission evidence (US1/US2). A supervisor alone does not unblock008. Sandbox and model capabilities remain disabled until US3/US4/US5 gates pass.
- **Release**: reviewed PR; six exact-head checks plus added macOS native-package/mock checks included in the aggregate gate; independent green merged-main CI. Existing automatic app delivery stays unchanged. Separately authorized one-Studio-at-a-time native rollout with stopped manager DB backup, prior binary/config retention, socket/key manifest validation and health-only verification. Rollback drains/reconciles native/owned work; never erase uncertain ownership to make an old binary start.

## Complexity Tracking

| Proposed exception/complexity | Why needed | Simpler alternative rejected |
| --- | --- | --- |
| Native unprivileged supervisor/manager/session adapter | Recover OrbStack independently and observe host-local native activity | A manager inside OrbStack cannot operate while OrbStack is unavailable |
| Isolated sandbox execution + trusted runtime authority | Explicitly requested temporary agent tasks with complete lifecycle ownership | Giving the existing frontend/model worker the Docker socket violates separation |
| Separate Pydantic platform entry point | Bounded task/sandbox model access without changing007 tool budgets | Reusing the web-search worker command surface would conflate unrelated authority |
| G2 native observation/admission prerequisite | All-client semantics and race safety are required by A/A/A | Manager-only ledger or zero GPU/sampled queue values cannot prove host-wide idle |

These are proposed exceptions/constraints, not accepted constitutional waivers. See [governance-proposal.md](governance-proposal.md).
