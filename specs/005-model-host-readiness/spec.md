# Feature Specification: Model and Host Readiness

**Feature Branch**: `005-model-host-readiness`
**Created**: 2026-10-25
**Status**: Complete and closed (2026-10-25). PR #2 merged as `867da7d8be7e6f5df7c77d6bd61e7f80d23ba7d0` after green exact-head/main CI and was deployed with backup/verification. Spec 006 supersedes the rejected native supporting-service topology: readiness and delivery now run in the OrbStack Compose stack. Preserve the readiness behavior; never restore the historical native installer. See validation.md for release and interruption/recovery evidence.
**Input**: Fix the availability gap, including serving-host health and advertised models; test local Gemma disappearance/recovery before merging and deploying production.

## User Scenarios & Testing

### User Story 1 — Trust model availability (P1)

A user sees whether the gateway and each serving host are reachable and presenting a selected model, rather than mistaking a cached peer listing for readiness.

**Independent test**: Leave a stale model advertised while its host fails; refresh and attempt a send.

**Acceptance scenarios**:
1. Given a healthy gateway and host presenting a chat model, discovery marks it available, separately identifies its loaded state, and permits an exact-ID send.
2. Given a stale gateway listing and an offline host, discovery marks the model unavailable and no inference is sent.
3. Given a reachable host that no longer presents the model, that model is unavailable even if the gateway still lists it.
4. Given an unverified or unauthorized host, status is unknown, not ready; sending is blocked with an actionable safe error.

### User Story 2 — Recover without substitution (P1)

A user sees hosts/models disappear or become unavailable and recover when services restart, without silently changing the selected model.

**Independent test**: Stop the authorized local service and verify Gemma is unavailable; restart it and verify the exact ID reappears without inference.

**Acceptance scenarios**:
1. A gateway outage is distinct from application liveness, retains no stale ready claims, and blocks new generations.
2. Restart restores availability on refresh; a present unloaded model is available for on-demand loading, not falsely described as already loaded.
3. Changes during preflight or streaming fail honestly without retry or fallback.

### User Story 3 — Deliver verified production changes (P2)

The user receives a tested, reviewed, green-CI merge and a verified production upgrade with backup and rollback safety.

**Independent test**: Exercise recovery in isolated containers before the production release and record the deployed revision and discovery result.

### Edge Cases

Malformed/oversized catalogs, bounded slow probes, unauthorized peers, mismatched peer suffixes, missing host configuration, redirect/credential leakage, stale peer records, service death between preflight and inference, failed deployment and rollback.

## Requirements

- **FR-001**: Distinguish application liveness, gateway health, serving-host health, model advertisement and loaded state. Never equate unloaded with offline.
- **FR-002**: Check both the host's health and its own model advertisement; a gateway's cached peer entry alone MUST NOT establish readiness.
- **FR-003**: Only explicitly configured serving-host endpoints may be probed; never follow arbitrary catalog URLs or redirects or forward gateway credentials to peers.
- **FR-004**: Refresh visible status within 30 seconds or on explicit refresh/focus; probe deadlines MUST be bounded, and failure MUST invalidate prior ready claims.
- **FR-005**: Reject unavailable/unknown selected models before inserting messages. The inference harness MUST independently preflight the exact selected target immediately before inference, including when called without Express.
- **FR-006**: Preserve exact model IDs, capabilities, authentication, history, stop/cancellation and reasoning privacy; no retry, fallback, tools, inference probes or automatic loading during discovery.
- **FR-007**: Host/model status and safe reasons MUST be visible in the UI; unavailable selections MUST NOT silently select a replacement.
- **FR-008**: Cover healthy/offline/stale/missing/unauthorized/slow/recovery behavior with isolated mocks and real Agent traversal. Live validation may stop/restart the local MLX-Serve only; remote service changes require user assistance or approval.
- **FR-009**: Merge only after green latest-head CI. Production delivery MUST preserve a stopped-data backup and prior image, verify health and authenticated discovery, and roll back failed application upgrades without changing native inference or RDMA.
- **FR-010**: If network isolation requires host observations to be shared across a runtime boundary, those observations MUST be read-only to the application, bound to explicitly configured hosts, contain no credentials, and expire within 5 seconds. Missing, altered, future-dated or expired evidence MUST NOT establish readiness.

### Key Entities

- Host observation: stable configured name, available/unavailable/unknown status, safe reason, observation time and advertised local model IDs.
- Model availability: exact gateway ID, serving host, advertised/loaded state, availability and reason; transient, not a new persisted conversation format.
- Release: checked merged revision, previous image, stopped-data backup, verification/rollback outcome.

## Success Criteria

- **SC-001**: Offline, stale and unverified targets yield zero inference attempts in automated tests.
- **SC-002**: Host health and model availability recover within one refresh after restoration, without a different model being selected.
- **SC-003**: Local Gemma stop/start is observed before release, with the original service restored and no real inference required.
- **SC-004**: Existing regression suites and new availability checks pass locally and in hosted CI before merge; production revision and non-inference verification are reported separately.
- **SC-005**: Loss of the host observer (containerized under spec 006) invalidates peer readiness within 5 seconds; expired or endpoint-mismatched evidence produces zero inference attempts in automated tests.

## Assumptions

MLX-Serve exposes health and model discovery on each configured serving host. Its gateway includes peer-qualified IDs and may retain stale peer entries. Explicit peer endpoints belong in private deployment configuration; host URLs from model payloads are not trusted routing instructions. The user authorizes stopping/restarting the local service for validation, but not remote processes or cluster configuration. Previously requested automatic-delivery guidance is carried into this feature's release work; missing automation must be reported honestly.
