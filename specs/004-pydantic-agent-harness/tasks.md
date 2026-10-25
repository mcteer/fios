# Tasks: Pydantic AI Agent Harness

**Input**: Design documents in `specs/004-pydantic-agent-harness/`.
**Prerequisites**: spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md.
**Tests**: Mandatory under FR-010. Write failing tests before their implementation; never substitute a fake worker for real-Agent integration coverage.
**Status**: Implementation and mandatory validation complete (T001–T046). Feature commit/PR tracking is finalized in T047; production deployment is not part of this implementation checkpoint. See validation.md.

Format: `- [ ] Tnnn [P?] [USn?] Description with file paths`. `[P]` means different files can be worked on concurrently after the stated dependencies/gates, not permission to skip them. Requirements-checklist completion does not complete these tasks.

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Create root `pyproject.toml`, `.python-version`, `uv.lock` and `src/agent/fios_agent/__init__.py`: Python `>=3.11,<3.12`, exact pins `pydantic-ai-slim[openai]==2.61.0`, `openai==3.37.0`, `httpx2==2.16.0`, build backend `hatchling==1.32.4`; resolve with uv 0.13.5, package from `src/agent/fios_agent`, and verify frozen non-editable installation/import with isolated Python mode. No full distribution or unrelated extras. (FR-001, FR-013)
- [X] T002 [P] Update `.gitignore` and `.dockerignore` to exclude `.venv`, Python caches/build artifacts and local test data while retaining Python source, package metadata and `uv.lock`. (FR-008, FR-013)
- [X] T003 Add `scripts/test-agent.mjs` and `package.json` commands so `npm test` runs Node plus stdlib Python unittest, `test:agent` can run separately, and the configured/default Python executable is invoked without a shell; fail clearly when uninstalled. (FR-010, FR-013)
- [X] T004 [P] Extend `tests/mock-mlx.js` with SDK-compatible chunk fields, exact peer IDs, captured requests/connections, usage/reasoning/image scenarios, raw malformed/empty/missing-sentinel/[DONE]-only/tool outputs, delayed/hanging responses and request-count assertions; keep existing API/browser fixture behavior. (FR-003, FR-010)
- [X] T005 [P] Create synthetic `tests/fixtures/legacy-chat.json` with stable chat/message IDs, timestamps/order, complete/interrupted turns, text/PDF-extracted attachments and an inline image; record expected data hashes without copying production data. (FR-005, SC-003)

**Setup dependencies:** T003 follows T001. T002/T004/T005 are independent of each other and T001. No real models or production databases used.

## Phase 2: Foundational (Blocks All User Stories)

- [X] T006 [P] Add `tests/agent/test_protocol.py` covering version/type/extra-field rejection, UUID correlation, context schema, UTF-8 chunk boundaries, newline/CRLF handling and bounded pre-parse buffers per `contracts/agent-ipc.md`. (FR-008, FR-010)
- [X] T007 [P] Add `tests/agent-client.test.js` and `tests/fixtures/agent-worker.py` for startup/version failures, overlong frames, EOF, output backpressure, mismatched IDs, shutdown and unavailable-worker rejection; no model calls in these fake-process tests. (FR-007, FR-010)
- [X] T008 Implement strict request/event schemas in `src/agent/fios_agent/protocol.py`: `v: 1`, UUID `run_id`, model “Nonempty exact gateway ID, at most 1,024 UTF-8 bytes”, context “Ordered nonempty list; roles `user` or `assistant`; final item is `user`”, nonempty assistant strings, unknown fields rejected, fixed safe error codes and optional numeric HTTP status 400–599. Enforce 32 MiB request, 1 MiB event and 32 Ki UTF-16-unit output chunks before allocations grow unbounded. (FR-003, FR-008, FR-013)
- [X] T009 Implement matching incremental framing/validation in `src/agent/protocol.js`, including limits from T008, strict lifecycle event types/statuses, only one outstanding start frame and no unbounded pending frames. (FR-007, FR-008)
- [X] T010 Implement `src/agent/fios_agent/__main__.py` and `worker.py` control-reader foundation: ready after config/import validation with zero network requests, one active run, concurrent control processing, token allocated before later cancel commands, shutdown/stdin EOF cleanup, stdout protocol-only and safe stderr. Harness execution is connected in T019. (FR-007, FR-008, FR-009, FR-014)
- [X] T011 Implement `src/agent/client.js` supervisor foundation: fixed installed `-I -m fios_agent` entry, `shell: false`, minimal child environment, operator-only `FIOS_AGENT_PYTHON`, 10-second readiness timeout, drain-aware writes, one active run, fail-closed unavailable state, single new-request restart attempt, and reap on shutdown. No direct inference or automatic replay. (FR-002, FR-007, FR-008, FR-013)
- [X] T012 Run foundational tests and package import checks; record actual results and unresolved compatibility failures in `specs/004-pydantic-agent-harness/validation.md` before connecting inference. (FR-010)

**Foundation dependencies:** T006/T007 may be authored together. T008 follows T006; T009 follows T007. T010 follows T008; T011 follows T009. T012 waits for all. This phase establishes testable lifecycle/contracts, not completed user inference.

## Phase 3: US1 — One Consistent Model Interaction Path (P1, Internal MVP)

**Goal:** authenticated text chat through a real Pydantic Agent using exact local/peer IDs and no fallback.
**Independent test:** real worker plus mock gateway; one request per send, incremental answer, successful completion, missing worker/upstream failures without retries/bypass.

### Tests first

- [X] T013 [P] [US1] Add `tests/agent/test_harness.py` for explicit provider/Chat Completions selection, exact IDs, zero SDK/Agent retries, one-request/tool-zero budgets, text start/delta deduplication, safe errors and rejection of tool output; disable non-mock model requests. (FR-001, FR-002, FR-003, FR-011)
- [X] T014 [P] [US1] Add `tests/agent-api.test.js` using actual Python Agent + mock MLX + isolated DB: local and peer text streaming, one request on 429/503/timeout, missing worker/no fallback, removed-model revalidation, recoverability on next new request, and no duplicated assistant rows. (FR-002, FR-003, FR-010, SC-001, SC-005)
- [X] T015 [P] [US1] Add `tests/agent/test_transport.py` for byte-fragmented SSE, CRLF, `[DONE]`-only success, usage-only chunks, missing `[DONE]` even with a finish reason, invalid/empty/oversized frames and stream cleanup. (FR-004, FR-007, FR-010)

### Implementation

- [X] T016 [US1] Implement `src/agent/fios_agent/transport.py` as an HTTPX2 stream observer consumed by the SDK, not another request client: `[DONE]` observed before yield, 4 MiB upstream frame cap, genuine activity only, 10s connect/30s write/180s read limits, no redirects/proxy inheritance, safe failure codes and no body logging. (FR-007, FR-008, FR-014)
- [X] T017 [US1] Implement text history mapping in `src/agent/fios_agent/context.py`: prior user/assistant roles/order preserved, final user prompt removed from history and sent once, existing Fios instruction supplied once. Until T026, reject image parts explicitly rather than omit them; this MVP is not a production replacement. (FR-005)
- [X] T018 [US1] Implement `src/agent/fios_agent/harness.py` with `Agent`, explicit MLX-only `OpenAIChatModel`/`OpenAIProvider`/`AsyncOpenAI`, selected pins, exact IDs, `max_tokens=8192`, merged leading system instruction, standard usage-only chunks, no continuous stats, zero retries and `UsageLimits(request_limit=1, tool_calls_limit=0)`. Map `run_stream_events()` text without duplicating initial/final content; terminal success requires final Agent result plus sentinel; reject tools/unsupported outputs. (FR-001, FR-002, FR-003, FR-004, FR-011)
- [X] T019 [US1] Connect worker run dispatch/event emission in `src/agent/fios_agent/worker.py`, preserving one active run, strict run ID matching, safe terminal errors, no automatic replay and context-owned SDK stream cleanup. (FR-002, FR-007, FR-014)
- [X] T020 [US1] Replace direct `/chat/completions` fetch/parsing in `server/index.js` with `src/agent/client.js`; retain fresh catalog/vision checks, pre-dispatch abort checks, reservation, transactional persistence and browser meta/delta/error/done shapes. Return safe 503 before persistence when unavailable; terminalize after-header failures. Remove obsolete inference-only `sseData` code/imports from `server/lib.js` and adjust `tests/unit.test.js` if unused, retaining `buildContext`. (FR-002, FR-003, FR-004, FR-008, FR-009)
- [X] T021 [US1] Run real-harness US1 API tests and existing text-chat tests; record one-attempt/no-bypass evidence in `specs/004-pydantic-agent-harness/validation.md`. Stop for explicit design revision if pinned provider compatibility fails; do not add a fallback or silently upgrade. (FR-010, SC-001)

**Checkpoint:** text-only internal MVP verified. Do not deploy until US2 parity and release gates pass.

## Phase 4: US2 — Existing Conversation and Interaction Parity (P1)

**Goal:** preserve attachments/history/reasoning and safe cancellation/persistence.
**Independent test:** pre-upgrade fixture continuation, valid images/PDF/text, transient reasoning, stop/fault injection, reload/restart/deletion through the real worker.

### Tests first

- [X] T022 [P] [US2] Add `tests/agent/test_context.py` for role/order and once-only current prompt, exact document wrappers, MIME/base64/signature/size validation, inline image fidelity, no remote image fetch, text limits measured as UTF-16 units, and empty/oversized/invalid context rejection. (FR-005, FR-006)
- [X] T023 [P] [US2] Add `tests/agent/test_worker.py` for immediate pre-start stop, text/thinking cancellation, completion races, stdin EOF, shutdown and no double terminal event; extend Node fake-process lifecycle tests in `tests/agent-client.test.js` for a wedged worker and reaping deadlines. (FR-007, SC-004, SC-005)
- [X] T024 [P] [US2] Add `tests/agent-persistence.test.js`: construct legacy fixture in its isolated DB, stop before reopening, assert 100% existing record/blob fidelity, continue once, retain partial answer across worker failure and app restart, recover stale streaming state, preserve ordering, then verify cascade deletion. (FR-005, SC-003)
- [X] T025 [P] [US2] Add `tests/browser/agent.spec.js` and configure `playwright.config.js` to use installed real worker with existing mock services/isolated DB. Cover streamed text/reasoning, model selection, image/text/PDF validation, Markdown/code copy, errors, stop, reload/deletion, desktop/mobile; retain existing catalog tests. (FR-004, FR-005, FR-006, SC-002)

### Implementation

- [X] T026 [US2] Complete `src/agent/fios_agent/context.py` multimodal translation using `BinaryContent`, not upload/remote-image APIs. Preserve “at most 400,000 UTF-16 code units” aggregate text, “at most 20 MiB” aggregate decoded images, “at most 10 MiB” per image and MIME allowlist `image/png`, `image/jpeg`, `image/webp`, `image/gif`. Keep Node limits of five files, 10 MiB/file, 20 MiB/upload and 100,000 UTF-16 units per message/extracted document in `server/lib.js`/`server/attachments.js`; fix only demonstrated parity gaps, with no schema change. (FR-005, FR-006)
- [X] T027 [US2] Extend `src/agent/fios_agent/harness.py` to map thinking start/delta parts separately, enforce “at most 500,000 UTF-16 code units” combined answer/reasoning, reject all tool/non-text outputs and use a fresh cancellation token per run; never persist/replay reasoning or append aggregate final output. (FR-004, FR-007)
- [X] T028 [US2] Complete active cancellation/control cleanup in `src/agent/fios_agent/worker.py`: cancel the current token while still reading controls, close upstream/client resources, and acknowledge only after cleanup; wrong/stale IDs are no-ops. (FR-007)
- [X] T029 [US2] Complete `src/agent/client.js` stop/disconnect/idle/shutdown handling: 180s real-upstream idle watchdog, SIGTERM after 1s and SIGKILL after 1.5s without acknowledgement, reap and release within 2s in controlled tests, discard late frames, no orphan/replay, and exactly one terminal result. (FR-007, SC-004)
- [X] T030 [US2] Finalize `server/index.js` browser event/persistence mapping: preserve 15s keepalives and periodic answer saves, transient reasoning, stop-winning `interrupted` versus worker-error `error`, safe errors followed by one done, and slot cleanup even during upload/catalog cancellation. Retain `server/store.js` schema and stale-stream recovery unchanged unless a tested parity fix is required. (FR-004, FR-005, FR-007)
- [X] T031 [US2] Add `tests/agent-boundaries.test.js` using actual worker/mock transport for maximum image/Unicode envelopes, output bounds, slow consumers, 180s-idle behavior with test-only shorter injected deadlines, no-first-token stops, disconnects and no automatic retries. (FR-006, FR-007, SC-004, SC-005)
- [X] T032 [US2] Run US2 suites plus existing API/browser regressions, record stop latency, fixture parity and failed/pending cases in `specs/004-pydantic-agent-harness/validation.md`; do not claim real image understanding from mock payload fidelity. (FR-010, SC-002, SC-003, SC-004, SC-005)

**Checkpoint:** complete current UX/data parity through harness, independently tested; no production upgrade yet.

## Phase 5: US3 — Maintainable Mandatory Boundary (P2)

**Goal:** enforce one private inference path and ship it reproducibly without weakening security or operations.
**Independent test:** boundary inspection plus real-worker auth/non-inference/privacy tests and hardened isolated image acceptance.

### Tests first

- [X] T033 [P] [US3] Add `tests/agent-security.test.js` verifying denied auth/origin requests and health/catalog/CRUD trigger zero model calls, unavailable harness does not break those operations, only allowlisted environment reaches the child, no listener/remote-image fetch/cloud fallback exists, and prompt/key/response markers never reach captured logs or browser assets. (FR-008, FR-009, FR-014, SC-006)
- [X] T034 [P] [US3] Add `scripts/check-agent-boundary.mjs` and assertions in `tests/agent-client.test.js` to enforce no direct inference code outside `src/agent/fios_agent`, no frontend agent import, no tool registration/unrelated provider extras, and no browser dependency on Python sources; allow model discovery and explicitly identified test fixtures. Pair static checks with runtime no-bypass tests, not grep alone. (FR-002, FR-011, FR-013)

### Implementation

- [X] T035 [US3] Review/harden `src/agent/client.js`, `src/agent/fios_agent/worker.py`, `harness.py` and `transport.py` against T033: MLX-only explicit endpoint/key, no embedded URL credentials/query/fragment, no redirect/proxy/cloud-env fallthrough, no telemetry/price refresh, stdout-only framing and stderr run-ID/phase/count/code diagnostics without content/raw exceptions. (FR-008, FR-014)
- [X] T036 [US3] Update `Dockerfile`/`compose.yaml` for Python 3.11 and frozen non-editable venv plus copied Node bridge in final image, pin/review base digests and record Python runtime package version; preserve UID 1000, read-only root, tmpfs, limits, init, localhost port and the existing data volume. No writable bytecode caches, runtime downloads, new ports or Python DB access. (FR-001, FR-008, FR-012, FR-013)
- [X] T037 [US3] Create `tests/compose.agent.yaml` and `scripts/check-agent-container.mjs` for distinct test image/project, mock-only gateway, localhost-only test port, disposable unique volume and cleanup; test readiness, no-inference health, streaming, shutdown/parent death/reaping and non-root/read-only execution on ARM64. Never stop production or reuse its database. (FR-008, FR-009, FR-010, FR-012)
- [X] T038 [US3] Re-run live-catalog regression in `tests/api.test.js`, `tests/browser/catalog.spec.js` and new non-inference/security tests; preserve spec 003 polling/peer ID behavior and prove no new request occurs merely from readiness/import/discovery. (FR-003, FR-009, SC-006)
- [X] T039 [US3] Document Python setup, config defaults, diagnostic codes, liveness versus readiness, no retries, explicit model selection, stop/recovery, backup and rollback in `README.md` and `.env.example`; add permanent mandatory harness/`src/agent/` guidance and Python validation commands to `AGENTS.md`, preserving per-spec branch/PR policy. Never include actual secrets. (FR-011, FR-012, FR-013, FR-014)
- [X] T040 [US3] Reconcile `docs/adr/0002-pydantic-agent-harness.md` and `specs/004-pydantic-agent-harness/{plan.md,research.md,quickstart.md}` with implemented decisions/evidence and link ADR/spec from `README.md`; keep ADR Proposed until reviewer acceptance is recorded. (FR-012)
- [X] T041 [US3] Run US3 tests and record actual private-boundary, no-telemetry/no-inference and hardened-image evidence in `specs/004-pydantic-agent-harness/validation.md`. (FR-010, SC-001, SC-006)

## Phase 6: Polish and Release Gates

- [X] T042 Run `npm ci`, frozen Python install, `npm test`, `npm run build` and `npx playwright test` per `specs/004-pydantic-agent-harness/quickstart.md`; record exact outcomes and remaining failures in `validation.md`, keeping unit/mock/browser evidence distinct. (FR-010, SC-001–SC-006)
- [X] T043 Review `package-lock.json`/`uv.lock`, run `npm audit` and pinned pip-audit against the installed Python environment, and record findings/remediation in `specs/004-pydantic-agent-harness/validation.md`; no unreviewed dependency upgrades or secret output. (FR-001, FR-008)
- [X] T044 Run `docker compose config --quiet`, boundary checker and isolated container checker; extend `scripts/check-agent-container.mjs` as needed to measure worst-case accepted Unicode/image input and slow-consumer memory under 1 GiB/2 CPU, image import readiness and stop deadlines; record actual results in `specs/004-pydantic-agent-harness/validation.md`. (FR-007, FR-010, FR-012, SC-004)
- [X] T045 Rehearse stop/backup/recreate/rollback against only the disposable volume via `scripts/check-agent-container.mjs`, never two instances on one DB; document old/new image references, data fidelity and cleanup in `specs/004-pydantic-agent-harness/validation.md`. (FR-005, FR-012, SC-003)
- [X] T046 Review all feature artifacts for stale claims and unchecked failures, run diff/link checks, and update `specs/004-pydantic-agent-harness/tasks.md`/`validation.md` honestly. Leave optional real inference and production deployment explicitly unverified unless separately approved and observed with `scripts/check.mjs`; do not load a large cold model. (FR-010, FR-012)
- [ ] T047 Commit completed feature work on `004-pydantic-agent-harness` and open its PR targeting `main`, linking `specs/004-pydantic-agent-harness/spec.md`, ADR 0002 and validation evidence; include the pending `AGENTS.md` per-spec branch/PR rule and identify it in the PR. No direct main commit or merge without review/approval. (project governance)

## Dependencies and Execution Order

```text
Setup T001–T005
  → Foundation T006–T012
  → US1 T013–T021 (internal text MVP)
  → US2 T022–T032 (required regression parity)
  → US3 T033–T041 (required release/security/operations)
  → Release T042–T047
```

Within US1: T013/T014/T015 can be authored together. T016 follows T015; T017 follows foundation; T018 requires T013/T016/T017; T019 requires T018; T020 requires T019 and T014; T021 waits for all.

Within US2: T022–T025 can be authored together after US1; T026 follows T022, T027 follows T026 and existing harness tests, T028 follows T023/T027, T029 follows T023/T028, T030 follows T029, T031 follows completed lifecycle/context, and T032 waits for all.

Within US3: T033/T034 can be authored together (distinct test files); T035 follows both; T036 follows proven runtime; T037 follows T036; T038 follows T033/T035; T039 follows stable configuration; T040 follows docs/implementation; T041 waits for all. Security is foundational—this phase verifies/hardens it, not permission for insecure earlier implementations.

Shared `worker.py`, `harness.py`, `client.js` and `server/index.js` changes are deliberately sequential across stories. The stories have independent acceptance suites, but this migration's implementation is cumulative, not three independently deployable products.

## Parallel Examples

- **US1:** author Python harness tests T013, real-worker API tests T014 and transport tests T015 concurrently in separate files after foundation.
- **US2:** author context T022, lifecycle T023, persistence T024 and browser T025 suites concurrently after US1; do not edit their shared mocks simultaneously.
- **US3:** author security T033 and boundary guard T034 concurrently after US2; serialize hardening of shared runtime files afterward.
- **Setup:** ignore rules T002, mock fixtures T004 and legacy data fixture T005 can proceed while packaging T001 is resolved.

## Implementation Strategy

1. Freeze/review dependencies and protocol first; demonstrate the real Agent reaches the mock using the pinned SDK.
2. Deliver the US1 text MVP for internal validation only; no production cutover while image/history/stop parity is pending.
3. Complete US2 and US3 before release. Keep the public browser API and database schema stable.
4. Pass all mandatory isolated checks and rollback rehearsal; request review through the feature PR. Actual deployment remains a separate approved operation with a backup, not an effect of marking planning tasks complete.
