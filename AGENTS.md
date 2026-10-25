# Fios agent guidance

Read `.specify/memory/constitution.md` before changes. Follow upstream Spec Kit prompts in `.agents/commands/`; generic integration is intentional. Active feature artifacts live in `specs/002-custom-frontend/`.

Fios is a custom React/Vite frontend and Express/SQLite backend. Open WebUI is retired; `specs/archive/001-open-webui/` is historical only. Do not restore that deployment. Preserve the purpose-built UX, local-first architecture and exact MLX model IDs.

Validation:

```sh
npm ci
npm test
npm run build
npx playwright test
npm audit
docker compose config --quiet
node scripts/check.mjs
```

Browser/API tests use mock MLX and isolated databases. Real inference is opt-in via `node scripts/check.mjs 'EXACT_MODEL_ID'`; select an already-loaded or appropriately small model, not a huge cold Studio model. Update feature tasks and validation evidence honestly.

Never print `.env`, resolved Compose secrets, or passwords in logs/responses. Keep inference native on macOS. Do not alter RDMA, enable remote execution, expose public/LAN ports, or delete the detached legacy data volume without approval. Do not open the same SQLite file from two application instances; startup recovers stale streaming rows.
