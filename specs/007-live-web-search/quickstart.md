# Quickstart / Acceptance Guide — Spec 007

**Acceptance guide.** Original PR#8 is merged/deployed. The user-approved fix on `fix/007-searxng` replaces blocked direct DDG with a local Compose SearXNG service; see `validation.md` for actual current evidence. SearXNG provider-only acceptance retrieved5 sources/2 pages (partial,1 upstream failed); no newly authorized real model tool cycle has run.

## Prerequisites and safety

- Work on a dedicated fix branch for spec007; read the updated spec/clarification/plan/contracts. Runtime is the existing OrbStack app/private harness plus the explicitly approved SearXNG container; no native helper.
- Use pinned uv0.13.5/CPython3.11.17 and noneditable install. Use the updated frozen lock; direct dependencies include the already-locked certifi CA bundle to ensure verified TLS works in the image.
- Do not print `.env`, resolved Compose secrets, prompts/queries/arguments or page bodies. Never open production SQLite from a test app.
- CI/public-network tests use mock transports and dedicated fixture-worker launchers. There is no production environment flag that allows arbitrary private destinations/provider URLs. Test apps have isolated DB/ports and no production credentials or Docker socket.

## Mock acceptance (required before live checks)

```sh
npm ci
uv sync --locked --no-editable --reinstall-package fios-agent
npm test
npm run build
npx playwright test
npm audit
uvx --python 3.11.17 --from pip-audit==2.10.1 pip-audit --path .venv/lib/python3.11/site-packages
node scripts/check-agent-boundary.mjs
docker compose config --quiet
node scripts/check-agent-container.mjs
node scripts/check-searxng-container.mjs # network-none; static health/config, no query
```

Expected new checks:
1. **Real installed Agent, mock model:** streamed `web_search` call → single Python tool execution → structured tool return → same exact model continuation. Assert actual tools declaration/arguments/results, two POSTs maximum, and no Node search/networking. No-tool fixture emits text with one POST and zero search requests.
2. Unknown/malformed/repeated/parallel calls, retries, third request or missing `[DONE]` on either step fail closed. Raw tool args never enter browser/log/DB. Mixed text-before-tool is reset, final text streams once; reasoning remains transient and is absent from continuation.
3. Guard attachment/secret/private-token leakage, DNS rebinding/mixed answers, numeric IPv4/IPv6 forms, redirects/downgrades, wrong cert, headers/cookies, parser bombs, response limits, robots and challenge/429. Assert numeric socket target and preserved TLS hostname, not just URL validation. Test full Retry-After seconds/HTTP-date (>15min included), zero/past/missing and malformed/conflicting/overflow values: no early request, delayed replay or restart evasion.
4. Search failure/timeout returns explicit evidence outcome and at most one bounded explanatory continuation. Cancellation before/during tool or before step2 gives zero subsequent model calls; kill/reap parser including worker parent-death in Linux container.
5. Authenticated progress/sources/reset/detail/delete, exact outcome/reason pairs, pending versus no-tool, null timestamps with empty sources and atomic finished-status/source pairing. Context fitting precedes immutable manifest emission; only evidence_state can advance, and citations stay inert until sent_to_model. Cover invalid citations, untrusted titles/links, desktop/mobile keyboard and screen-reader labels. Metadata persists across reload; query/excerpt/tool transcript/reasoning does not.
6. Actual isolated old→new→old→new compatibility, old-version cascade deletion, idle/searching/fetching interruption recovery while preserving already completed retrieval after an answer failure, stopped backup/restore and injected failed-upgrade automatic rollback. App resource bounds remain1GiB/2CPU with maximum context/enrichment/parser. The approved SearXNG service has no published ports/app credentials/DB/socket; no app/observer socket access.

## Live provider only (nonsensitive, no model)

Explicit test command (not a health check or automatic retry):

```sh
node scripts/check-web-search.mjs --provider-only --query 'Python 3.11 release notes'
```

The driver invokes the **installed Python provider adapter** in a disposable hardened app-image container **with init**, alongside a disposable Compose SearXNG service, no model/DB/socket and a fixed nonsensitive query. Both images/networks/services are cleaned up. Init is required because the parser correctly refuses a PID1 parent; do not weaken that guard. The actual tool/Agent cycle is separately covered by installed-package mocks and the opt-in model gate; this provider-only driver does not simulate model competence. It must not implement a Node search client. Report safe counts/status/evidence kind only; verify actual organic extraction plus at least one allowed page or honestly report snippet/blocked state. Do not solve challenges or retry through other clients/endpoints. Health checks never perform this operation. A blocked result is a valid failure test, **not** proof that live retrieval succeeds.

## Live model tool cycle (separate explicit opt-in)

Only after user authorizes a new inference test and an exact appropriately small/already-loaded model is selected:

```sh
node scripts/check-web-search.mjs --model 'EXACT_ADVERTISED_MODEL_ID'
```

Use the authenticated app API/normal Agent path with an isolated acceptance app or a uniquely identified temporary production chat, never a second process opening production DB. Ask a nonsensitive question whose answer requires the fetched fixture/current source; verify an actual native tool call, SearXNG result, same-ID continuation, source manifest and completed stream. Delete only the temporary test chat in finally. One approved run, no automatic retries/substitutions/large cold Studio model. If it answers without tools, report **tool behavior unverified/no-tool**, not a pass or a cue for forced Node retrieval. If unsupported, report it; no alternate model without approval.

The prior real Gemma text-attachment smoke did not prove tool calls and is not blanket permission for this new check. SC-007 cannot be checked off using mock model behavior. Record exact model, gateway/app revision, whether it was loaded, tool/request counts, source/outcome, cleanup and limitations without private content.

## Delivery/rollback

Dedicated reviewed feature PR with all six exact latest-head checks. Wait for independently green merged-main CI, then existing container delivery builds before stopping, preserves old image/stopped-data backup, deploys and verifies health/authenticated catalog plus installed worker/provenance compatibility without unsolicited inference. From clean green merged main, build/start the pinned `searxng` Compose service (README commands); no branch-built supporting image is deployed. The stable controller's app-only transaction intentionally does not recreate supporting services. Missing/unhealthy SearXNG yields search failure, not fake model unavailability. Keep source evidence and safe failure outcomes distinct from model readiness/health. Retain backups/rollback images; if additive schema compatibility fails, stop rollout and obtain a restore plan rather than overwriting data.
