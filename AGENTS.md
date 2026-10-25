# Fios agent guidance

Read `.specify/memory/constitution.md` before changes. Follow upstream Spec Kit prompts in `.agents/commands/`; generic integration is intentional. Feature artifacts live in `specs/<number>-<name>/`. Resolve the active feature with `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` rather than assuming a fixed spec directory.

Fios is a custom React/Vite frontend and Express/SQLite backend. Open WebUI is retired; `specs/archive/001-open-webui/` is historical only. Do not restore that deployment. Preserve the purpose-built UX, local-first architecture and exact MLX model IDs.

## Spec branches and pull requests

Going forward, each spec must have its own dedicated branch and pull request. Before creating or changing a spec or implementing its work, create or switch to its branch (for example, `004-feature-name`). Keep that spec's artifacts, implementation, tests, and validation evidence together on the branch; do not combine unrelated specs in one PR. Open a PR targeting `main` that links the spec and summarizes changes, validation results, and any pending checks. Do not commit spec work directly to `main`; merge through the PR after review and approval. This policy applies to new specs and subsequent work on existing specs.

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
