# Feature Specification: Containerized Supporting Services

**Branch**: `006-container-support-services` | **Created**: 2026-10-25 | **Status**: Implemented and locally verified; hosted CI and production migration pending separately gated release.

## User Scenarios & Testing

### US1 — One managed application stack (P1)
As the operator, I want every Fios supporting service managed by OrbStack with the application, so no invisible macOS processes or login jobs are required.

Acceptance: removing the former native jobs leaves no registrations/programs; starting the stack runs readiness checks in an isolated container, and the app and harness receive fresh observations. Restarting the observer recovers without native helpers. Missing or old observations block affected models without inference or substitution.

### US2 — Containerized safe delivery (P1)
As the operator, I want approved green-main releases delivered automatically by the same container stack while keeping deployment authority out of the app.

Acceptance: a separate outbound-only management container rejects unchecked, skipped, failed and superseded revisions; builds before stopping, backs up stopped data, preserves the previous image and rolls back failed verification. It never runs PR code. No native daemon, host checkout/config mount or hosted production runner is required.

### US3 — Durable operational standard (P2)
As the operator, I want AGENTS and operational instructions to prohibit future native supporting processes, preserving only the MLX/RDMA native exception.

Acceptance: documentation describes container lifecycle, explicit management privilege and recovery; the obsolete host installer cannot recreate native jobs.

## Requirements

- **FR-001**: Run all persistent supporting processes in the OrbStack Fios stack; only MLX-Serve/RDMA remain native. One-shot administrative/test commands are allowed.
- **FR-002**: Remove only the newly installed native registrations, programs and observation artifacts; preserve app data, credentials, rollback images, backups and rollout evidence.
- **FR-003**: Containerize read-only readiness observations using shared metadata storage with the app's mount read-only. Preserve endpoint binding, five-second expiry and independent Express/Python gating.
- **FR-004**: Observe only explicitly configured endpoints, without inference, URL following, credential forwarding, routing/RDMA changes or public listeners.
- **FR-005**: Isolate delivery management from the app/observer. Only the dedicated controller receives Docker-management access; no published ports, host source/config mounts or unnecessary credentials.
- **FR-006**: Require successful exact-main push CI and every required check, including a final recheck before stopping. Public discovery must work without exporting host GitHub credentials; polling must respect anonymous rate limits.
- **FR-007**: Preserve serialized build-before-stop, stopped-data backup, exact revision verification and automatic compatible-image rollback, without two app instances opening the live database.
- **FR-008**: Reject the native installer, update AGENTS/README, validate mock-only CI and exercise real container discovery without inference before claiming completion.

## Success Criteria

- **SC-001**: Zero installed Fios LaunchAgents/native background supporting services remain.
- **SC-002**: The running stack reports three healthy hosts and five available chat models, including unloaded local Gemma, without inference.
- **SC-003**: Observer stop/recovery changes peer readiness within the existing five-second evidence bound and recovers automatically.
- **SC-004**: All required hosted checks pass before merge and merged-main checks pass before deployment; upgrade/failed-verification rollback rehearsals pass on isolated resources.
- **SC-005**: The app has no Docker socket/deployment credentials, retains localhost binding and unchanged persistent data/hardening.

## Key Entities

Observer: metadata-only worker. Observation volume: short-lived endpoint-bound evidence. Controller: singleton privileged delivery manager. Release: immutable approved main revision/image. Snapshot: stopped-data backup with prior image reference.

## Assumptions and Edge Cases

Container networking currently reaches both existing Studio APIs; transient failures must fail closed rather than install native proxies. Docker-management access is the controller's explicit existing deployment authority, not an application privilege. Public repository metadata needs no exported personal token; optional future credentials require separate review. The controller is a stable reviewed image and must not replace itself mid-rollout. Same-volume backups are not disk-loss protection. Incompatible future database migrations require a reviewed restore plan. Handle missing/expired observations, controller restart, failed build/backup/verification/rollback, main advancing mid-build, API rate limiting and an absent existing app.
