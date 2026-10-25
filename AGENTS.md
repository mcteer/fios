# Fios agent guidance

Read `.specify/memory/constitution.md` before changes. Follow upstream Spec Kit prompts in `.agents/commands/`; generic integration is intentional. Feature artifacts live in `specs/<number>-<name>/`. Resolve the active feature with `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` rather than assuming a fixed spec directory.

Fios is a custom React/Vite frontend and Express/SQLite backend. Open WebUI is retired; `specs/archive/001-open-webui/` is historical only. Do not restore that deployment. Preserve the purpose-built UX, local-first architecture and exact MLX model IDs.

## Spec branches and pull requests

Going forward, each spec must have its own dedicated branch and pull request. Before creating or changing a spec or implementing its work, create or switch to its branch (for example, `004-feature-name`). Keep that spec's artifacts, implementation, tests, and validation evidence together on the branch; do not combine unrelated specs in one PR. Open a PR targeting `main` that links the spec and summarizes changes, validation results, and any pending checks. Do not commit spec work directly to `main`; merge through the PR after review and approval. This policy applies to new specs and subsequent work on existing specs.

## Continuous integration

`.github/workflows/ci.yml` validates locked installs, Node 22/24 unit/API tests, build/boundary checks, Chromium regressions, npm/Python audits and a native ARM64 hardened-container recovery rehearsal. CI is mock-only: no production secrets, live MLX hosts, real inference or deployment. Keep actions SHA-pinned and permissions read-only; do not use `pull_request_target` to execute PR code with secrets. The aggregate `CI gate` must pass with every prerequisite successful on the exact latest PR SHA before merging; zero checks is not green CI. CI validates changes; the production delivery policy below defines the required deployment that follows a successful merge. Neither CI nor deployment authorizes cluster changes.

## Production delivery

A successful merge to `main` must lead to automatic production deployment after CI passes on the exact merged commit. Merge-only delivery is not the expected endpoint. Routine Fios application deployment under these safeguards does not require another approval after an approved merge.

Required sequence: merge → green `main` CI → build the exact merged revision → preserve the currently deployed image/revision → stop the application and back up its persistent data → deploy → verify application health and authenticated gateway discovery without inference. Build before stopping the application to minimize downtime. Serialize deployments and never open the same SQLite file from two application instances.

If deployment or verification fails, automatically restore the previous known-good application image/configuration and verify recovery. Restore the stopped-volume backup if data compatibility requires it; preserve the failed deployment's data for diagnosis rather than overwriting or deleting it blindly. Keep backups and rollback images until successful verification. If safe rollback cannot be completed, stop the rollout and report the failure explicitly.

Deployment must remain on the existing authorized application host, preserve credentials, authentication, localhost binding, persistent volumes and container hardening, and must not expose the Docker socket to the app or PR jobs. Automatic application deployment does not authorize MLX/RDMA changes, new remote-execution access, public/LAN exposure, real inference or removal of legacy data.

Keep CI and deployment status distinct in reports: identify the deployed commit and observed verification result. Green CI or a merged PR is not proof of deployment. If the deployment mechanism is missing, disabled or blocked, report that gap explicitly and do not call the delivery complete. Documentation alone does not implement automatic deployment.

## Model and host readiness

Express and the Python harness must independently gate the exact selected model on gateway/serving-host health and that host's own advertised model catalog. A cached peer entry is not proof of readiness. Unloaded but advertised on a healthy host means available on demand; discovery must never load models or run inference. Probe only explicit `MLX_PEER_URLS`; never follow catalog URLs or forward gateway credentials to peers.

The hardened production container cannot directly reach the Studio interfaces in the observed environment. `scripts/observe-hosts.mjs` performs native read-only checks and atomically shares metadata through a read-only directory bind, not a listener or Docker socket. Both runtimes must validate endpoint fingerprints and reject missing, malformed, future-dated or older-than-5-second observations. Unknown/unavailable targets cannot be sent and must not trigger fallback/substitution. Preserve this fail-closed behavior when changing discovery or the harness.

`node scripts/install-deployment.mjs --install` installs the native observer and outbound-only local delivery agent from clean, green, merged main only. Do not install code from an unmerged worktree or run production deployment from a PR/hosted CI runner. Keep installed programs pinned to reviewed source, serialize upgrades with the native lock, and exercise `tests/deployment.test.js` plus `scripts/check-agent-container.mjs` before changing release safety. Record the actual deployed revision, backup and verification separately from CI results.

## Agent harness

All interface-originated language-model inference must go through the Pydantic AI slim harness under `src/agent/`. No direct inference fallback, automatic retries, model substitution, tool execution or cloud telemetry. Express owns authentication, discovery, uploads and SQLite; Python is a private pipe worker and must never open the database or expose a listener. Preserve exact model IDs, browser SSE behavior and attachment/history semantics.

Use uv 0.13.5 and CPython 3.11.17. Install with `uv sync --locked --no-editable`; after changing Python source, run `uv sync --locked --no-editable --reinstall-package fios-agent` so isolated-mode tests exercise the current installed code. Do not use editable source imports to conceal packaging failures. Worker startup and health checks must not invoke models.

Validation:

```sh
npm ci
uv sync --locked --no-editable
npm test
npm run build
npx playwright test
npm audit
uvx --python 3.11.17 --from pip-audit==2.10.1 pip-audit --path .venv/lib/python3.11/site-packages
node scripts/check-agent-boundary.mjs
node scripts/check-agent-container.mjs
docker compose config --quiet
node scripts/check.mjs
```

Browser/API tests use mock MLX and isolated databases. Real inference is opt-in via `node scripts/check.mjs 'EXACT_MODEL_ID'`; select an already-loaded or appropriately small model, not a huge cold Studio model. Update feature tasks and validation evidence honestly.

Never print `.env`, resolved Compose secrets, or passwords in logs/responses. Keep inference native on macOS. Do not alter RDMA, enable remote execution, expose public/LAN ports, or delete the detached legacy data volume without approval. Do not open the same SQLite file from two application instances; startup recovers stale streaming rows.
