# Fios

_A clear space to think._ A custom, coding-focused chat workspace for your local MLX-Serve models. Built from scratch with React, Express and SQLite; no Open WebUI dependency.

## Open the workspace

**http://localhost:3000**

The application runs as the `fios` service in OrbStack. To see your generated access password locally:

```sh
./scripts/password.sh
```

The password and session-signing secret are in the private, Git-ignored `.env`. Do not paste them into tickets or commit them.

## Features

- A clean, responsive interface with conversation sidebar, search, model picker and keyboard-friendly composer.
- Persistent chat history with confirmed deletion, including associated attachment data.
- Streamed responses, stop-generation control, explicit error states and saved partial responses.
- Markdown, tables, lists, syntax-highlighted fenced code, and copy icons for messages and code blocks.
- Text/source, PDF and image attachments; remove files before sending or drag them onto the composer.
- Password-protected, localhost-only workspace; no signup, analytics, external fonts or remote image loading.

Press **Enter** to send or **Shift+Enter** for a new line. Select a model from the picker inside the composer. The picker identifies its host, vision capability and whether it is already loaded. The catalog refreshes automatically every **30 seconds while the tab is visible**, when returning to the tab/window, after the browser reconnects, and when opening the picker. Additions and removals reflect MLX-Serve's advertised chat models without a page reload. If the selected model disappears, Fios clears the selection and asks you to choose another rather than silently switching models. Discovery outages are shown with automatic retries; stale model choices cannot be sent until discovery recovers. Selecting a model does not load it; sending a request can cause MLX-Serve to load it.

## Architecture

```text
Browser :3000 → Fios container (React + Express + SQLite)
                    ↓ private process pipes (no new network listener)
                Pydantic AI slim Python agent
                    ↓ http://host.docker.internal:11234/v1
                Mini's native MLX-Serve gateway
                    ↓ existing LAN routing / distributed configuration
                Mac Studios / existing RDMA cluster
```

Inference stays native on macOS. Express queries `/v1/models`; **all model inference runs through Pydantic AI slim**, using streaming Chat Completions and preserving exact model IDs and peer suffixes. The agent code lives in `src/agent/`. There is no direct-call fallback, automatic inference retry, model substitution, tool execution or external telemetry. Python has no network listener and never opens SQLite. Login, catalog, conversation management and health checks are not agent runs. It does not configure RDMA, change model files, or provide execution sandboxes. A peer-qualified model ID alone does not prove distributed inference.

## Install / run

Prerequisites: OrbStack in Docker mode, Docker Compose v2, Python 3 for first-time setup, and MLX-Serve running on this host at port 11234.

```sh
./scripts/setup.sh             # idempotent; creates private credentials
# Optional: edit MLX_BASE_URL / MLX_API_KEY in .env.
docker compose config --quiet # do not print resolved credentials
docker compose up -d --build --wait
./scripts/password.sh
```

The production container runs as UID 1000, with a read-only root filesystem, no added capabilities, no Docker socket, and 1 GiB / 2 CPU limits. SQLite and attachment blobs live in the named **`fios_fios-data`** volume. Rebuilding/recreating the container preserves them. **`docker compose down -v` deletes them.**

### Configuration

| Setting          | Purpose                                                       |
| ---------------- | ------------------------------------------------------------- |
| `FIOS_PASSWORD`  | Generated local access password, minimum 12 characters        |
| `SESSION_SECRET` | Stable generated cookie-signing secret, minimum 32 characters |
| `MLX_BASE_URL`   | Defaults to `http://host.docker.internal:11234/v1`            |
| `MLX_API_KEY`    | Optional real key if MLX authentication is enabled            |
| `FIOS_AGENT_PYTHON` | Local development interpreter override; defaults to `.venv/bin/python`. The image fixes `/opt/venv/bin/python`; do not use a host path in Compose. |

Edit `.env`, then run `docker compose up -d` to apply environment changes. If changing the password, also rotate `SESSION_SECRET` to invalidate existing sessions. Cookies expire after seven days. Login attempts are rate-limited; logging out clears the current browser's cookie. This is a single-user workspace, not a multi-user account system.

### Attachment limits

- Up to **5 files/message**, **10 MiB/file**, **20 MiB total/message**.
- UTF-8 text and common source/config formats; extracted text is limited to **100,000 characters/file**.
- Text-based, unencrypted PDFs up to **100 pages**, with parsing isolated in a memory-bounded worker and a 15-second deadline. No OCR or office-document extraction.
- PNG, JPEG, WebP and GIF images. The selected model must advertise vision support; a conversation containing images must continue with a vision-capable model.
- All prior attachments remain context for later turns. Aggregate text context is capped at **400,000 characters** and image data at **20 MiB/conversation**. These byte/character safety caps are not token-aware; the selected model's own context limit may be smaller. Start a new chat or attach shorter excerpts if needed.
- Images are forwarded to MLX as multimodal content, not OCR'd by Fios. Quality depends on the selected model. Unsupported files are rejected rather than silently omitted.

Fios sends up to 8,192 output tokens per request, supports one active generation at a time, and aborts if MLX produces no stream data for 180 seconds. Cold starts may take time. Health probes never load models. Attachments, prompts and replies are stored locally without application-level encryption; protect your disk and backups. Do not attach untrusted or sensitive material indiscriminately.

## Checks and development

Node 22.13+ is required locally; production uses digest-pinned Node 24.15.0, uv 0.13.5 and CPython 3.11.17. Install uv 0.13.5 locally, then use the frozen Python setup below. npm dependencies are pinned in `package-lock.json`; Python provider dependencies are pinned in `pyproject.toml` and fully resolved in `uv.lock`. Production has no runtime package downloads.

```sh
npm ci
uv python install 3.11.17
uv sync --locked --no-editable
# After editing Python source, rebuild its non-editable installed package:
# uv sync --locked --no-editable --reinstall-package fios-agent
npm test                     # Node + Python tests; real harness, mock MLX
npm run build
npx playwright install chromium
npx playwright test          # desktop/mobile browser tests against mock MLX
npm audit
uvx --python 3.11.17 --from pip-audit==2.10.1 pip-audit --path .venv/lib/python3.11/site-packages
node scripts/check-agent-boundary.mjs
# Isolated image/volume tests; defaults to fios:0.1.0 as the prior image.
# Override FIOS_AGENT_ROLLBACK_IMAGE if using another already-built prior version.
node scripts/check-agent-container.mjs
node scripts/check.mjs       # real authenticated gateway discovery; no inference
# Opt-in: sends a temporary attachment + prompt, then deletes the test chat.
# May load the selected model. Use an already-loaded or suitably small model.
node scripts/check.mjs 'EXACT_ADVERTISED_MODEL_ID'
```

Browser/API tests use the actual Python Agent against mock MLX, isolated ports and databases (`data/browser-test.sqlite` for browsers), never the production volume. Fake worker processes are used only for supervision fault tests. Container tests create a unique Compose project/image/network/volume, bind only a free localhost port, rehearse old → new → old image rollback and backup restore, and clean up only their own resources. Screenshots are written into ignored `test-results/`. These tests do not prove real model behavior; see `specs/002-custom-frontend/validation.md` for live evidence.

For frontend hot reload, run the backend locally (stop the container first to free port 3000), then Vite in a second terminal:

```sh
MLX_BASE_URL=http://localhost:11234/v1 node --env-file=.env server/index.js
npm run dev
```

Visit Vite's printed localhost address. Requests are proxied to Express; the backend database defaults to local `data/fios.sqlite`, separate from Docker's volume. Never run the backend directly against a database already open in another application instance.

### Continuous integration

[CI](https://github.com/mcteer/fios/actions/workflows/ci.yml) runs on PRs, pushes to `main`, manual dispatch and weekly scheduled runs. Required checks cover clean locked installs and unit/API tests on Node 22/24, Chromium browser regressions, builds/inference boundaries, npm/Python advisory scans, and a native ARM64 hardened-container upgrade/rollback/backup-restore rehearsal. The immutable pre-harness source commit is built as the disposable rollback baseline; no local production image is assumed on hosted runners.

The stable **CI gate** succeeds only when every required job succeeds; failed, cancelled or skipped jobs fail the gate. Actions are SHA-pinned, repository permissions are read-only, and no production secrets or live MLX access are used. Only mock-data browser/container diagnostics are retained on failure, for seven days. Hosted CI does not access production or prove real inference/RDMA behavior. Require green checks on the exact latest PR commit before merging. The local delivery agent below automatically deploys approved main revisions after their main-push CI passes.

## Operations

```sh
docker compose ps
docker compose logs --tail=100 fios
docker compose stop
docker compose up -d --wait
```

If the UI opens but models do not load, use **Reconnect** or refresh models from the picker. Check native MLX-Serve and `MLX_BASE_URL`. Container `localhost` is not the Mini: use `host.docker.internal`. An upstream failure is shown as an error, with any partial output retained. Do not blindly retry large cold-model loads.

### Model and host readiness

`GET /api/models` returns authenticated model and serving-host observations. The picker shows host online/offline/unverified state and model availability separately from Loaded/On demand. A healthy host presenting an unloaded model is available on demand; discovery never loads it. Stale gateway peer listings cannot establish readiness: Express rejects unavailable/unverified targets before saving messages, and the Python harness independently preflights the exact target before its single possible inference request. No retry, substitution or fallback is added.

Configure `MLX_PEER_URLS` privately as a JSON map of **exact peer name** to trusted `/v1` base. Unconfigured peers stay unverified. Catalog-provided URLs are never followed and gateway credentials are never forwarded to peers. Direct native/development clients probe the configured hosts; unauthorized hosts require operator configuration rather than guessed credentials.

On this deployment, live tests proved that native host access to the Studios works but direct container access does not. The native observer uses only health/catalog reads and shares atomic metadata through a **read-only directory bind**; it exposes no listener or Docker socket. Node and Python reject endpoint-mismatched, malformed, missing or older-than-5-second observations (future tolerance: 1 second). `MLX_READINESS_FILE` names the container file; `FIOS_READINESS_DIR` names only the metadata directory on the host. Never mount `.env` or host credentials into this directory. If the observer stops, peer readiness expires and sends are blocked. `/health` remains app liveness, not model readiness.

### Automatic production delivery

After an approved merge and successful CI on the exact merged main SHA, the **local** outbound-only delivery agent archives/builds that immutable revision, preserves the current image, stops the app, snapshots all data except prior backup directories, replaces the app, verifies health/authenticated discovery and Python non-inference readiness, and verifies the image revision label. Failed upgrades automatically restore and verify the prior image on the same compatible schema; new records are never discarded by automatic data restoration. Backups remain at `backups/before-…` **inside the application data volume**; previous images have unique `fios:rollback-…` tags. Protect/export these backups; same-volume copies alone do not protect against disk/volume loss. Schema-changing upgrades require an explicit compatibility/restore plan.

Install or update reviewed stable programs only from **clean, green, merged main** on the authorized macOS host:

```sh
node scripts/install-deployment.mjs --install
```

This installs user LaunchAgents `lab.fios.readiness` (continuous read-only native observation) and `lab.fios.deploy` (60-second polling). An active user login, existing local Docker and authenticated GitHub CLI are prerequisites. No CI runner gets production access, no new listener/SSH/remote execution is enabled, and MLX/RDMA settings are untouched. The installer rejects an active deployment lock; macOS `shlock` handles serialization and dead-owner locks. Reviewed programs are copied into `~/Library/Application Support/Fios/deploy`, so switching developer branches cannot execute unmerged code. Re-run the installer after approved changes to the observer/deployer themselves.

State and sanitized logs are in that private directory. The agent changes only `FIOS_IMAGE` after verification; installation sets the observer bind path. Existing credentials are preserved. A failed upgraded SHA is not repeatedly redeployed; inspect the failure/rollback outcome before authorizing recovery. Transient pre-deployment failures can be retried by later polls. To pause delivery, unload only `lab.fios.deploy` with `launchctl bootout gui/$(id -u)/lab.fios.deploy`; keep the observer running for readiness. Do not interrupt an active upgrade. A successful merge is not proof of deployment: verify `state.json`, the running image revision and non-inference health/discovery, and report actual outcomes.

### Agent lifecycle and troubleshooting

`/health` is app liveness, not proof of agent or MLX readiness. The Python worker starts lazily on generation, sends a versioned readiness handshake within 10 seconds, and stays available for later runs. If startup fails, generation returns 503 before inserting messages; login, history and model discovery remain usable. After a worker crash, only a **new user request** can start its replacement—the failed request is never replayed.

Stop/disconnect cancels the Agent and closes upstream streams. An unresponsive worker is terminated after one second and killed after 1.5 seconds; controlled tests verify cleanup within two seconds. Real remote compute cancellation remains MLX's responsibility. Missing upstream completion markers and malformed streams are errors, not successful answers; received answer text is retained. Reasoning text is transient and is not saved or replayed.

Diagnostics contain only run ID, lifecycle phase, safe error code and elapsed time. `agent_unavailable` usually means interpreter/package installation or worker startup failed; check `FIOS_AGENT_PYTHON` and reinstall the package. `agent_protocol_error` means worker framing/version failure. `model_unavailable` indicates a rejected readiness preflight; check the picker hosts, explicit peer configuration and native observer freshness. `upstream_http`, `upstream_unavailable`, `upstream_timeout`, `incomplete_stream`, and `output_limit` distinguish gateway/output failures. Do not enable raw SDK HTTP/debug logs or paste credentials/content into logs. The SDK banner is disabled and untrusted child stderr is not forwarded verbatim.

### Backup / restore

Stop the app for a consistent SQLite snapshot. Backups contain private conversations and attachments; keep them encrypted and back up `.env` securely as well.

```sh
umask 077
mkdir -p backups
docker compose stop fios
docker compose run --rm --no-deps -T --entrypoint tar fios \
  -C /app/data -czf - . > backups/fios-data.tar.gz
docker compose up -d --wait
```

Restore with the matching application version into a **fresh, empty recovery volume**, not over a running or populated database:

```sh
# Example: an isolated recovery project creates its own empty volume.
# Do not start this project on the production port while production is running.
docker compose -p fios-recovery run --rm --no-deps -T --entrypoint tar fios \
  -C /app/data -xzf - < backups/fios-data.tar.gz
```

Review recovered data before switching production to it. Test restore before relying on a backup. Before upgrades, preserve the old image and consistent data backup; rollback may require both, not just an old image.

### Access policy

Keep the default `127.0.0.1` port binding. LAN/public exposure is not configured. HTTPS, secure cookies (`COOKIE_SECURE=true`), proxy trust/origin behavior, firewall rules and multi-user authorization need a separate spec/security review. Frontend authentication does not secure MLX-Serve's native LAN endpoint. No remote runner or model-controlled execution is enabled.

## Spec Kit and project history

Upstream GitHub Spec Kit scaffolding is in `.specify/`, with generic-agent prompts in `.agents/commands/`. Read the [constitution](.specify/memory/constitution.md), then the active numbered feature's spec, plan, tasks and validation evidence (currently [feature 005](specs/005-model-host-readiness/spec.md)). Each spec gets its own branch and reviewed PR targeting `main`; never commit spec work directly to `main`. Use specify → clarify → plan → tasks → analyze → implement for future features.

[ADR 0002](docs/adr/0002-pydantic-agent-harness.md) records the Pydantic AI harness design; it was accepted with feature PR #1. [ADR 0001](docs/adr/0001-replace-open-webui-with-custom-frontend.md) records the decision to replace Open WebUI with the purpose-built Fios frontend. The Open WebUI attempt is retired under `specs/archive/001-open-webui/`; its container/images were removed. The detached legacy `fios_webui-data` volume was preserved to avoid unapproved data loss and is not used by Fios. [Studio sandbox research](docs/sandboxes.md) remains a separate future feature.
