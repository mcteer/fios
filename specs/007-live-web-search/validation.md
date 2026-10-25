# Spec 007 implementation and acceptance evidence

## Status (2026-10-25)

Core implementation exists on `007-live-web-search`, **not merged/deployed or formally closed**. Passing mocks are not live-provider/model acceptance. Production remains the previously checked main release; no native inference, model loading, RDMA, public ports, persistent supporting services or production database were changed by implementation/testing.

**Release blockers:**

1. T038: the actual installed Python DuckDuckGo adapter returned **`blocked`, zero sources/pages, two HTTP attempts** from the hardened ARM64 container. This is an observed failure, not organic-search acceptance. Do not switch clients/endpoints/providers, solve a challenge, or call the historical planning smoke a runtime pass.
2. T039/SC-007: **no new real model inference ran**. A fresh explicit exact-ID opt-in is required, and a successful actual tool → usable search result → same-model grounded completion must be observed before making a named-model claim. The completed historical Gemma attachment smoke does not supply that permission/evidence.
3. T042–T044: exact-head PR CI/review, independently green merged main, and checked automatic delivery remain separate gates. A draft PR is not release approval.

## Implementation delivered

- Only the existing Pydantic Agent can decide/invoke `web_search(query)`. It uses the real function tool/result conversation, not Node intent routing, a classifier generation, a second agent or text pretending to be a tool call.
- The run-local latch permits one attempted tool. An actual POST-boundary counter caps two exact-ID requests. Agent/SDK/model/HTTP/tool retries are zero, continuation has no tools, and readiness is rechecked before each inference. Unknown/parallel/repeated/malformed calls fail closed. Each response has its own streaming observer/required `[DONE]`; successful SDK completion remains necessary.
- Provenance separates bounded current/immediately preceding raw user text from expanded attachments. Oversized text is elided, not truncated. Query validation rejects recognized secret/private/code/identifier/operator patterns, attachment-only/assistant/page-only terms and ambiguous provenance. Unknown sensitive prose cannot be perfectly recognized; the README documents that limitation and the fact that public requests leave the machine.
- Public retrieval uses a fixed DuckDuckGo HTML endpoint, validated public DNS answers/CNAME edges, numeric pinned sockets, actual peer checks and original-host verified TLS; no proxy/auth/cookie replay. Configured MLX hosts and nonpublic/special/mixed answers fail closed. URL/redirect checks apply to every hop. No generic fetch, scripts, credentials, CAPTCHA evasion, crawling or alternative provider exists.
- Bounded requests, identity-only bodies, aggregate bytes/deadline, robots/cache/crawl delays/request rates and full Retry-After restrictions are enforced. A killed/reaped isolated stdlib parser handles HTML with Linux CPU/address-space limits and parent-death cleanup. It excludes ads/active/hidden/navigation content; visible hostile prose remains untrusted text, not an executable capability.
- Evidence is context-fitted before its first immutable manifest. Hashes/IDs/source identity cannot change during delivery; only `retrieved_only` → `sent_to_model` advances on the exact result-bearing HTTP200 continuation. Original user history/attachments are not silently trimmed. Only supplied IDs receive clickable citation badges; this is not factual verification.
- Private IPC v2 adds strict provenance/status/source/reset contracts. Express mechanically supplies provenance, validates/relays events, atomically persists safe metadata and resets preliminary text/reasoning. Python never opens SQLite. Ephemeral queries/pages/excerpts/tool transcripts/reasoning are not stored/replayed.
- Additive message-FK metadata survives reload and compatible old/new image round trips; deletion cascades even under the old image. Startup recovers unfinished idle/searching/fetching records without replacing finished retrieval outcomes. Invalid/future metadata renders a safe notice rather than unvalidated links or raw fields.
- The browser exposes progress/outcomes/page-versus-snippet/source times, supplied-evidence distinction, inert unknown/unsafe citations and keyboard-operable mobile/desktop sources. No opt-in toggle or browser search-decision logic was added. `FIOS_WEB_SEARCH=off` administratively removes the tool without replacing the model.

## Dependencies / installed packaging

uv0.13.5, CPython3.11.17, Pydantic AI2.61.0/OpenAI3.37.0/httpx2.16.0 remain frozen. The lock resolves29 packages: only dnspython2.9.0 (ISC) and Protego0.7.0 (BSD-3-Clause) are newly resolved. Existing httpcore2.16.0 (BSD-3-Clause) and certifi2026.10.23 (MPL-2.0) are direct exact pins. Python minimums are compatible. No npm dependency/search service was added. Tests rebuild and exercise the **noneditable installed wheel**, not editable source imports.

A live failure exposed managed Python's default trust context failing certificate verification in the minimal image. A sanitized robots-only trace located `SSLCertVerificationError`; DNS-only diagnostics confirmed public answers. Supplying the existing locked certifi bundle fixed TLS without adding a custom root or disabling verification. A regression asserts `cafile=certifi.where()`, `CERT_REQUIRED`, hostname checking and original-host SNI over the pinned socket. The subsequent two-attempt provider result above is still blocked. No search-query retry or alternate client was used to evade that denial.

## Local verification

Final local post-review unit/build/browser/audit checkpoint (2026-10-25; before the documentation-only commit):

| Check | Actual result |
| --- | --- |
| `npm ci` | Pass |
| `uv sync --locked --no-editable --reinstall-package fios-agent` | Pass,29 packages |
| `npm test` | Pass:56 Node/API +77 Python tests, including administrative off/no-tool declaration regression |
| `npm run build` | Pass |
| `npx playwright test` | Pass:11 browser tests;1440px/390px search, keyboard sources, reset/citation/reload and hostile/unsafe link cases |
| `npm audit` | Zero known vulnerabilities |
| pip-audit2.10.1 against installed package path | No known vulnerabilities; first-party `fios-agent` skipped because it is not a PyPI distribution |
| `node scripts/check-agent-boundary.mjs` | Pass; narrowly allows only the reviewed tool registration and denies search orchestration outside harness |
| `docker compose config --quiet` | Pass; no resolved configuration/secrets printed |
| `node scripts/check.mjs` (no model argument) | Authenticated deployed discovery passed,5 chat models; no inference/search performed and not proof of branch delivery |
| `git diff --check` | Pass |

Final post-review ARM64 rehearsal passed at **609MiB** peak under the unchanged1GiB/2CPU app envelope. `scripts/check-agent-container.mjs` observed installed Agent → public fixtures → same-model continuation/Linux parser, forced observer expiry/recovery, worker/parser parent-death/cancellation cleanup,400,000 UTF-16 units with20MiB images,370,000 units plus20MiB images and tool evidence, compatible upgrade → old image → re-upgrade source retention, old-image deletion cascade, stopped backup/restore and injected failed-deployment rollback. This is isolated mock inference, not production database access or native compute cancellation proof.

Logs: `/tmp/fios-007-final-tests.log`, `/tmp/fios-007-final-browser.log`, `/tmp/fios-007-final-container.log`. Detailed final609MiB container log: `/var/folders/hq/9t1wgm2x713f5qykp8y8wldc0000gn/T/fios-agent-test-c049468b-d3c.log`. Earlier549MiB,497MiB and538MiB runs also passed; the final run included the stricter robots/CA checks and mock-network guard.

## Coverage / evidence boundaries

| Requirement | Evidence / remaining limitation |
| --- | --- |
| FR-001,FR-005,FR-006,FR-014 / SC-001 | Actual installed-Agent mocked tool invocation, arguments, one attempt/two same-ID POSTs, continuation tool removal; no-tool/off single-POST tests and static boundary checks |
| FR-002 | Fixed organic parser fixtures pass; **live organic access is blocked**, so this live gate is not complete |
| FR-003 / SC-003 | Shared query canaries, provenance type/elision tests, attachment/private/out-of-origin term denial; no public request on rejected query; conservative policy limitations documented |
| FR-004,FR-011 / SC-003,SC-006 | Special/mixed address/CNAME/peer/URL tests; pinned TLS/minimal headers; DNS/body/header/encoding/attempt/parser caps; robots/cache/delay/rate/Retry-After cases and controlled cancellation |
| FR-007 / SC-002 | Exact fixture-only fact is present in actual tool-return conversation and controlled final output; browser known IDs only, code/unsafe links inert, source status/kind/time shown; no real semantic-quality claim |
| FR-008 / SC-004,SC-005 | Exhaustive outcome/reason fixtures, interrupted/finished state persistence, bad-row safe fallback, source deletion cascade/reload and image round-trip/restore |
| FR-009 | Existing hardened app only, installed private worker, no new service/port/socket/SQLite ownership; unchanged model/readiness/auth/attachments regression suite |
| FR-010 | Local mock checks pass; unit runner forbids nonloopback sockets/DNS, web fixture worker restricts real sockets/DNS to explicit mock MLX hosts; live scripts are explicit and excluded from CI/health; release checks remain pending |
| FR-012 | Full intermediate/result context accounting, strict evidence bounds and visible context failure; near/max-context/image rehearsal; no user-context truncation |
| FR-013 | Per-response sentinels, incomplete first/second streams, fragmented tool arguments/preliminary text, unsupported/unknown/parallel/repeated tools, unchanged exact-ID/readiness/attachment/reasoning regression coverage |
| SC-007 | **Unrun**: fresh opt-in and actual same-ID native grounded tool cycle required |

Stop/disconnect tests interrupt actual installed-Agent public-fixture retrieval, close the stream within2 seconds, persist interrupted/cancelled state and observe exactly one model POST. Parser timeout/cancel tests reap a deliberately unresponsive subprocess. No claim is made about immediate cancellation of native GPU compute. First observed foundation red was `ModuleNotFoundError: fios_agent.web` before installed-package implementation; later regression additions and fixture corrections are not falsely described as a complete recorded red/green transcript.

## Implementation path reconciliations

- Streaming cases live in `test_web_tool.py`, not a redundant `test_web_streaming.py`.
- Actual old/new/old/re-upgrade compatibility is exercised by the ARM64 container driver plus `web-persistence.test.js`, not a synthetic-only `web-upgrade.test.js`.
- `tests/fixtures/web-worker.py` injects public responses into installed code in-process; executable native/container launchers are test-only. There is no separate mock-web listener and **no production bypass environment flag**.
- The provider-only acceptance driver exercises the installed adapter with its fixed nonsensitive query; it does not claim a synthetic/no-model invocation is model competence. The full actual tool cycle has independent mock coverage, and a real model remains an explicit separate gate.

## Delivery

No feature merge/deployment has occurred. Any draft PR/check results should be recorded against the exact head in that PR without manufacturing source-file evidence for a future commit. Keep T038,T039 and release tasks unchecked until their actual gates pass. Do not bypass a failed/skipped/missing check or repeat live queries through changed identities to make this record green.
