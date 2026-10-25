# Quickstart and Validation Guide — 004

**Status:** implemented validation/run guide. See validation.md for observed test results and remaining operational limits. These commands do not authorize replacing production; run the isolated suite first and deploy only after review/approval and a backup.

## Prerequisites and setup

- Work on `004-pydantic-agent-harness`, not `main`; deliver through its reviewed PR.
- Node 24.15.0, CPython 3.11.17, uv 0.13.5, OrbStack/Compose and installed Playwright browser.
- Do not print `.env`, resolved Compose output or credentials. Existing production can stay up while isolated tests use different ports/data.
- Implemented Python packaging must include `src/agent/fios_agent`; no runtime dependency resolution.

Install the pinned runtime and locked project package:

```sh
npm ci
uv python install 3.11.17
uv sync --locked --no-editable
npm test
npm run build
npx playwright test
npm audit
uvx --python 3.11.17 --from pip-audit==2.10.1 pip-audit --path .venv/lib/python3.11/site-packages
docker compose config --quiet
node scripts/check-agent-boundary.mjs
node scripts/check-agent-container.mjs
```

`npm test` will run both the Node suite and Python unittest suite via `scripts/test-agent.mjs`. For focused Python tests: `npm run test:agent`. Use `FIOS_AGENT_PYTHON` for an operator-selected interpreter if not using the documented default `.venv/bin/python`; it must have the package installed, not merely the dependencies. Production uses `/opt/venv/bin/python`. Keep package installs non-editable so isolated Python mode can import the installed package. After editing Python source, rebuild with `uv sync --locked --no-editable --reinstall-package fios-agent`. The container script expects an already-built prior image (default `fios:0.1.0`); set `FIOS_AGENT_ROLLBACK_IMAGE` to an appropriate prior image when rehearsing later releases.

Expected: all mandatory checks pass, advisories are reviewed, container tests use only mock MLX and a unique disposable volume, and no production data is opened. The container script uses `tests/compose.agent.yaml`, a distinct image tag/project, localhost-only test port, and guaranteed cleanup; it never invokes production `compose down` or reuse `fios_fios-data`.

## Scenario 1 — Mandatory path and exact IDs (US1)

Run `node --test tests/agent-api.test.js` after setup. The suite starts its own mock MLX, Express, real Python worker and temporary DB. Submit one local and one peer-qualified mock model. Expect exactly one captured upstream request per accepted message, exact model bytes, visible incremental answer and one final state. Return 503/429/timeouts and verify no retry. Kill/disable worker and verify no direct request; a subsequent new request can recover. A fake worker alone is not acceptable proof of harness traversal.

## Scenario 2 — Context and UI parity (US2)

Run `node --test tests/agent-persistence.test.js` and `npx playwright test tests/browser/agent.spec.js`. Use the synthetic legacy fixture, never a production DB copy. Verify saved messages/attachments survive, continuation includes each turn once, extracted text/PDF wrappers are unchanged, images arrive as inline image content, text-only models reject image histories, and Markdown/copy/stop controls behave as before. Reasoning is shown transiently and does not appear in the saved answer or subsequent model context.

## Scenario 3 — Stop, corrupt streams and recovery (US2)

The API/worker tests exercise slow streams, no first token, missing `[DONE]` (even with a finish reason), `[DONE]`-only valid streams, usage-only chunks, malformed events, unexpected tools and process death. Stop from before dispatch, during text/reasoning and at completion. Assert one terminal outcome, upstream disconnect plus `generating: false` within two seconds in controlled tests, no duplicates, partial text retained, and the next valid message succeeds. Use short injected test deadlines for the 180-second idle watchdog, never shorten production behavior.

## Scenario 4 — Boundary/security and deployment (US3)

Run boundary and container scripts. Verify authentication/origin failures yield zero model requests; health/catalog/CRUD work without a ready worker and invoke no inference; worker stdin EOF/SIGTERM/parent death leave no orphan; no Python listener exists; secrets/prompt markers do not appear in captured logs or browser assets. Max-size image/Unicode inputs and a slow stream consumer must remain bounded under the existing 1 GiB/2 CPU limits. Verify installed package imports on ARM64 Linux with a read-only root and no writable Python cache requirement.

## Backup, release and rollback rehearsal

Before any approved production upgrade, use the stop/backup procedure in [README](../../README.md); retain the previous image reference. Rehearse on a disposable test volume first: stop old instance, back up, run new image, stop it, run previous image, then verify history. Never open the same SQLite file from two app instances. No schema change is planned. Do not delete the detached Open WebUI volume. If prerequisite/compatibility tests fail, stop and update the plan rather than deploy a bypass.

## Live discovery and optional inference

After an approved deployment, `node scripts/check.mjs` checks authentication and real gateway discovery without loading a model. Record actual counts/peers, not assumptions. Real inference is separate and opt-in:

```sh
node scripts/check.mjs 'EXACT_MODEL_ID'
```

Replace the placeholder with an already-loaded or suitably small model's exact advertised ID. Do not select a large cold Studio model to prove this migration. Report real cancellation/image/model compatibility only when observed; mock evidence does not establish native cluster or RDMA behavior.

## Troubleshooting

- Health passes but generation fails: `/health` is app liveness. Check safe worker phase/error codes and the Python binary/package installation; no model request should be needed for readiness.
- Worker unavailable: check installation/permissions/versioned handshake; do not bypass it or loop-replay requests.
- Gateway HTTP/timeout error: inspect safe numeric status and existing native service connectivity. No SDK retry occurs.
- Incomplete response: retain partial text and report missing completion; do not mark it complete solely because EOF was clean.
- Missing peer models: discovery is still owned by MLX; this feature does not change network discovery or RDMA.
