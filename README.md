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

Inference stays native on macOS. Express queries `/v1/models`; **all model inference runs through Pydantic AI slim**, using streaming Chat Completions and preserving exact model IDs and peer suffixes. The agent code lives in `src/agent/`. There is no direct-call fallback, automatic inference retry, model substitution, arbitrary tool execution or external telemetry. Spec007's sole tool exception is automatic agent-invoked `web_search(query)` inside the same Python harness. The approved fix uses our own **SearXNG container** instead of blocked direct DuckDuckGo retrieval. Python owns query/privacy validation, bounded public retrieval and evidence integration; Express does not decide or execute searches. The reviewed first-release envelope allows one attempted search and at most two actual same-ID model requests, with zero retries. No-tool turns remain one request. No other tools, MCP, shell/file execution, classifier pass or automatic provider/model fallback is authorized. SearXNG is the sole additional search service. Queries and site requests leave the machine; privacy-oriented search is not anonymity or perfect sensitive-data detection. Sources will indicate supplied evidence, not factual verification. Live provider-only SearXNG acceptance retrieved five sources including two pages, with a partial outcome and one upstream failure. No named model has yet passed a newly authorized real tool-cycle test; readiness does not certify tool competence. Python has no network listener and never opens SQLite. Login, catalog, conversation management and health checks are not agent runs. It does not configure RDMA, change model files, or provide execution sandboxes. A peer-qualified model ID alone does not prove distributed inference.

## Install / run

Prerequisites: OrbStack in Docker mode, Docker Compose v2, Python 3 for first-time setup, and MLX-Serve running on this host at port 11234.

```sh
./scripts/setup.sh             # idempotent; creates private credentials
# Optional: edit MLX_BASE_URL / MLX_API_KEY in .env.
docker compose config --quiet # do not print resolved credentials
docker compose up -d --build --wait
./scripts/password.sh
```

The application container runs as UID 1000, with a read-only root filesystem, no added capabilities, no Docker socket, and 1 GiB / 2 CPU limits. `readiness` is a separate nonroot metadata-only container. `searxng` is a pinned official-image derivative (AGPL-3.0-or-later),977:977/read-only,256MiB/0.5CPU, no published port/app secrets/SQLite/socket mounts. Its process-local session key and caches are disposable; access/query logs are disabled and not retained. The app reaches it on an internal-only network; SearXNG has a separate egress network. `deployer` is a separately isolated trusted management container: its root user and Docker socket give it daemon-wide deployment authority, never shared with the application or observer. It has no published ports or host checkout/config mounts. All supporting services run in the OrbStack Fios stack; do not install native macOS background helpers. SQLite and attachment blobs live in the named **`fios_fios-data`** volume. Rebuilding/recreating the container preserves them. **`docker compose down -v` deletes them.**

### Configuration

| Setting          | Purpose                                                       |
| ---------------- | ------------------------------------------------------------- |
| `FIOS_PASSWORD`  | Generated local access password, minimum 12 characters        |
| `SESSION_SECRET` | Stable generated cookie-signing secret, minimum 32 characters |
| `MLX_BASE_URL`   | Defaults to `http://host.docker.internal:11234/v1`            |
| `MLX_API_KEY`    | Optional real key if MLX authentication is enabled            |
| `FIOS_WEB_SEARCH` | `auto` (default) or `off`; only the Python agent may decide/invoke search. No provider URL override. Apply an off override to app and the trusted controller environment through reviewed Compose configuration so automatic delivery retains it. |
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

### Automatic web evidence (spec 007 branch)

The selected local model can invoke only `web_search(query)`. Python validates the query against bounded eligible plain-user terms before the internal SearXNG API request and independently guarded public-page requests. Attachments, assistant/page-only terms, recognized credentials/private/code patterns and ambiguous provenance are rejected. This conservative filter can reject legitimate paraphrases and cannot identify every sensitive phrase typed by a user. Queries/connection metadata leave the machine; search is not anonymous.

Each turn permits one attempted search and at most two actual same-ID model requests, with zero retries. Search uses the fixed internal `http://searxng:8080/search` JSON API, at most five sources/three page chains, fourteen harness HTTP attempts/two public sockets, a 15-second tool deadline, 1 MiB bodies/5 MiB aggregate and 16,000 UTF-16 units/64 KiB evidence. SearXNG queries the explicit Bing/Brave engine set concurrently; it is **not a local index** and those engines receive eligible queries. Its own upstream requests are outside the harness's14-request counter, with configured3s/max4s engine timeout and zero retries. There is no silent engine-set change or DDG fallback. For public pages/robots, DNS/IP/redirect checks pin a public numeric destination while retaining hostname certificate verification with the locked certifi CA bundle. Robots, access denials and full Retry-After restrictions are honored. No JavaScript/login/CAPTCHA solving, provider switch, generic fetch tool or hidden no-tools retry is provided.

The UI shows progress, failure/no-search notices, page versus snippet evidence and sources supplied to the model. Citation IDs resolve only against that answer's supplied manifest; sources are **not factual verification**. Preliminary text is cleared if a tool call follows it. Query arguments, pages, excerpts, tool transcripts and reasoning are ephemeral; safe source URLs/titles/times/hashes/outcomes persist with the answer and cascade on deletion. Old images may omit the new metadata but preserve it across compatible rollback/re-upgrade. Health checks never search or infer.

The internal gateway is a narrow separate client, not a private-address exception in the public page fetcher. SearXNG's packaged engine clients own upstream networking; they are not covered by our custom pinned-IP page transport. Stopping a turn closes harness work and prevents model continuation, but already-started upstream service work may finish under its configured timeout.

A model that declines tools or rejects tool parameters is not silently replaced. The provider can block access, and chat readiness does not certify tool competence. Live provider acceptance and an explicitly authorized exact-model tool cycle are separate gates; mock tests do not prove either.

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

The stable **CI gate** succeeds only when every required job succeeds; failed, cancelled or skipped jobs fail the gate. Actions are SHA-pinned, repository permissions are read-only, and no production secrets or live MLX access are used. Only mock-data browser/container diagnostics are retained on failure, for seven days. Hosted CI does not access production or prove real inference/RDMA behavior. Require green checks on the exact latest PR commit before merging. The containerized delivery controller below automatically deploys approved main revisions after their main-push CI passes.

## Operations

```sh
docker compose ps
docker compose logs --tail=100 fios
docker compose stop
docker compose up -d --wait
```

If the UI opens but models do not load, use **Reconnect** or refresh models from the picker. Check native MLX-Serve and `MLX_BASE_URL`. Container `localhost` is not the Mini: use `host.docker.internal`. An upstream failure is shown as an error, with any partial output retained. Do not blindly retry large cold-model loads.

### Model and host readiness

`GET /api/models` returns authenticated model and serving-host observations. The picker shows host online/offline/unverified state and model availability separately from Loaded/On demand. A healthy host presenting an unloaded model is available on demand; discovery never loads it. Stale gateway peer listings cannot establish readiness: Express rejects unavailable/unverified targets before saving messages, and the Python harness independently preflights the exact target before each permitted inference request (one normally; at most two for a single search-tool cycle). No retry, substitution or fallback is added.

Configure `MLX_PEER_URLS` privately as a JSON map of **exact peer name** to trusted `/v1` base. Unconfigured peers stay unverified. Catalog-provided URLs are never followed and gateway credentials are never forwarded to peers. Direct native/development clients probe the configured hosts; unauthorized hosts require operator configuration rather than guessed credentials.

The `readiness` container uses only health/catalog reads and shares atomic metadata through the **`fios_fios-readiness` named volume**, mounted read-only by the application. It exposes no listener or Docker socket and never reads a host `.env`. Node and Python reject endpoint-mismatched, malformed, missing or older-than-5-second observations (future tolerance: 1 second). If the observer stops, peer readiness expires and sends are blocked. `/health` remains app liveness, not model readiness. Container probes now reach both Studio interfaces in the observed environment; if connectivity fails, diagnose OrbStack/macOS network permissions and report the blocker—never add native probes/proxies or silently change routing/RDMA.

### Automatic production delivery

After an approved merge and successful CI on the exact merged main SHA, the **containerized** outbound-only delivery controller archives/builds that immutable revision, preserves the current image, stops the app, snapshots all data except prior backup directories, replaces the app, verifies health/authenticated discovery and Python non-inference readiness, and verifies the image revision label. Failed upgrades automatically restore and verify the prior image on the same compatible schema; new records are never discarded by automatic data restoration. Backups remain at `backups/before-…` **inside the application data volume**; previous images have unique `fios:rollback-…` tags. Protect/export these backups; same-volume copies alone do not protect against disk/volume loss. Schema-changing upgrades require an explicit compatibility/restore plan.

Build/start or update supporting images only from **clean, green, merged main**. The old native installer is disabled; its LaunchAgents and installed programs were removed. For the first SearXNG rollout, after exact merged-main CI is green, run `docker compose build searxng` and `docker compose up -d --no-deps --no-build --wait searxng` from that clean main checkout. This publishes no ports or credentials and does not open the application DB. The existing controller still delivers the app with its normal backup/verification policy; it intentionally does not recreate supporting services during an app transaction. Compose manages `readiness`, `searxng` and `deployer` alongside `fios`; no user login scheduler or authenticated host GitHub CLI is needed. The management image pins Node 24, git, Docker CLI/Compose/buildx and Linux flock. It polls public main/CI metadata every **180 seconds**, without exporting a personal GitHub token, and fetches immutable reviewed source into its private `fios_fios-deployment` volume. Linux flock serializes the controller; never run a concurrent manual rollout. No CI runner gets production access, no listener/SSH/remote execution is added, and MLX/RDMA remain untouched.

The controller deliberately updates **only the app**, with `--no-deps`, during a SQLite-critical transaction; the observer/controller are stable reviewed images, updated explicitly through Compose after their own changes pass CI. Immutable app images are `fios:<sha>`; `fios:current` is updated only after verification so manual Compose operations retain the latest verified application. Remove obsolete private `FIOS_READINESS_DIR`/old `FIOS_IMAGE` overrides during migration, without changing credentials. Source worktrees are not mounted into running services.

Deployment state is `/state/state.json` inside `deployer`; inspect only sanitized metadata with `docker compose exec -T deployer cat /state/state.json`, and logs with `docker compose logs --tail=100 deployer`. Credentials are provided through Compose environment, never written into source archives/logs. A failed upgraded SHA is not repeatedly deployed; review failure/rollback before clearing it. Transient pre-deployment failures retry on later polls. To pause delivery, `docker compose stop deployer` **only when idle**; leave readiness running. Do not interrupt active upgrades. A successful merge is not proof of deployment: verify stored state, the running revision label and authenticated non-inference discovery. The Docker socket is an explicit high-trust management boundary, not a safe application capability; never mount it into app, observer or PR test containers.

### Agent lifecycle and troubleshooting

`/health` is app liveness, not proof of agent or MLX readiness. The Python worker starts lazily on generation, sends a versioned readiness handshake within 10 seconds, and stays available for later runs. If startup fails, generation returns 503 before inserting messages; login, history and model discovery remain usable. After a worker crash, only a **new user request** can start its replacement—the failed request is never replayed.

Stop/disconnect cancels the Agent and closes upstream streams. An unresponsive worker is terminated after one second and killed after 1.5 seconds; controlled tests verify cleanup within two seconds. Real remote compute cancellation remains MLX's responsibility. Missing upstream completion markers and malformed streams are errors, not successful answers; received answer text is retained. Reasoning text is transient and is not saved or replayed.

Diagnostics contain only run ID, lifecycle phase, safe error code and elapsed time. `agent_unavailable` usually means interpreter/package installation or worker startup failed; check `FIOS_AGENT_PYTHON` and reinstall the package. `agent_protocol_error` means worker framing/version failure. `model_unavailable` indicates a rejected readiness preflight; check the picker hosts, explicit peer configuration and container observer freshness. `upstream_http`, `upstream_unavailable`, `upstream_timeout`, `incomplete_stream`, and `output_limit` distinguish gateway/output failures. Do not enable raw SDK HTTP/debug logs or paste credentials/content into logs. The SDK banner is disabled and untrusted child stderr is not forwarded verbatim.

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

## Studio platform agent — development, not installed

[Spec009](specs/009-studio-platform-agent/spec.md) adds a narrowly scoped native, unprivileged supervisor/manager/session boundary on the two approved Studios; inference and RDMA stay native and the deployed application/support containers stay unchanged. Only the trusted manager may hold Studio-wide runtime authority. Observers, model workers and temporary sandboxes never receive it. No general host shell, remote execution, public management listener, host mounts, runtime sockets, credentials or egress are granted to a sandbox. Models cannot authorize management.

**Activation is closed.** Authoritative all-client/native-backend terminality, production enrollment, lifecycle acceptance and reviewed installation remain incomplete. Development artifacts are observation-only, not installable complete releases. See [current task status](specs/009-studio-platform-agent/tasks.md), [dated evidence](specs/009-studio-platform-agent/validation.md) and [native gaps](specs/009-studio-platform-agent/native-backend-terminality.md). Empty-device primitives and mock/process tests are not real-model or installed-service acceptance.

Use the [009 quickstart](specs/009-studio-platform-agent/quickstart.md) for exact local status/task/service/backup commands, limits and cleanup/rollback rules. Desired `running|maintenance|stopped` persists intent, not successful actuation; unenrolled drain/force remains unsupported. Installation is review-only and requires separately authorized, one-host-at-a-time operator execution from reviewed artifacts. Never enable the retired005 installer or use app delivery to deploy native components. Preserve independent uncertainty, exports, backups and unrelated resources on failure or uninstall.

Routing008 remains **parked at `3936da2`**, unmerged and undeployed. Its future consumer may use009's normalized authenticated activity/admission contract only after enrollment; resident lists, sampled GPU/idle values or this development branch are not substitutes. Do not import or resume008 automatically.

## Spec Kit and project history

Upstream GitHub Spec Kit scaffolding is in `.specify/`, with generic-agent prompts in `.agents/commands/`. Read the [constitution](.specify/memory/constitution.md), then the active numbered feature's spec, plan, tasks and validation evidence (currently [feature009](specs/009-studio-platform-agent/spec.md);008 is parked). Each spec gets its own branch and reviewed PR targeting `main`; never commit spec work directly to `main`. Use specify → clarify → plan → tasks → analyze → implement for future features.

[ADR 0002](docs/adr/0002-pydantic-agent-harness.md) records the Pydantic AI harness design; it was accepted with feature PR #1. [ADR 0001](docs/adr/0001-replace-open-webui-with-custom-frontend.md) records the decision to replace Open WebUI with the purpose-built Fios frontend. The Open WebUI attempt is retired under `specs/archive/001-open-webui/`; its container/images were removed. The detached legacy `fios_webui-data` volume was preserved to avoid unapproved data loss and is not used by Fios. [Studio sandbox research](docs/sandboxes.md) is historical input to the in-progress009 boundary, not installation authority.
