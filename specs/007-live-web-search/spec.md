# Feature Specification: Automatic Live Web Search

**Feature Branch**: `007-live-web-search`
**Created**: 2026-10-25
**Status**: Specified and clarified; planning artifacts only, implementation not started.
**Input**: Add DuckDuckGo live web search as retrieval-augmented generation for local models. User chose automatic activation and explicitly requires a **search tool inside the Pydantic AI harness**.

## Clarifications

### Session 2026-10-25

- Q: How should web search be activated? → A: **B — automatic**. The user does not enable it separately for each message. DuckDuckGo is the requested provider.
- User architecture constraint: “This needs to be built into the Pydantic harness.” Search is not a Node/Express pre-generation pipeline or a separate service.
- Q: Should the agent invoke a search tool or should retrieval be a pre-generation stage inside the harness? → A: **“Inside the harness as a search tool.”** The Pydantic agent decides when and what to search.
- The earlier assistant-chosen deterministic intent router, Node retrieval modules and associated npm dependencies are withdrawn. They must not be implemented.
- Scope of this workflow: specify → clarify → plan → tasks → read-only analyze, with user-authorized document remediation and repeated analysis until planning findings are resolved. No implementation, deployment or new real model inference is requested.
- Privacy clarification: DuckDuckGo is privacy-oriented but queries/connection metadata leave the machine; independently fetched sites see requests. Minimize disclosures without imposing repeated consent prompts. No anonymity or infallible secret-detection guarantee.

## User Scenarios & Testing

### User Story 1 — Agent automatically searches for evidence (Priority: P1)

As a user, I ask a current-information question and the selected local model can call DuckDuckGo through the Pydantic harness, read the result and answer with sources. I do not choose a search mode.

**Why this priority**: This is the requested model capability, not an unrelated preprocessor deciding for the model.

**Independent Test**: The installed real Pydantic agent with a mock MLX tool-call stream invokes only the registered search tool, consumes fixture evidence and continues with the same exact model; a no-tool stream makes no external request.

**Acceptance Scenarios**:
1. **Given** the selected model requests `web_search`, **when** the harness accepts a safe query, **then** DuckDuckGo evidence returns as a real Pydantic tool result and the same agent continues to an answer.
2. **Given** the model answers a self-contained task without requesting the tool, **when** its response completes, **then** there are no DuckDuckGo/page requests or hidden classification-model calls.
3. **Given** a follow-up about a prior public topic, **when** the model forms a query, **then** it may use only bounded eligible current/preceding user terms, not leak attachments or the transcript through tool arguments.
4. **Given** a completed tool result, **when** answer generation continues, **then** final answer text streams with existing cancellation/partial-output semantics and exact model identity preserved.
5. **Given** a selected model cannot produce supported tool calls, **when** it declines search or the server rejects tool parameters, **then** Fios reports no search/the error honestly, without substituting a model, forcing a Node search or automatically retrying without tools.

### User Story 2 — Inspect sources and know the limits (Priority: P1)

As a user, I can see when the model searches, inspect the sources actually supplied to it, and distinguish retrieved evidence from unsupported claims.

**Why this priority**: Automatic web access must be transparent and not imply verification merely because a model writes a link.

**Independent Test**: Render searching, page-backed, snippet-only, unavailable, timeout and invalid-citation fixtures, then reload/delete the saved conversation.

**Acceptance Scenarios**:
1. **Given** a search tool is executing, **when** I view the response, **then** Fios shows progress and eventually safe source links/titles, evidence type and retrieval time, without exposing raw tool arguments or reasoning.
2. **Given** a model cites a source identifier, **when** Fios renders it, **then** a citation link is created only for an actual source supplied to this answer; unknown identifiers are unverified.
3. **Given** search failed or returned no useful evidence, **when** the same agent produces its bounded final answer, **then** the UI retains an explicit lack-of-current-evidence notice and does not claim a successful search.
4. **Given** a saved answer, **when** I reload it, **then** source provenance/outcome remain without rerunning search or presenting the old evidence as current.
5. **Given** early model text is followed by a tool call, **when** the answer continues, **then** preliminary text is not concatenated into the final grounded answer as if it were part of that answer. Cancellation still retains the appropriate current partial answer.
6. **Given** I navigate sources on mobile or with a keyboard, **when** I inspect links/status, **then** labels and controls are accessible without relying only on color or remote embeds.

### User Story 3 — Keep the harness tool narrow, safe and local-first (Priority: P1)

As the operator, I want only bounded read-only search, not arbitrary agent capabilities or private-network access.

**Why this priority**: Tool arguments and page text are untrusted; neither may expand privileges.

**Independent Test**: Exercise hostile arguments/pages, secret fixtures, invalid/duplicate tool calls, redirects/DNS rebinding, cancellation and exceeded budgets; assert no forbidden request or subsequent inference.

**Acceptance Scenarios**:
1. **Given** the local model has seen private attachments/history, **when** it proposes a query containing material outside the eligible user-term boundary or recognized secret/code/private-context patterns, **then** the harness rejects it before any external request. Local model context is not permission to transmit that context.
2. **Given** retrieved text tells the model to exfiltrate secrets, run code or search again, **when** the agent processes it, **then** no new tool capability or second search is permitted.
3. **Given** a result/redirect resolves to local/private/special-use addresses, **when** retrieval validates it, **then** access is blocked, including resolution changes and mixed public/private DNS answers.
4. **Given** a page requires scripts, login, CAPTCHA or exceeds limits, **when** encountered, **then** it is skipped/reported, never bypassed or supplied with Fios/MLX credentials.
5. **Given** stop/disconnect/model loss occurs during the tool cycle, **when** it is handled, **then** outstanding retrieval is closed and no further model request starts for the canceled/unavailable run.

### Edge Cases

- Tool-capable protocol does not prove a particular model knows when/how to call tools; chat/host readiness is not a tool-support certification.
- Text and tool-call fragments interleaved in one response, malformed arguments, unknown names, duplicate/parallel calls, missing `[DONE]` on either model response.
- Prompt injection, private prose not recognizable by patterns, query terms copied from attachments, alternate alphabets/encodings and ambiguous follow-ups.
- DuckDuckGo HTML changes, HTTP 202 challenges, 429, no results, unavailable page, robots denial, contradictory/stale sources and absent publication dates.
- Cancellation before arguments finish, during DNS/body/parser work, after a result but before continuation, or while Node is persisting progress.
- Existing context near its limit; generated intermediate text/arguments plus tool results also consume the continuation budget. No silent loss of user data.
- Restart/crash during retrieval; upgrade→old image→new image with provenance present; deleting a conversation under an older compatible version.

## Requirements

### Functional Requirements

- **FR-001**: The **Pydantic AI agent** MUST decide automatically whether to call the search tool and supply its query. No deterministic intent router, separate classifier generation, per-message activation or consent prompt may replace that decision. The tool is offered by default subject only to safety/configuration/budget gates.
- **FR-002**: The only search provider MUST be DuckDuckGo. Verify actual organic web-result access; Instant Answers are not general search. Challenges/unavailability MUST NOT trigger alternative engines, proxy rotation, CAPTCHA bypass or hidden retries.
- **FR-003**: The harness MUST validate model-generated queries at the external boundary. It MUST NOT export full transcripts, attachment contents, application credentials or raw tool arguments by default. Only bounded eligible user-authored terms plus a fixed generic search vocabulary may be sent; recognized secret/private-context/code patterns, ambiguous eligibility and out-of-bound arguments MUST be rejected. Document the limits of sensitive-data detection honestly.
- **FR-004**: Retrieval MUST be read-only and bounded in calls/results/bytes/time, public-web-only, with URL/redirect/DNS/connection validation. No scripts, arbitrary URL-fetch tool, cookies, application credentials, unsafe scheme, private-address request or unrestricted browsing.
- **FR-005**: Sources MUST be marked untrusted in the tool result, separate from application instructions; they MUST NOT authorize new capabilities. Only `web_search` is allowed. No command/file tools, MCP, provider-hosted search, cloud inference or fallback.
- **FR-006**: Decisions, argument validation, retrieval and evidence integration MUST execute inside the existing Python Pydantic harness. Node/Express only supplies bounded user-text provenance, supervises/cancels, relays validated progress and owns storage/UI. No search orchestration or provider/page networking in Node/Express and no additional search service.
- **FR-007**: The UI MUST expose actual retrieval progress/outcome, safe source titles/URLs, snippet-versus-page evidence and retrieval time. Citations MUST map to sources supplied in that run; a source list MUST NOT be presented as automatic factual verification. Publication date MUST NOT be invented from retrieval time.
- **FR-008**: No-tool, disabled, rejected, no-results, partial, blocked and timeout outcomes MUST remain distinguishable. A failed tool may return a bounded safe failure result to let the agent explain its limits; it MUST NOT silently retry. Saved sources/outcomes survive reload and are removed with their conversation; ephemeral queries/pages/tool transcripts are not persisted/replayed.
- **FR-009**: All new runtime functionality MUST ship in the existing application container. Agent/search execution code MUST stay under `src/agent/`; API, persistence and UI integration remain in their existing server/frontend locations. No native helper, public listener, app Docker socket or cluster/RDMA changes. Python remains a private supervised worker without SQLite access. Health/startup checks invoke neither search nor inference. Logs exclude queries, arguments, page bodies, prompts, secrets and reasoning.
- **FR-010**: Tests MUST exercise actual Pydantic tool invocation/continuation against mock MLX, SSRF/privacy/cancellation/streaming/persistence/browser boundaries and container upgrade/rollback. CI is mock-only. Live provider tests use nonsensitive queries and are separate from model inference; new real model inference requires explicit opt-in. Deliver only via exact-head green PR/main CI and existing backup/verification/rollback policy.
- **FR-011**: Honor site restrictions/robots/access-denial/rate limits. No scripts, credentialed pages, evasion or link crawling. Skipped pages may leave clearly labeled snippet-only evidence; no assertion that an unread page was inspected.
- **FR-012**: Context validation MUST include intermediate model parts/tool arguments/results before continuation. Never silently truncate user history/attachments to make evidence fit. Omit evidence with a visible context-limit outcome if needed; if even a bounded failure continuation cannot fit, stop with a safe context error.
- **FR-013**: Preserve exact IDs, independent model-readiness gates, authentication, streaming, partial output and transient-reasoning privacy. Preliminary tool-turn text is not the final answer. Every actual model response requires its own valid streaming terminator, plus successful agent completion before final success.
- **FR-014**: The narrow exception to the previous no-tools/single-request policy permits **at most one attempted `web_search` and two actual model HTTP requests per user turn**: initial response and, only after an accepted tool invocation/result, final continuation using the same ID. Failed/rejected attempts consume the tool budget. Agent, SDK, HTTP and tool-validation retries remain zero. Repeated/unknown tools, extra requests and incomplete streams fail closed; no model substitution or automatic no-tools retry.

### Key Entities

- **Run search context**: server-authored separation of current/preceding plain user text from attachment-expanded local context; harness derives eligibility, not a browser-controlled search flag.
- **Tool invocation**: model-issued `web_search(query)` with run/tool-call correlation, one-attempt latch and safe outcome; raw arguments ephemeral.
- **Retrieved source**: validated public URL/title, retrieval time, evidence kind, bounded excerpt and provenance; all source content untrusted.
- **Evidence bundle**: bounded tool result with source IDs and status; fed back to the same Pydantic run, not a second agent or persistent index.
- **Answer provenance**: per-answer saved safe manifest, evidence-delivery state and outcome, excluding raw query/page/tool transcript.

## Success Criteria

- **SC-001**: Controlled tool-calling fixtures yield exactly one harness tool attempt and at most two same-ID model POSTs; no-tool/self-contained fixtures make exactly one model POST and zero external retrieval requests.
- **SC-002**: Controlled grounding tests verify the continuation receives the exact fixture-only evidence in a tool result and produces the expected fact. Every rendered citation resolves only to that answer's supplied sources; mock evidence is not a claim of real model semantic quality.
- **SC-003**: Safety fixtures produce zero forbidden network destinations/credential or attachment exports, zero arbitrary tool execution and zero post-cancellation model dispatches.
- **SC-004**: Timeout, no-result, provider challenge, budget, unsupported tool and missing-terminator fixtures yield the documented explicit outcomes, with no provider/model substitution or hidden retry.
- **SC-005**: Saved source metadata/outcomes survive reload and compatible upgrade/rollback; deletion removes associated data. Desktop/mobile/browser and existing harness regressions pass.
- **SC-006**: The search tool completes or returns a safe retrieval-timeout outcome within 15 seconds of invocation, excluding model generation/readiness checks. Cancellation closes controlled DNS/network/parser work within 2 seconds; existing supervisor deadlines remain enforced.
- **SC-007**: Before claiming live search works for a named model, an explicitly authorized small-model test must observe actual native tool-call → search result → same-model grounded completion. Models not exercised remain unverified for tool behavior; there is no heuristic-routing accuracy claim or assumption that all chat models support tools.

## Assumptions and Scope Boundaries

- User-approved architecture: a real agent-invoked search tool inside the Pydantic harness. This is bounded tool use, not open-ended autonomous research. The one-tool/two-request ceiling is the proposed first-release implementation budget, explicitly documented rather than an unbounded policy relaxation.
- No external classifier, vector database, crawler, new model ID, telemetry or paid/proxy service. Automatic mode can be disabled administratively; normal chat then remains one-request/no-tools.
- The local model continues to see ordinary conversation/attachments. Query safety is enforced on its proposed arguments; therefore eligibility metadata and runtime validation—not a prompt alone—protect the external boundary. Unknown sensitive prose cannot be guaranteed recognizable.
- Standard Chat Completions tool support is required. Unsupported-model errors/no-tool decisions are honest outcomes; no hidden emulation, forced search outside the harness or model substitution.
- Retrieved evidence reduces stale-knowledge risk, not hallucination/prompt-injection risk to zero. Provenance means supplied evidence, not fact-check certification.
- The prior Gemma smoke authorization was a completed one-shot test. It does not authorize a new inference test in this planning workflow.
