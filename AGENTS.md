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

## Supporting services must be containerized

All Fios supporting services—including readiness observers, deployment controllers, schedulers and background workers—must run as containers in the OrbStack-managed Fios Compose stack. Do not install or run them as macOS LaunchAgents, LaunchDaemons, login items or persistent host-side scripts. MLX-Serve and RDMA are the explicit native-inference exceptions; this does not authorize other native supporting processes. One-shot development/test/administrative commands are not persistent services.

Container connectivity failures must be diagnosed within the authorized OrbStack/container architecture, not bypassed with host-resident probes or proxies. Report network/OS permission blockers and request the required approval rather than modifying RDMA, routing or security settings silently. Keep the application isolated from deployment privileges: never give it the Docker socket or deployment credentials. Any containerized deployment controller's required management access must be explicit, least-privilege and separately reviewed.

## Model and host readiness

Express and the Python harness must independently gate the exact selected model on gateway/serving-host health and that host's own advertised model catalog. A cached peer entry is not proof of readiness. Unloaded but advertised on a healthy host means available on demand; discovery must never load models or run inference. Probe only explicit `MLX_PEER_URLS`; never follow catalog URLs or forward gateway credentials to peers.

Both runtimes must validate endpoint fingerprints and reject missing, malformed, future-dated or older-than-5-second observations when using a containerized observer's shared metadata. Unknown/unavailable targets cannot be sent and must not trigger fallback/substitution. Preserve this fail-closed behavior when changing discovery or the harness.

The native installation introduced in spec 005 was rejected and removed. `scripts/install-deployment.mjs` must stay disabled; never restore its LaunchAgents. `readiness` and `deployer` are Compose services. Only the trusted, isolated controller may mount the Docker management socket; this is daemon-wide authority, not read-only access, and must never be shared with app/observer/PR test containers. Keep the controller free of host source/config mounts and personal GitHub credentials; public main/CI polling is rate-limited and token-free. Use named volumes for metadata/deployment state and a read-only metadata mount in the app. Do not install code from an unmerged worktree or run production deployment from a PR/hosted CI runner. Keep deployed programs pinned to reviewed source, serialize upgrades, and exercise `tests/deployment.test.js` plus `scripts/check-agent-container.mjs` before changing release safety. Record the actual deployed revision, backup and verification separately from CI results.

## Agent harness

All interface-originated language-model inference must go through the Pydantic AI slim harness under `src/agent/`. No direct inference fallback, automatic retries, model substitution, arbitrary tool execution or cloud telemetry. Spec 007 authorizes only the agent-invoked `web_search(query)` tool inside the existing Python harness: Python owns query validation, DuckDuckGo-only public retrieval and evidence integration; Express only supplies provenance, supervises, relays validated events and owns persistence/UI. The approved implementation plan's first-release envelope is one attempted search and at most two actual same-ID model POSTs (initial response plus one tool-result continuation), with zero Agent/SDK/HTTP/tool-validation retries. No-tool/admin-off turns remain one-request/no-tools. Unknown, repeated or parallel calls fail closed; no MCP, shell/file tools, provider fallback, classifier pass or separate search service. Spec 007's branch implements this exception; previously deployed images remain no-tools/single-request until reviewed delivery. Do not claim live functionality or deployed capability from mock tests: provider acceptance and explicit exact-model tool testing are separate gates. Real-model tool testing still requires separate explicit opt-in. Express owns authentication, discovery, uploads and SQLite; Python is a private pipe worker and must never open the database or expose a listener. Preserve exact model IDs, browser SSE behavior and attachment/history semantics.

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
