# Spec 1 tasks and handoff

Checked items have implementation or verification evidence in this checkout and the dated handoff below. Open items identify acceptance evidence still needed. IDs T005–T014 belong to the subsequent roadmap.

## Phase 1 · Setup

- [x] T001 Protect local credentials in `.gitignore` and `.dockerignore`, pin the development tools in `.specify/requirements-macos-arm64-py315.txt` and initialize the Codex integration (FR-006).

## Phase 2 · Foundation

- [x] T002 Publish atomic samples in `src/backend/host_agent.py` and validate bounded files in `src/backend/inventory.py` under the [data-model.md](data-model.md) definitions for `Host.id`, `Host.hardware`, `Host.chip`, `Host.role`, `Host.configured_gb`, `Observation.version`, `Observation.node`, `Observation.sampled_at`, `Observation.memory_bytes`, `Observation.logical_cpus` and `Observation.load_1m` (FR-001–003).

## Phase 3 · US1 cluster inventory

Independent test: render the overview against a temporary observation directory with a controlled read time. The three host cards, measurements, labels and reporting count must match each case in SC-001 and SC-002.

- [x] T015 [US1] Derive [data-model.md](data-model.md) fields `Host.state` and `Host.observation` in `src/backend/inventory.py` and render their labels and count in `src/frontend/dashboard.py` (FR-001–003).
- [x] T016 [P] [US1] Extend the rendered-view assertions in `tests/test_foundation.py` to check three awaiting hosts, fresh at 30 seconds, stale at 31 seconds with retained measurements, and invalid data with no measurements. Assert the count in every case (SC-001–002).

## Phase 4 · US2 local operator access

Independent test: run inventory reads and rejected requests against a disposable local server. Compare response contents and sample bytes.

- [x] T003 [US2] Gate the dashboard and inventory routes in `src/backend/core.py` on the [data-model.md](data-model.md) definition of `Operator.role`, bind loopback and mount observations read-only in `compose.yaml` (FR-004–005).
- [x] T017 [US2] Extend the access checks in `tests/test_foundation.py` to assert that denied responses contain no fixture observations and attempted writes leave the fixture intact. Exercise the write methods in [the contract](contracts/inventory.md) (SC-003).

## Phase 5 · US3 reproducible workspace

Independent test: follow [quickstart.md](quickstart.md) on a clean supported checkout, including its first live observation and feature resolution.

- [x] T004 [US3] Document local startup in `README.md`, and record candidates, admission criteria and release risks in `specs/001-platform-foundation/research.md` and the roadmap below (FR-006–007).
- [x] T018 [P] [US3] Exercise `specs/001-platform-foundation/quickstart.md` end to end from the same clean checkout. Record dashboard, advancing sample and active feature results in this handoff. Use an isolated local development session or a planned preview restart to avoid a port conflict (SC-004).

## Phase 6 · Final acceptance

- [x] T019 Run `make check` via `Makefile` after T016–T018, review FR-001–007 and SC-001–004, and record the results in `specs/001-platform-foundation/tasks.md`.

## Dependencies and delivery order

T001 supplies development tooling. T002 supplies the data contract for US1 and US2. The minimum operator delivery combines T015 and T003 so the first visible inventory is access-controlled. T004 documents that delivery. T016 and T017 touch the same test file and should land serially. For US1, rendered-fixture work can run alongside US3 checkout preparation. For US2, denial tests can run alongside US3 documentation verification. For US3, use a separate machine or isolated session for T018 while the local test suite runs. Final acceptance waits for all three stories.

## Following milestones

| Task | Depends on | Deliverable and verification |
| --- | --- | --- |
| T005 Machine identity and enrollment | T003 | Native foreground agent to supervised launchd service on each approved host, pinned machine credentials, revocation and replay-resistant heartbeats. Reject unknown hosts and stale epochs. |
| T006 Core job ledger and scheduling | T005 | SQLite jobs, events, reservations and usage. Test simultaneous admission, expiry, idempotent retry, restart, cancellation, idle TTL and backpressure with a fake native worker. |
| T007 First private chat and coding | T006 | Mini MoE and Studio Qwen model/runtime qualification. Fixed-prompt quality, RAM, compatibility and cancel/stream tests before enabling aliases. |
| T008 Paired Studio inference | T007 | Compare MLX-Serve, EXO and MLX distributed on the actual cable. Verify both ranks, transport and cleanup after worker/link loss. |
| T009 Operations | T006–T008 | Extend inventory into live operational metrics and token ledger. Add role-checked drain, unload and signed/pinned update/rollback jobs. Rehearse a failed update on one idle host. |
| T010 Project library and narration | T007 | Durable owner-scoped Projects, canon, source history, session notes, DM/player views, homebrew presets and export. Test recovery and spoiler-free output. |
| T011 Search | T007 | Explicit query preview/consent, provider adapter, citations, bounded egress, quotas and failure handling. Verify synthetic retrieval injections cannot call tools. |
| T012 Review and sandbox | T006, T007 | Static defensive checks first. Qualify isolation before exposing the explicit sandbox-run UI. Test containment, limits, cancellation and deletion with harmless probes. |
| T013 Art and content controls | T006, T010 | Evaluate classifications before enabling generation. Test Z-Image-Turbo, anatomy, style/ratio presets, publication policy and handout export. Cover every role and retrieval/export path. |
| T014 Public identity and release | T008–T013 | Google OIDC, scoped keys, TLS ingress, ownership migration, permissions and abuse controls. Rehearse key revocation, access denial, rollback and backup restore before publication. |

T010–T012 can progress separately once dependencies pass. T013 safety design can start alongside T010. Public exposure is last.

## Verification and resumption · 2026-11-27

- F1. A native Mini sample matched the container API field for field. The only reporting node was fios-core, with 24.0 GiB observed physical memory and 12 logical CPUs. Both Studios were awaiting observations. The native watch loop produced two distinct samples and exited on interrupt.
- F2. The OrbStack health check passed. Loopback HTTP succeeded. Sample reads with an invalid bearer, foreign authority/origin or forwarded identity were denied. Connections to port 8741 via both non-loopback IPv4 addresses of this Mac were unavailable. This check did not probe from a separate LAN machine. Inspected runtime settings showed UID 65532, read-only root, all capabilities dropped, no new privileges and one read-only observation mount.
- F3. `make check` passed the upstream Spec Kit validator, seven unittest cases and Compose validation. All seven tests also passed inside the pinned container image. WebKit rendered the dashboard at 1100 and 375 CSS pixels with all three hosts, the stylesheet active and no horizontal overflow. The image contained only the six intended application files under /app. The Git ignore check passed for .env.local. Python syntax, common credential-pattern and local documentation-link checks passed.
- Review. Separate requirements, code and security passes found and corrected two bootstrap issues before handoff: requests presenting unsupported bearer credentials now fail closed, and new observation exports remain readable by the unprivileged core under a restrictive umask. There was no independent reviewer or configured SAST/SCA scanner in this initial checkout. The local credential-pattern check is limited. Add pinned code and image scanning before a release.
- Limits. The framework validation used local telemetry and no model weights. It provides no measurements for Studio capacity, RDMA, inference speed, creative model quality, moderation accuracy or sandbox containment. Public access, account migration and host updates are later milestones. The temporary verification service was stopped.
- Next executable task. T005 starts with the agent enrollment and heartbeat contract and tests using two synthetic host identities. Before live enrollment, confirm the operator's Studio identities and trust anchor. T006 can then implement leases against the enrolled test workers.

## Framework and local preview · 2026-11-27

- The official Specify CLI v1.4.5 initialized this checkout with Codex as its default integration. Codex listed all nine enabled project skills. The planning helper resolved the existing spec and plan. A clean local copy passed the locked tool install, integration checks, seven application tests and Compose validation.
- Application source now lives under `src/frontend`, `src/backend` and `src/agent`. The native host sampler belongs to the backend. The AI harness currently provides authoring configuration.
- At handoff, OrbStack reported Compose project `fios`, container `fios-core-1`, healthy. The Mini's native sampler advanced by five seconds across observations. WebKit rendered the local dashboard at desktop and phone widths. Both Studios were awaiting measurements. Use `make dashboard` to start the preview and `make dashboard-stop` to stop it.
- The next product milestone remains T005, authenticated Studio enrollment. Passwordless SSH access is available for later host work.

## Spec 1 final acceptance · 2026-11-27

- SC-001 and SC-002 passed through the HTTP dashboard. Three cards render for empty, fresh, stale and malformed fixtures. The count drops from one at 30 seconds to zero at 31 seconds, while stale measurements remain visible. Invalid samples display no measurements.
- SC-003 passed through HTTP for the HTML and JSON reads. Denied requests returned only the denial message. POST, PUT, PATCH and DELETE returned 405 and left the observation directory and sample bytes intact.
- SC-004 passed from one clean copy of the repository with no existing virtual environment, active feature pointer, observations or environment file. Locked tool installation, feature resolution, Compose build and health, matching HTML and JSON measurements, and an advancing Mini timestamp all passed. The temporary preview and sampler were removed. The original preview was restored and checked healthy.
- Final review mapped FR-001–007 to the tests, quickstart and research. `make check` passed all nine tests, Spec Kit validation and Compose configuration. All nine tests also passed in an isolated, network-disabled container using the dashboard image and read-only test fixtures. Python syntax checks passed. No dedicated security scanner is configured in this checkout.
- All nine foundation tasks are complete. T005 authenticated Studio enrollment remains the next roadmap milestone.
