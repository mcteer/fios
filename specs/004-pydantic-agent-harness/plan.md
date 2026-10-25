# Implementation Plan: Pydantic AI Agent Harness

**Branch**: `004-pydantic-agent-harness` | **Date**: 2026-10-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-pydantic-agent-harness/spec.md`

## Summary

Replace Express's direct chat-completions request with a mandatory Pydantic AI Agent running in a supervised Python worker. Use the slim OpenAI extra and retain the existing MLX gateway. Keep all agent runtime code, including the Node bridge, in `src/agent/`. Express continues to own authentication, model discovery, uploads, SQLite and public SSE; the UI stays unchanged. Private inherited pipes provide the only worker interface—no new listener, sidecar, or database writer. This is a migration, not an autonomous-tool feature.

## Technical Context

**Language/Version**: existing JavaScript/React and Node 24.15.0; Python `>=3.11,<3.12`; pin managed CPython 3.11.17 in the Bookworm production image and local `.python-version`.

**Primary Dependencies**: `pydantic-ai-slim[openai]==2.61.0`, `openai==3.37.0`, `httpx2==2.16.0`; `uv==0.13.5`, build backend `hatchling==1.32.4`. Existing npm pins unchanged except intentional lock maintenance. Root `pyproject.toml` and `uv.lock`; frozen installation, no runtime downloads. Managed CPython 3.11.17 and Node/uv image digests are pinned at packaging time; the Python runtime is copied from a build stage, with downloads disabled at runtime.

**Storage**: current SQLite schema and attachment blobs; Node is the sole owner. No Pydantic transcript store, new schema, or data migration.

**Testing**: stdlib Python unittest/async tests, Node test runner, existing Playwright suite, real Python-worker integration against mock MLX, isolated container acceptance. Python advisory scan uses pinned `pip-audit==2.10.1` against the resolved environment.

**Target Platform**: non-root ARM64 Linux container under OrbStack, native macOS development/test; MLX inference stays native on the existing hosts.

**Project Type**: existing single-user web app with private agent subprocess.

**Performance Goals**: incremental content before completion; stop cancels the mock upstream request and releases the slot within two seconds; no additional inference calls; remain within existing 1 GiB/2 CPU container limits under maximum accepted input tests.

**Constraints**: one global active generation, no inference retries, no model substitution, no tools or cloud fallback, no public/LAN worker ports, no production DB access by tests. Existing 180-second idle limit, 8,192 output tokens, and 500,000 combined output UTF-16 code-unit limit preserved. Detailed limits and wire behavior are in the contracts.

**Scale/Scope**: current chat only; future model-generating features must use this boundary but are not implemented here.

## Constitution Check

| Principle | Before research | After design |
| --- | --- | --- |
| Specification first | Pass: numbered spec and user source-path constraint recorded on dedicated branch. | Pass: spec, research, contracts, tasks and validation plan precede code; merge via reviewed feature PR. |
| Purpose-built frontend | Pass: preserve the custom UX; no Open WebUI revival. | Pass: existing browser SSE/interaction contract retained; chosen dependencies pinned and researched. |
| Native inference, isolated workloads | Pass: orchestration only, no cluster changes. | Pass: Python runs client-side orchestration in container; MLX/RDMA remain native and untouched. |
| Secure by default | Pass: existing auth and localhost binding retained. | Pass: inherited pipes only, no arbitrary commands/tools, minimal child environment, no telemetry, same non-root/read-only deployment. |
| Persistent and reproducible | Pass: SQLite remains canonical. | Pass: Node-only DB ownership; frozen Python/npm locks; backup and rollback steps required before deployment. |
| Verify honestly | Pass: no inference or compatibility claim from docs alone. | Pass: mock/unit/browser/container evidence tracked separately from opt-in real inference; no runtime tests yet. |

No constitution violations or exemptions. The Python process adds lifecycle complexity but does not change security or deployment boundaries. [ADR 0002](../../docs/adr/0002-pydantic-agent-harness.md) records the proposed integration design; acceptance is through this feature's PR, not assumed from authoring this plan.

## Project Structure

### Documentation (this feature)

```text
specs/004-pydantic-agent-harness/
├── spec.md
├── clarification.md
├── checklists/requirements.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/agent-ipc.md
├── contracts/browser-api.md
├── quickstart.md
├── tasks.md
└── validation.md
```

### Source Code (planned additions/changes)

```text
pyproject.toml                  # Python packaging; package source src/agent/fios_agent
uv.lock                         # full resolved dependency graph, committed during implementation
.python-version                 # 3.11.17
src/agent/
├── client.js                    # Node spawn/supervisor/framing/async run interface
├── protocol.js                  # Node protocol validation and bounds
└── fios_agent/
    ├── __init__.py
    ├── __main__.py              # fixed worker entry point, private pipes only
    ├── protocol.py              # strict Pydantic IPC envelopes/limits
    ├── worker.py                # control reader, one run, token/cancel/shutdown
    ├── harness.py               # Agent, model/provider settings, event mapping
    ├── context.py               # bounded history/image conversion
    └── transport.py             # HTTPX2 stream observer, sentinel/idle/framing guards
server/index.js                 # call bridge instead of raw inference; preserve API/storage
server/lib.js                   # buildContext retained; remove obsolete inference-only parser if unused
Dockerfile                     # add Python runtime, frozen venv, copy src/agent (not in dist)
compose.yaml                   # same hardened service/volume/port; fixed worker path if needed
.dockerignore / .gitignore      # exclude Python env/caches, not lock/source
package.json                   # test commands including Python; no agent browser import
scripts/test-agent.mjs          # choose configured Python binary, run unittest without a shell
scripts/check-agent-boundary.mjs # enforce no browser/Node direct inference bypass
scripts/check-agent-container.mjs # isolated hardened-image/rollback checks
AGENTS.md / README.md           # harness invariants, active feature pointer, operations
playwright.config.js           # use installed worker with isolated mock backend
tests/                         # existing tests retained; additions below (no extra production DB)
├── agent/*.py                  # protocol, context, harness, transport, worker tests
├── agent-client.test.js        # bridge framing/lifecycle fake-worker tests
├── agent-api.test.js           # real worker + mock MLX API coverage
├── agent-persistence.test.js   # pre-upgrade fixture, reopen/recovery/deletion
├── agent-boundaries.test.js    # maximum inputs, backpressure, deadline cases
├── agent-security.test.js      # auth, environment, privacy, non-inference behavior
├── agent-lifecycle.test.js     # crash/disconnect/parent-death/race/escalation tests
├── agent-support.js            # shared isolated test app lifecycle
├── compose.agent.yaml          # isolated mock-backed container test project
├── fixtures/agent-worker.py    # test-only process fault simulator
├── fixtures/agent-parent.mjs   # test-only parent-death simulator
├── fixtures/legacy-chat.json   # synthetic pre-upgrade records, no production data
├── mock-mlx.js                 # SDK-compatible envelopes and fault scenarios
└── browser/agent.spec.js       # browser regression on real harness/mock inference
```

**Structure Decision**: preserve existing frontend/server layout. Python packaging maps the `fios_agent` import package to `src/agent/fios_agent`; Node imports only `src/agent/client.js`. Agent source must never be imported from the Vite frontend or copied as a public asset. `tests/agent/` holds tests, not production implementation.

## Architecture and Execution

1. Node starts a fixed worker command (`FIOS_AGENT_PYTHON` executable, default `.venv/bin/python` locally and `/opt/venv/bin/python` in image; arguments `-I -m fios_agent`). Use installed non-editable package, `shell: false`, inherited private pipes, and an allowlisted environment containing only runtime necessities and explicit MLX settings—not session/access passwords or generic provider/proxy keys. The worker sends a versioned readiness frame within 10 seconds; imports/config checks must not call a model or fetch metadata.
2. Keep current authenticated multipart validation, 409 global reservation, fresh model-catalog revalidation and `buildContext`. Check abortion after upload/parse/catalog and before persistence/dispatch. Once validated, store user/attachments/assistant placeholder exactly as today. The worker cannot read/write SQLite. If unavailable before persistence, respond 503 without creating messages; failure after persistence ends the placeholder in `error`.
3. Send a bounded `run` frame with exact model and context. Python validates again, translates history, constructs Agent text output with unchanged Fios instructions, zero retries, one-request/tool-zero usage limits, explicit MLX provider and settings. No prefix parsing or credentials in protocol frames. Missing MLX API key uses a local placeholder, never a cloud credential.
4. Pydantic executes the sole model request. HTTPX2 observer detects `[DONE]`, malformed/oversized raw frames and actual upstream activity without generating its own requests. The Agent event mapper emits incremental text/reasoning, handles initial parts once, and accepts completion only after the final result AND sentinel. Tool parts trigger an error and cannot initiate tools or a second model request.
5. Node translates worker frames into unchanged browser SSE; preserves incremental answer persistence (at most one second between saves while deltas arrive), transient reasoning, 15-second browser keepalives, bounded output and single terminal finalization. Answer is not re-appended from the final Agent result. Browser disconnect, stop, idle timeout and app shutdown cancel the worker run. Partial answer text survives errors.
6. Supervisor correlates run IDs; rejects protocol mismatch/invalid frames; bounds queues and honors pipe backpressure; treats worker exit/EOF before terminal result as failure. Cancellation escalates at 1s/1.5s to terminate/kill then reap, keeping the controlled 2s limit. Worker recovery is one startup attempt on a subsequent new request, never an automatic replay or hot restart loop. Node shutdown cancels/reaps the child before closing SQLite/exit; worker exits on stdin EOF.

## Configuration, Security and Operations

- `MLX_BASE_URL` remains the only inference endpoint setting; validate http(s), reject embedded credentials, query/fragment, and disable redirect following and ambient proxy environment on the worker HTTP client. Neither IPC nor browser may supply an endpoint, Python command, system instruction, or credential.
- `MLX_API_KEY` remains optional and server-side; never log it, pass via arguments, or put it in the protocol. No Logfire exporter, automatic price refresh, remote file fetch/upload, cloud inference, MCP, or execution tools.
- `FIOS_AGENT_PYTHON` is operator-controlled, not request-controlled. Document local/image defaults and validate startup failures. Pin/install the package at build/setup time; no shell expansion or `uv run` dependency resolution in production startup.
- `/health` keeps its existing liveness behavior; it does not imply worker or MLX readiness. Catalog, login and CRUD can work with the worker unavailable. Handshake and failed generation diagnostics distinguish worker versus gateway faults without leaking internals to the browser.
- Structured stderr diagnostics: run ID, phase, elapsed time, counts and safe error code only. No raw provider errors/bodies, prompts, answers, thinking, attachments, environment dumps, or stack locals. stdout is protocol only and must not be forwarded to logs.
- Container retains one process supervisor (Node plus Compose init), UID 1000, read-only root, existing tmpfs/capabilities/memory/CPU settings and localhost port. Set Python no-bytecode/no-runtime-download behavior. Copy the installed Python package and Node bridge into the final image, not Vite assets.
- Before production replacement, stop the app and back up its volume per README. Do not touch the detached legacy volume. Roll back to the prior image with the same volume after stopping the new app; never run both against that SQLite file. No schema migration is planned.

## Delivery Phases and Gates

- **Phase 0 — Research (complete as documentation):** official tagged docs/source and current app behavior inspected; decisions in research.md. No runtime compatibility claim.
- **Phase 1 — Design (complete as documentation):** contracts, data model, ADR proposal, validation guide and constitution recheck produced.
- **Implementation setup/foundation:** resolve frozen dependencies, strict protocol and lifecycle, test fixtures. Prove real Pydantic/model-client compatibility against mock SSE before swapping production routing.
- **US1:** mandatory harness for local/peer text streaming; no bypass and one attempt. This is the internal MVP, not deployable until US2 parity is complete.
- **US2:** history/images/reasoning/cancellation/persistence parity and failure recovery.
- **US3:** enforce boundary, private configuration, privacy and hardened packaging/operations.
- **Release gate:** all mandatory regression checks, isolated hardened ARM64 image smoke, dependency reviews, backup/rollback rehearsal, then reviewed feature PR. Real inference is optional and explicitly selected; absent evidence must remain marked pending. No deployment in this planning session.

## Validation Strategy

See [quickstart.md](quickstart.md) and [validation.md](validation.md). Test the actual Python Agent in API/browser flows; fake workers are only for protocol fault injection. Count mock requests to catch SDK retries and unauthorized inference. Cover [DONE]-only success, usage-only chunks, missing sentinel even after finish reason, invalid JSON, empty streams, tool requests, slow/absent output, worker crashes/hangs and stop races. Compare stored pre-upgrade message/attachment data before and after, then check continuation and deletion. Test maximum Unicode/image context and backpressure under the existing container cap. Audit emitted logs and built browser assets for secret/content or worker-source leakage. Keep temporary test DBs separate and stop every instance before reopening its DB.

## Complexity Tracking

No constitution violations. Explicit cost: shipping/supervising Python and a small versioned IPC protocol. This is preferable to replacing the backend or introducing a network service for a single-user, single-run system.
