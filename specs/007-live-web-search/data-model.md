# Data Model — Harness Search and Answer Provenance

## 1. RunSearchInput (private Node → Python provenance)

Not a search command. Node mechanically copies user-authored text, never chooses a query/intent.

| Field | Constraint |
| --- | --- |
| current_text | string or null; <=2,000 UTF-16 units; null when original is longer, never silently truncate |
| current_has_attachments | strict boolean, including current attachments in this turn |
| previous_text | string or null; <=2,000 UTF-16 units; immediately preceding user turn only |
| previous_has_attachments | strict boolean; true makes previous text ineligible |
| current_elided / previous_elided | strict booleans indicating omitted oversized raw text |

Missing provenance (direct test/legacy caller) fails closed for search, not a request to derive a query from attachment-expanded context. Current attachment-bearing/attachment-only/private/code-marked inputs are ineligible; prior attachments never contribute terms. The ordinary local model still receives canonical history/attachments. Harness uses only this bounded provenance to validate model-generated arguments; raw transcript is not exported.

## 2. SearchRunState (Python memory only)

- `run_id`: existing UUID; exact selected model string unchanged, <=1,024 UTF-8 bytes.
- `tool_attempts`: integer 0..1, atomic latch before any side effect, not reset by failure.
- `model_posts`: integer 0..2, actual transport dispatch counter, not merely successful agent responses.
- `tool_call_id`: <=128 UTF-16 units, unique within run; no raw value logged/displayed.
- `query`: ephemeral normalized accepted argument; <=256 UTF-16 units and <=12 tokens; bounded generic vocabulary plus eligible current/prior user terms; at least one topic term. No URLs, credentials, code, arbitrary headers/filters/provider overrides or invisible control characters. Rejected query is not rewritten-and-sent.
- `request_started_at`, monotonic tool deadline, cancellation token, HTTP/body/output counters; safety budgets never reset between steps.
- `search_outcome`: `pending`, `not_requested`, `disabled`, `privacy_skipped`, `retrieved`, `partial`, `snippets_only`, `empty`, `blocked`, `rate_limited`, `timeout`, `unavailable`, `context_limit`, `cancelled`, `error`.
- `phase`: `idle`, `searching`, `fetching`, `finished`; finite monotonic transitions per call.
- `evidence_state`: `none`, `retrieved_only`, `sent_to_model`. A safe manifest can exist without a successful model continuation. Only a tool-result-bearing model request accepted with HTTP200 advances to sent_to_model; it does not certify answer truth.
- `step`: 1 or2; step2 only after the first accepted tool result; all request_count/tool_count/sentinel bookkeeping is per run/response, not globally reused.

Terminal run states remain existing `complete`, `interrupted`, `error`. Tool search outcome and answer status are separate: retrieved evidence can coexist with an interrupted answer. No model decision chain-of-thought is persisted.

### 2.1 Shared status/reason domain

This is the exhaustive schema1 mapping, not an example list. `reason` is the indicated fixed string, or JSON null **only** for `pending`; no SDK error, arbitrary diagnostic string or additional reason is allowed. User-facing explanations are local static labels keyed by this mapping.

| outcome | reason | Meaning |
| --- | --- | --- |
| `pending` | null | No final retrieval outcome yet; never render as successful/no-tool |
| `not_requested` | `no_tool_call` | Initial model response completed without invoking search |
| `disabled` | `operator_disabled` | Administrative off setting |
| `privacy_skipped` | `privacy_policy` | Missing/ineligible provenance or rejected query |
| `retrieved` | `page_evidence` | Nonempty retained evidence, all page-backed |
| `partial` | `partial_evidence` | At least one page-backed source with other snippets/skipped pages |
| `snippets_only` | `snippet_evidence` | Nonempty retained evidence, all SearXNG snippets |
| `empty` | `no_results` | Recognized zero organic results |
| `blocked` | `provider_blocked` | Provider challenge/access refusal |
| `rate_limited` | `rate_limit` | Local limiter or provider cooldown/429 |
| `timeout` | `tool_timeout` | Tool wall deadline expired without retained evidence |
| `unavailable` | `retrieval_unavailable` | Transport/layout/parser failure without retained evidence |
| `context_limit` | `context_budget` | No evidence fits, or tool omitted for context safety |
| `cancelled` | `run_cancelled` | Run stopped/crashed before a final retrieval outcome |
| `error` | `tool_error` | Terminal agent/tool/protocol failure before a final retrieval outcome |

Initial state is `phase=idle, outcome=pending, reason=null, tool_attempted=false`. Allowed phase transitions are idle→searching→fetching→finished, idle→finished and searching→finished; there is no transition out of finished. Searching/fetching have outcome pending and tool_attempted=true. Non-finished phases have only pending/null; finished has any listed outcome except pending. Same-phase duplicate updates are rejected unless another allowed field changes; event caps still apply.

`tool_attempted` changes false→true only when a valid single tool invocation consumes the latch, before query/network checks; it never reverts. Disabled/not_requested require false; retrieved/partial/snippets_only/empty/blocked/rate_limited/timeout/unavailable require true. Privacy/context gates may finish with false before invocation or true inside the tool. Cancelled/error preserve the latch's actual value. Invalid/multiple/unknown calls rejected before invocation do not set it or authorize continuation.

Once retrieval finishes, later model errors/cancellation change **answer** status only; do not overwrite a completed retrieval outcome or invent a second retrieval. At startup, recover every non-finished provenance row on an interrupted message (including idle/pending) as finished/cancelled/run_cancelled, preserving the latch. Completed retrieval rows and evidence delivery state are retained. This state machine applies equally to Node/Python validation, storage recovery and UI fixtures.

## 3. Source / evidence bundle (Python ephemeral)

| Field | Constraint |
| --- | --- |
| id | `S1`..`S5`, contiguous and unique in one manifest, scoped to assistant message |
| url | validated canonical public http/https URL, <=2,048 UTF-16 units; no credentials/fragment; controls rejected |
| title | plain text <=300 UTF-16 units; no HTML rendered |
| kind | `page` or `snippet`; snippet-only must not imply page read |
| retrieved_at | integer UTC epoch milliseconds in 0..9,007,199,254,740,991; actual retrieval time, never null or fabricated publication time |
| excerpt | <=3,000 UTF-16 units, immutable once provided to model; strip markup/unwanted sections, mark truncation |
| excerpt_sha256 | lowercase 64-hex SHA-256 of exact UTF-8 excerpt passed to model |
| excerpt_units | nonnegative integer <=3,000 |
| truncated | strict boolean |

Maximum five sources. The ephemeral tool-result object has exactly `{v, outcome, reason, retrieved_at, sources}`: v is integer1; outcome/reason use §2.1; sources includes excerpts. Only invoked-tool outcomes retrieved/partial/snippets_only/empty/blocked/rate_limited/timeout/unavailable/privacy_skipped/context_limit may be returned; pending/disabled/not_requested/cancelled/error are not tool results. Cancellation/terminal errors abort, never authorize continuation. Fixed untrusted-data framing is included in the bounds: combined serialization <=64 KiB UTF-8 and formatted enrichment <=16,000 UTF-16 units.

The root `retrieved_at` is required but nullable: null **if and only if** sources is empty; otherwise the maximum of the actual source timestamps. It records evidence acquisition, not attempt/completion/publication time. Evidence outcomes retrieved/partial/snippets_only require 1..5 sources; all other outcomes require sources=[] and retrieved_at=null. A page-level failure may yield partial/snippets_only within the deadline; the global timeout discards unfinished evidence and yields timeout with no sources.

Finalize context fitting **inside the tool before returning or emitting the first source manifest**. Reduce/discard only retrieval content, never user history/attachments; assign contiguous IDs/hash/lengths after this reduction. The before-model hook rechecks the finalized result and aborts on any later mismatch/overflow rather than mutating an already emitted manifest. Only sources actually included in this immutable tool result may later be marked sent_to_model. No preliminary per-page source lists are emitted.

Query/page HTML, selected source extracts and native tool-call/return messages live only for the run. No cross-chat result cache, automatic historical tool replay or vector index. Source titles remain untrusted data, never seeds for a follow-up query. Eligible prior **user** terms may inform the argument guard; assistant/page/attachment-only tokens may not.

## 4. StoredWebRetrieval (Express SQLite)

New additive `web_retrieval` table; do not alter existing chats/messages/attachments column order.

| Column | Constraint |
| --- | --- |
| message_id | TEXT PRIMARY KEY, FK messages(id) ON DELETE CASCADE; assistant message only, validated by store |
| schema_version | INTEGER NOT NULL, fixed1 for this feature |
| phase | TEXT NOT NULL, validated phase enum |
| outcome | TEXT NOT NULL, validated outcome enum |
| evidence_state | TEXT NOT NULL, validated enum |
| updated_at | INTEGER NOT NULL, server UTC epoch milliseconds in 0..9,007,199,254,740,991 |
| manifest_json | TEXT NOT NULL, validated safe JSON <=64 KiB UTF-8 |

`manifest_json` has exactly `{v, phase, outcome, reason, tool_attempted, evidence_state, retrieved_at, sources}`. All fields are required; v is integer1, phase/outcome/reason follow §2.1, tool_attempted is a strict boolean, and evidence_state is exactly none/retrieved_only/sent_to_model. Sources contains only the §3 Source fields **excluding excerpt** (all remaining source fields required). Reject extra keys and type coercion at every object level. Root timestamp nullability and source/outcome rules are exactly those in §3. Column phase/outcome/evidence_state/schema_version must agree with the manifest; they are not independent conflicting authorities.

`evidence_state=none` if and only if sources=[], regardless of whether an empty failure result was delivered. Nonempty manifests begin retrieved_only and may advance once to sent_to_model upon HTTP200 for the exact result-bearing continuation. Across that advance only evidence_state changes; source IDs/URLs/kinds/timestamps/hashes/lengths and retrieval outcome remain identical. These same object fields are used in source events and authenticated detail responses; do not introduce parallel names such as `schema` or `hash` for v/excerpt_sha256.

Never store query, arguments, raw provider errors, full pages, source excerpts, tool transcript or reasoning. Source URL/title are private conversation metadata, not telemetry; include them only in authenticated responses. Parse/version/length/schema checks in both runtimes and on DB read; malformed legacy rows produce an unavailable-source notice rather than raw content rendering.

Insert the §2.1 initial state with the assistant placeholder in the same existing transaction: v=1, evidence_state=none, retrieved_at=null, sources=[]. Apply status/reset/provenance updates atomically with associated message state where necessary; final done persists final provenance before announcing completion. Recover non-finished rows as specified in §2.1 and mark partial answers interrupted as today. Never infer completed search from an interrupted row. For a nonempty finished outcome, validate and persist the final status plus the immediately following first source manifest atomically; never expose an intermediate finished/retrieved row with empty sources. A crash before that commit leaves the prior pending state for recovery.

Delete conversation → message FK deletion → provenance/attachments cascade. Old compatible app opens the DB, ignores the new table and still has foreign_keys enabled; test its deletion cascade with feature rows. Upgrade→old→new preserves records and ignores unrecognized additive metadata safely. If this is not demonstrated, do not claim compatible automatic image-only rollback.

## 5. Model context and stream ownership

Canonical user/assistant history remains authoritative in Express. Tool results stay inside one Python Agent run and are **not** serialized as additional conversation roles for future turns. Current-turn intermediate model text/arguments/results are counted before continuation. Thinking is stripped before continuation and never persisted/replayed. The raw transport validates exact model ID, dispatch budget and per-response `[DONE]`.

A validated search call may require `answer_reset`: clear preliminary current answer in UI/DB, retain no hidden old answer copy, do not reset run output-unit counters. Subsequent answer text is final-step incremental output. If stopped before reset, the displayed first-step partial is interrupted; if stopped after reset, retain only new current-step output. Saved source availability never proves a complete answer.
