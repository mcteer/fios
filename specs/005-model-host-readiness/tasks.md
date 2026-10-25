# Tasks: Model and Host Readiness

## Phase 1 — Setup
- [X] T001 Specify and research observed MLX health/catalog behavior in specs/005-model-host-readiness/spec.md and research.md. (FR-001–009)
- [X] T002 Clarify trust/loading assumptions and define plan, data-model, contracts and quickstart in specs/005-model-host-readiness/. (FR-001–009)

## Phase 2 — Foundation
- [X] T003 Add failing shared fixture/parity/security tests in tests/availability.test.js and tests/agent/test_availability.py, including 2-second/1-MiB bounds and explicit peer configuration. (FR-001–004)
- [X] T004 Implement bounded, credential-isolated discovery in src/agent/availability.js and src/agent/fios_agent/availability.py; pass MLX_PEER_URLS through safe configuration. Add scripts/observe-hosts.mjs and expiry/fingerprint tests for the metadata-only read-only native observation bridge required by observed container reachability. (FR-001–004)

## Phase 3 — US1: Trust readiness
- [X] T005 [US1] Add stale/offline/missing/unknown peer API and direct harness tests in tests/availability-api.test.js and tests/agent/test_harness.py, proving zero inference and no new messages. (FR-005–006)
- [X] T006 [US1] Gate Express before persistence in server/index.js and independently preflight Python inference in src/agent/fios_agent/harness.py; extend fixed IPC error enums. (FR-005–006)

## Phase 4 — US2: Recover without substitution
- [X] T007 [US2] Add browser recovery/selection tests and configurable mock failure states in tests/browser/availability.spec.js and tests/mock-mlx.js. (FR-007–008)
- [X] T008 [US2] Display hosts, safe model reasons and unloaded state in src/main.jsx and src/useModelCatalog.js; block bad sends without silently selecting another ID. (FR-007)
- [X] T009 [US2] Observe local Gemma availability → authorized local service stop → unavailable/rejected send → restore/recovery, using isolated storage; record evidence in specs/005-model-host-readiness/validation.md. (FR-008)

## Phase 5 — US3: Verified delivery
- [X] T010 [US3] Implement scripts/deploy.mjs and scripts/install-deployment.mjs for outbound-only exact-green-main local delivery and stable reviewed launchd programs. Document peer/observer configuration and safe delivery in .env.example, compose.yaml, README.md and AGENTS.md; test release backup/rollback in tests/deployment.test.js and scripts/check-agent-container.mjs without production data. (FR-003,009)
- [ ] T011 [US3] Run all local and hosted release gates; record observed results in specs/005-model-host-readiness/validation.md and open the dedicated PR. (FR-008–009)
- [ ] T012 [US3] After green latest-head and merged-main CI, deploy the approved immutable revision with backup/rollback safety; verify production health/authenticated discovery and record deployed revision in the PR and completion report. (FR-009)

## Dependencies and Strategy

T001 → T002 → T003 → T004 → T005 → T006; then T007 → T008 → T009; T010 → T011 → T012. Node/Python tests and implementations can be parallelized across separate files after contracts are fixed. US1 is the internal MVP, not deployable until UI/recovery/delivery checks finish. Administrative merge/deployment outcomes may be recorded in the PR/completion report rather than a self-referential pre-merge source revision.

## Read-only Analysis

FR-001–004 and FR-010 map to foundation (including tests/readiness-observer.test.js and shared parity fixtures); FR-005–006 to US1; FR-007–008 to US2; FR-009 to US3. All success criteria have test/release tasks. No unresolved clarification or constitutional exception; requirement checklist is 16/16 passing. No extension hooks configured. Existing AGENTS.md deployment-policy edit was requested by the user and is carried into this release's operations documentation, not discarded.
