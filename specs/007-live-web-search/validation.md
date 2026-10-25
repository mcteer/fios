# Spec 007 implementation and acceptance evidence

## Approved SearXNG fix — current checkpoint

Original PR#8 merged as `b3db969cc7b529205c738644c38529fa4d02f51f`, passed independent main CI40244490679 and was automatically deployed/healthy. The user then explicitly selected our own SearXNG **container with the existing stack**, as a fix to007 rather than a new spec. The following current record supersedes DDG-only/no-new-service assumptions in the historical checkpoint below.

### Fix implementation

- Python retains the sole automatic `web_search` function tool and all privacy/model-count/context/cancel/manifest/IPC/storage/UI controls. `web/searxng.py` replaces the direct-DDG adapter. Its separate unauthenticated, nonredirecting, no-proxy client reaches only `http://searxng:8080/search` with a validated query and fixed JSON/general/en/safe-search/page1 parameters. No endpoint environment override or generic private fetch is provided. Result URLs still pass the unchanged public-only page/robots DNS/IP/redirect/TLS checks, including rejection of the gateway as a source.
- `Dockerfile.searxng` derives from official index digest `sha256:23482d8ecf7ddf66029479468ea04c1bb11d2b65785a17a7e629e2ffd13296ca`, version2026.10.25-54ca1d9cf/source54ca1d9cfb08674f66261d7f351b063558dfcc62, AGPL-3.0-or-later. The app's frozen Python29-package lock is unchanged. The supporting image has its own packaged Python/dependencies, not the app interpreter.
- Compose adds `searxng` only:977:977, read-only/cap-drop/no-new-privileges,256MiB/0.5CPU, disposable tmpfs, random process-local secret, no published ports/app credentials/SQLite/socket/host checkout mounts, no retained access/query logs. App↔gateway uses an internal-only network; SearXNG has a distinct egress network. Static `/healthz` checks do not issue a query and do not prove upstream availability.
- Bing/Brave are an explicit concurrent upstream set, not a fallback ladder or local index. Queries leave the machine through those engines. Configured request timeout3s/max4s/retries0; no proxy/Tor/key or custom CAPTCHA workaround. SearXNG owns engine networking, outside the custom page transport; do not claim identical pinned-IP/header/robots policies or14 total wire requests across both processes. The harness still counts at most14 attempts, including the one gateway request, and bounds its full tool to15s. Already-started service engine work can finish under its timeout after app cancellation; no post-cancel model continuation is permitted.
- JSON responses/body/header/result count/field types are bounded; arbitrary answer/infobox data is ignored. Malformed/schema/redirect/private-result/rate/error cases fail safely; zero results with upstream errors is unavailable, and real sources with upstream errors remain partial. No raw query, response, title, URL or body is printed by the acceptance driver: safe counts/status only.

### Actual checks

| Check | Observed result |
| --- | --- |
| Failing-first installed test | `test_searxng.py` initially failed because the installed module did not exist; after noneditable rebuild it passed |
| Frozen noneditable rebuild / `npm ci` | Pass; app lock remains29 packages |
| `npm test` | **57 Node/API +81 Python tests passed** |
| `npm run build` / Playwright | Pass / **11 browser tests passed** |
| App Node/Python dependency audits | No known vulnerabilities; first-party `fios-agent` not on PyPI remains an explicit skip |
| SearXNG installed Python distributions | Exported version-only metadata from the pinned image under network-none; pip-audit2.10.1 `--no-deps --disable-pip` found no known vulnerabilities. Does not audit OS packages, vendored engine source or certify security; CI now repeats this check |
| Boundary checker / quiet Compose / diff check | Pass, no resolved credentials printed |
| ARM64 app/tool + upgrade/rollback/restore rehearsal | Pass, **610MiB** peak under unchanged1GiB/2CPU; actual installed-Agent mock JSON continuation, max/near-limit context/images/evidence, metadata retention/old deletion cascade, stopped backup/restore and injected failed-upgrade rollback |
| Offline SearXNG image/config/static health | Pass with `--network none`, nonroot/read-only/256MiB/.5CPU, exact Bing/Brave set and JSON-only configuration; added to the existing ARM64 CI check, no live query |
| Actual SearXNG provider-only acceptance | **Pass/partial**: gateway HTTP200,10 results,5 retained sources,2 fetched pages,6 harness HTTP attempts,1 failed upstream. This is actual organic/page access, not all-engine availability or real model competence |
| New native model inference | **Not run; fresh exact-ID opt-in still required** |

The provider driver initially returned unavailable despite valid SearXNG results because its Python process was PID1. The parser correctly rejects a PID1 parent to prevent orphans; using `docker run --init` fixed the driver. The guard was not weakened. Early diagnostic runs did not prove retrieval and are not counted as passes. Metrics contain only response status and counts. The final successful fixed-query run used disposable Compose resources and cleaned up containers/networks/images; no production DB/model/service was used.

Logs: `/tmp/fios-searxng-final-tests.log`, `/tmp/fios-searxng-final-browser.log`, `/tmp/fios-searxng-final-container.log`, `/tmp/fios-searxng-audit.log`; detailed610MiB rehearsal `/var/folders/hq/9t1wgm2x713f5qykp8y8wldc0000gn/T/fios-agent-test-27aae54c-cdd.log`. Provider-only driver reports counts without retaining captured queries/pages. No new real-model inference was authorized/performed.

### Release state

Fix branch `fix/007-searxng`; production remains on the original007 release at this source checkpoint. F007 (dedicated reviewed PR/exact-head CI/independent green main/service provision/controller delivery) is pending. Build/start supporting SearXNG only from clean green merged main, not a feature-branch test image. The stable controller remains app-only during its SQLite transaction; provision the support service separately with README commands. Record subsequent exact-head/run/deployment outcomes in the PR, not a self-referential source commit. T039/SC-007 remains unrun regardless of provider-only success.

## Historical checkpoint before original PR#8 merge (2026-10-25)

Everything below records that earlier implementation state, not the current provider or release status.

### Original status (2026-10-25)

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
