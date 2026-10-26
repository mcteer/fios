# Contract: Browser Progress, Sources and Storage

Existing authenticated message POST/stop/detail/delete endpoints remain. **No `/api/search` endpoint, browser tool invocation, per-message search toggle or Node retrieval pipeline.** Multer field count stays content/model plus files. Browser-supplied search context, URLs, headers/provider settings or tool names are rejected/ignored by the existing strict request boundary, never trusted as harness provenance.

## Request path

Express mechanically extracts <=2,000-unit current and immediately preceding plain user prose with attachment/elision flags and sends it privately to Python alongside canonical local context. It does not judge intent, form a query, perform SearXNG/page HTTP or inject evidence. Existing authentication, same-origin checks, single-active-run slot, limits, pre-persistence admission/worker readiness and localhost binding remain.

## SSE extensions

After existing `meta`, the existing stream can include:

| Event | Payload / semantics |
| --- | --- |
| `search` | exact `{phase,outcome,reason,tool_attempted}` using data model §2.1 mapping; pending/null is nonterminal; no raw query/tool args |
| `sources` | exact v=1 StoredWebRetrieval manifest from data model §4: phase/outcome/reason/tool_attempted/evidence_state/retrieved_at/sources; each source uses id/url/title/kind/retrieved_at/excerpt_sha256/excerpt_units/truncated; **no excerpts/query/page body** |
| `answer_reset` | `{reason:"tool_requested"}` at most once; clear current preliminary answer accumulator/UI and save cleared content before continuing |
| existing delta/reasoning | current response incremental text, with reasoning transient only |
| existing error/done | established terminal status; search metadata persists independently of answer completion |

Node validates before relaying or storing. Unknown/oversized/incorrectly correlated metadata is agent_protocol_error, not raw JSON forwarded to the browser. Safe progress resets the supervisor idle clock; SSE keepalive is not model progress. Event order: meta first; search before final sources; retrieved_only may precede sent_to_model; no additional metadata/answer updates after terminal. Persist authoritative final outcome before done. For nonempty evidence, validate/store the finished status and immediately following first source manifest as one atomic update before relaying that pair. No answer delta may intervene. Only evidence_state changes in a subsequent sent_to_model manifest; empty outcomes need no sources event. Metadata write failure aborts generation rather than misrepresenting source provenance.

When a model chooses no tool, final state is **not_requested / “No web search used”**, not an assertion that web evidence was unnecessary. Known admin off/privacy-ineligible states get appropriate labels. Server rejection/unknown tool is safe error text, never raw SDK exception. After successful search but failed answer, show available sources and incomplete/error answer honestly.

## Detail/history

`GET /api/chats/:id` adds `web` to each assistant message: null for legacy rows; otherwise validated safe manifest + phase/outcome/evidence_state. Do not expose raw stored invalid JSON or unknown schema fields. Old conversations work without fabricated no-search evidence. Reload never invokes search or marks prior timestamps fresh. Saved assistant text is replayed as normal chat context, but prior tool messages/excerpts/query arguments are never replayed.

Sources show title, destination hostname/link, retrieved time and **Page**/**Search snippet** label. Source badges mean the source was supplied to the model (`sent_to_model`), not that the assertion was fact-checked. `retrieved_only` sources remain inspectable but clearly not confirmed as supplied to a continuation. Unread pages are never labeled read, retrieval time is never publication time.

## Citation rendering and security

Recognize `[S1]`..`[S5]` in assistant text only in prose/linkable text nodes; do not rewrite code blocks or ordinary links. Resolve within that message's manifest only. Until that answer's manifest has evidence_state=sent_to_model, treat citation markers as inert text; retrieved_only source-list links can be inspected separately but receive no supplied-evidence citation badge. Unknown IDs stay inert/unverified; raw model URLs get no source badge. Repeated IDs can link to the same source, not create extra records. Source identifiers are message-scoped, so S1 in another answer cannot borrow a prior source.

Use escaped React text, no raw HTML, no remote favicons/images/embeds/prefetch. Validate href scheme/authority/length again; links open only on user action with `noopener noreferrer` and no-referrer. Do not turn link clicks into authenticated Fios proxy fetches. Malicious titles/URLs must not execute scripts or leak sessions. Keep current CSP (external connect/img remains blocked in browser).

Keyboard access, accessible names, visible focus and an `aria-live=polite` progress region are required. Sources collapse/expand without losing draft/scroll control; no layout regression at desktop/mobile widths. Cancellation during model decision, search or continuation uses existing Stop and preserves the correct current partial after any reset.

## Persistence and compatible rollback

See [data-model](../data-model.md). One new table; Express only. Initial state/assistant placeholder atomic, metadata updates bounded, terminal state and last partial saved, crash recovery explicit. Conversation deletion cascades all provenance. Keep old schema/positional SQL intact; upgrade→old→new must retain source rows and old-version deletes must remove them. Rollback display in old UI can omit sources but must not corrupt messages/data. No destructive restore unless separately reviewed compatibility failure requires it.
