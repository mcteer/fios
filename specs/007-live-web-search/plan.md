# Implementation Plan: Harness-Native Automatic Web Search

**Branch**: `007-live-web-search` | **Date**: 2026-10-25 | **Spec**: [spec.md](spec.md)
**Input**: User-approved automatic search **as a tool inside the Pydantic AI harness**. Subsequent approved fix replaces direct DDG with our own containerized SearXNG in the same stack; no new spec.
**Status**: Implemented on the feature branch; see validation.md for actual test evidence and remaining live/release gates. Production unchanged. This document retains the reviewed design; numeric budgets originated as explicit proposals, not additional user answers.

## Summary

Extend the existing private Python Pydantic Agent with exactly one read-only `web_search(query)` function tool. The model decides whether to invoke it. The tool validates the proposed query, retrieves local SearXNG JSON results and bounded public-page evidence, returns a structured untrusted-evidence result and emits safe provenance. The same agent/model can then produce a final answer. No Node-side intent routing/search, extra classifier, generic URL-fetch tool or model-provider-hosted search. The sole approved supporting addition is SearXNG, not another inference/orchestration service.

First-release envelope: **one attempted tool and at most two actual model POSTs**, same exact ID, no retries. No-tool turns remain one request. Search failures produce a safe result/visible limitation, not alternative engines or no-tools retries. Query/page security is enforced in Python code, not only in prompts. Supporting helpers remain inside the same OrbStack application container.

## Technical Context

**Language/Version**: CPython 3.11.17/uv 0.13.5; existing Node 22.23.4/24.15.0 test matrix; React 19/Vite frontend.
**Primary Dependencies**: preserve `pydantic-ai-slim[openai]==2.61.0`, `openai==3.37.0`, `httpx2==2.16.0`; declare already-locked `httpcore2==2.16.0` and `certifi==2026.10.23` directly (the latter fixes verified TLS in the minimal image); additions `dnspython==2.9.0`, `Protego==0.7.0`, frozen transitive lock/audit before use. stdlib HTMLParser in bounded installed parser subprocess. No new npm package.
**Storage**: Express-owned existing SQLite; additive per-assistant-message `web_retrieval` table, FK cascade, no old column/insert changes. Query/pages/excerpts/tool transcript/decision reasoning never persisted. Safe source metadata/hash/outcome only.
**Testing**: Python unittest with real Agent/mock MLX tool-call SSE and injected public HTTP/DNS; Node protocol/API/store/security; Playwright desktop/mobile; native ARM64 mock-only container recovery. Separate opt-in live provider and actual-model-tool checks.
**Target Platform**: existing hardened ARM64 app container on OrbStack; native macOS MLX/RDMA unchanged. One new internal-only SearXNG container; no published port or native helper. Parser child is a private installed harness helper, not a daemon.
**Project Type**: existing local-first web app + supervised inference harness.
**Performance Goals**: search tool total <=15s, controlled cancellation/reap <=2s; live answer continues incrementally. Existing 1 GiB/2 CPU cap unchanged, tested with maximum context plus evidence/parser.
**Constraints**: tools exact allowlist, raw-model-request counting, no prompt/query/body logs, no cloud requests except SearXNG's explicit Bing/Brave engine set and bounded public-page retrieval, no live inference/discovery/provider probes in CI (mock health checks remain required), no SQLite in Python.
**Scale/Scope**: single-user/single active generation; one query, up to5 results/3 page chains. No multi-step research, recursion, crawl/index/vector store or new model selection.

## Constitution Check

| Principle | Pre-research / post-design result |
| --- | --- |
| Specification first | Pass: dedicated 007 branch, user architecture correction recorded, spec/clarification/design/tasks before implementation |
| Purpose-built frontend | Pass: add source/status affordances to existing UI, preserve current UX and exact IDs |
| Native inference, isolated workloads | Pass: Python tool/parser in existing app container; MLX/RDMA remain native and untouched |
| Secure by default | Pass by design: same authentication/localhost bounds, no arbitrary execution, public-network gate, app no Docker socket |
| Persistent/reproducible | Pass by design: additive provenance table, exact package pins/lock, same-image upgrade/compatible rollback rehearsal required |
| Verify honestly | Pass: provider probe evidence separated from unrun tool integration/model behavior; live tests opt-in and CI mock-only |

**Existing guidance change required before implementation:** `AGENTS.md`, README and `scripts/check-agent-boundary.mjs` currently prohibit all tools/assume one request. User has explicitly authorized this one harness tool. After implementation approval covers this plan, update the policy/guard narrowly for `web_search` and the proposed one-attempt/two-request maximum; do not describe the numeric limits as a separate user answer; keep arbitrary tools, shell/file access, MCP, retries, fallback and telemetry forbidden. No constitution principle bans this read-only tool, so no constitutional amendment/exception is needed. Do not simply delete the boundary guard.

## Project Structure

```text
specs/007-live-web-search/
  spec.md, clarification.md, research.md, plan.md, data-model.md, quickstart.md
  contracts/agent-search.md, contracts/public-retrieval.md, contracts/browser-api.md
  checklists/requirements.md, tasks.md
src/agent/fios_agent/
  harness.py                 # exactly one Agent Tool, same-run continuation
  context.py                 # continuation accounting; strip transient thinking
  transport.py               # per-response sentinel + actual POST dispatch budget
  protocol.py, worker.py      # coordinated IPC v2 / settings / cancellation
  web/
    __init__.py, types.py     # strict query/evidence/provenance/run-deps types
    tool.py                  # Pydantic search tool and safe progress/results
    query.py                 # argument privacy boundary, not intent routing
    http.py                  # pinned-address public HTTP transport and DNS
    searxng.py                # fixed private JSON endpoint; guarded public sources
    pages.py, robots.py      # bounded allowed-page extraction and site rules
    parser.py                # isolated bounded parser entry point/helper
src/agent/protocol.js, client.js # validate/relay only; no search call/provider URL
server/index.js, store.js, lib.js # raw-user provenance, persistence, SSE relay
src/main.jsx, styles.css, components/WebSources.jsx # safe sources/status/reset UI
scripts/check-agent-boundary.mjs, check-agent-container.mjs, check-web-search.mjs
pyproject.toml, uv.lock, README.md, AGENTS.md, .env.example, compose.yaml
tests/agent/test_web_*.py, tests/web-*.test.js, tests/fixtures/web/*
tests/browser/web-search.spec.js, tests/mock-mlx.js, tests/fixtures/web-worker.py
```

No Node retrieval modules. `Dockerfile.searxng`/`services/searxng/` supply the pinned nonroot/read-only Compose service with a separate internal app network and egress network,256MiB/0.5CPU cap, no credentials/data/socket mounts or retained request logs. `scripts/check-web-search.mjs` is only an opt-in test driver, not production orchestration; provider-only mode invokes the installed Python adapter in a disposable hardened app container with init and a disposable Compose SearXNG service without MLX, model mode uses the authenticated normal Fios API and requires an explicit exact model ID.

## Phase 0 — Research conclusions

See [research.md](research.md). Historical direct-DDG runtime acceptance was blocked. The user explicitly selected SearXNG as the fix. Its pinned configuration queries Bing/Brave concurrently, with no automatic engine-set fallback, proxies or hidden retries. Live provider-only acceptance returned5 sources/2 pages, partial because an upstream failed and some pages were unavailable; this is not real-model competence. Pinned Pydantic docs/source support Tool/prepare/RunContext/stream-events/hooks; limits alone do not count unsuccessful attempts/all HTTP retries, so add explicit counters. Installed MLX docs expose tools/tool_choice, but actual exact-model support remains unverified until an authorized live test.

No unresolved architectural choice: search is an agent tool in Python. Remaining uncertainty is empirical (HTML drift, parser/transport correctness, model tool behavior, memory/rollback) with explicit test tasks and release gates, not a license for alternative architecture.

## Phase 1 — Runtime flow and interfaces

1. Express authenticates, reserves existing generation slot, parses attachments, validates exact model/host, builds canonical history and readies worker as today. It sends bounded **raw user provenance** separately, mechanically copied from current/prior user records (not queries, intents or provider URLs). Protocol validation still precedes insertion.
2. Python checks exact-model readiness and canonical limits, creates one per-run search context/cancellation scope, and offers only `web_search` if enabled and safe. Safety/configuration eligibility does not classify whether the user needs search. Model request 1 uses auto tool selection and exact ID; normal direct response is allowed.
3. Handle streamed tool-call parts without rendering raw args/names as answer/reasoning. Enforce raw argument/part bounds before SDK accumulation; require first response `[DONE]` before side effects. Unknown/multiple/invalid calls fail closed, never repair/retry. A valid tool invocation consumes the attempt before any safety/network check.
4. Tool checks query provenance/secrets and remaining context budget; emits pending search status; queries only the fixed internal SearXNG JSON endpoint, validates public result URLs, fetches allowed pages and builds bounded evidence. Before returning/emitting its first source manifest, finalize context fitting over canonical history + intermediate text/args + fixed instructions/tool-schema/result text, excluding transient thinking. Reduce/omit only evidence, then assign immutable source IDs/hashes. If even the safe failure continuation cannot fit, emit context error. Expected retrieval failure/global timeout becomes a safe result with empty sources/null retrieval time; page failures within the deadline may leave partial/snippet evidence. Cancellation aborts instead of becoming a continuation-enabling result.
5. Remove the tool from subsequent definitions via prepare and enforce before-request hook/counter. Strip transient thinking and recheck the finalized context/result; a later overflow/mismatch aborts, never rewrites emitted provenance. Recheck model readiness/cancellation before the only possible continuation. Raw transport permits request 2 only following the accepted tool result; no third request.
6. Sources are `retrieved_only` until the result-bearing model request is actually accepted (HTTP 200) by the exact gateway. Then only evidence_state advances to `sent_to_model`; this means delivered, not that a model used every source correctly. Node atomically validates/persists a nonempty finished status with its immediately following first source manifest before relaying them. Empty outcomes use status only and evidence_state=none. Browser citation markers remain inert until that answer's manifest is sent_to_model; separately inspectable retrieved_only links have no supplied-evidence badge.
7. Live text from request 1 may precede a tool call. On the validated call, `answer_reset` clears that preliminary text in UI and store before search/continuation; aggregate output counters do not reset. Request 2 text streams as the answer. If no tool call occurs, request1 text is already the answer. Preserve current-step partials on error/stop; never append the aggregate Agent result a second time.
8. Final success requires the Agent's final result plus valid termination for each dispatched response. Store only final/current partial answer and safe provenance, never raw Pydantic message history, query arguments, excerpts or reasoning. Crash recovery marks active retrieval interrupted; saved manifests do not cause fresh retrieval/replay on reload.

## Bounds and failure behavior

Normative bounds are in [agent contract](contracts/agent-search.md) and [retrieval contract](contracts/public-retrieval.md); exact required object shapes, exhaustive outcome/reason pairs, nullability and state transitions are centralized in [data model](data-model.md). Implementation must enforce these in code and parity fixtures. Pending is distinct from no-tool, all non-finished states recover as cancelled, and completed retrieval survives a later answer failure. Provider Retry-After is never shortened to15min: honor full valid deadlines; malformed/conflicting/nonrepresentable present values suppress provider access for the worker lifetime, with no restart evasion. Expected failure continues once with a limitation; invalid protocol/unknown tool/excess request/missing sentinel aborts. Provider unsupported-tools response is not retried without tools. Models that answer without invoking search get `not_requested`, not an invented `not_needed` judgment.

FIOS_WEB_SEARCH defaults `auto`, `off` is an operator override passed to Python. Fixed provider; no environment-specified arbitrary URLs in production. Test-only dependency injection cannot be activated by a browser field or normal production environment. The deployment controller can retain current environment defaults; forwarding a future off override must be wired explicitly in Compose/controller environment (not a native config process). No runtime source checkout mounts.

## Persistence, rollout and validation

[Data model](data-model.md) preserves the existing schema layout. New table is additive, single owner, all raw retrieval content ephemeral. Existing old binary must ignore rows and retain FK cascade behavior; test actual old-version deletion/rollback/re-upgrade, startup interruption, new rows and backups. If compatibility fails, do not claim image-only rollback; halt rollout and obtain an explicit migration/restore plan.

[Quickstart](quickstart.md) separates mock Agent acceptance, live Python provider smoke and optional authorized real exact-model tool behavior. Real grounded answer must be observed before advertising that named model as verified. No test uses a huge cold Studio model or cluster changes. Final release still needs all six exact latest-head checks, green merged-main CI, controller build-before-stop/backup/verify/rollback, authenticated source/history check and same-image installed worker verification. Test required changes to deployed controller environment without replacing the controller mid-transaction.

## Complexity Tracking

No constitution violation. Complexity added is necessary to the user-selected tool architecture: bounded second model step, stream-phase reconciliation, public egress validation and additive provenance. No separate service, alternate model, classifier or runtime indexing stack is justified. Parser helper process is a bounded internal operation under the harness, tested for parent-death cleanup and included in the app resource cap.
