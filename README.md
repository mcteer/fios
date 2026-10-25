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
                    ↓ http://host.docker.internal:11234/v1
                Mini's native MLX-Serve gateway
                    ↓ existing LAN routing / distributed configuration
                Mac Studios / existing RDMA cluster
```

Inference stays native on macOS. Fios uses `/v1/models` and streaming `/v1/chat/completions`, preserving exact model IDs and peer suffixes. It does not configure RDMA, change model files, or provide execution sandboxes. A peer-qualified model ID alone does not prove distributed inference.

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

Node 22.13+ is required locally; the production image uses pinned Node 24. Dependencies are pinned in `package-lock.json`.

```sh
npm ci
npm test                     # unit + API tests against mock MLX
npm run build
npx playwright install chromium
npx playwright test          # desktop/mobile browser tests against mock MLX
npm audit
node scripts/check.mjs       # real authenticated gateway discovery; no inference
# Opt-in: sends a temporary attachment + prompt, then deletes the test chat.
# May load the selected model. Use an already-loaded or suitably small model.
node scripts/check.mjs 'EXACT_ADVERTISED_MODEL_ID'
```

Browser tests use their own ports and `data/browser-test.sqlite`, never the production volume. Screenshots are written into ignored `test-results/`. These tests do not prove real model behavior; see `specs/002-custom-frontend/validation.md` for live evidence.

For frontend hot reload, run the backend locally (stop the container first to free port 3000), then Vite in a second terminal:

```sh
MLX_BASE_URL=http://localhost:11234/v1 node --env-file=.env server/index.js
npm run dev
```

Visit Vite's printed localhost address. Requests are proxied to Express; the backend database defaults to local `data/fios.sqlite`, separate from Docker's volume. Never run the backend directly against a database already open in another application instance.

## Operations

```sh
docker compose ps
docker compose logs --tail=100 fios
docker compose stop
docker compose up -d --wait
```

If the UI opens but models do not load, use **Reconnect** or refresh models from the picker. Check native MLX-Serve and `MLX_BASE_URL`. Container `localhost` is not the Mini: use `host.docker.internal`. An upstream failure is shown as an error, with any partial output retained. Do not blindly retry large cold-model loads.

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

Upstream GitHub Spec Kit scaffolding is in `.specify/`, with generic-agent prompts in `.agents/commands/`. Read the [constitution](.specify/memory/constitution.md), then [feature 002](specs/002-custom-frontend/spec.md), its plan, tasks and validation evidence. Use specify → clarify → plan → tasks → analyze → implement for future features.

[ADR 0001](docs/adr/0001-replace-open-webui-with-custom-frontend.md) records the decision to replace Open WebUI with the purpose-built Fios frontend. The Open WebUI attempt is retired under `specs/archive/001-open-webui/`; its container/images were removed. The detached legacy `fios_webui-data` volume was preserved to avoid unapproved data loss and is not used by Fios. [Studio sandbox research](docs/sandboxes.md) remains a separate future feature.
