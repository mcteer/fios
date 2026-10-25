# Contract: Pydantic Agent Search Tool / Private IPC

## Ownership and policy

All decisions, queries, tool execution, HTTP retrieval and evidence integration are inside `src/agent/fios_agent/`. Only `web_search` is registered, via the pinned Pydantic `Tool` API. No Node/Express search route/helper, fallback engine, generic fetch tool, model outside the harness, MCP, shell, file access or telemetry. Node merely supplies mechanically separated plain-user provenance and relays validated events/persistence.

Tool is automatic (`tool_choice=auto`, `parallel_tool_calls=False` where supported; local enforcement independent of provider flags); no human approval per invocation. Safety/off/budget prepare may omit the tool, but no keyword classifier decides search necessity. Only the selected model decides whether to call it.

## Tool declaration and call budget

- Name `web_search`; input object **only** `{query: string}`. Strict extra-field/type/length validation; <=256 UTF-16 units, <=12 tokens. Nonempty normalized text; raw streamed arguments <=8 KiB UTF-8; tool-call ID <=128 units.
- Tool definition uses `max_retries=0`, `sequential=True`, `requires_approval=False`; Agent retries0, SDK retries0, inference/search transport retries0. No ModelRetry on expected retrieval failure.
- `UsageLimits(request_limit=2, tool_calls_limit=1)` **plus** explicit one-attempt latch and actual model HTTP POST counter. Expected failure counts as an attempt even if Pydantic regards it unsuccessful. Reject a batch of >1 tool calls before executing any. Unknown name/malformed arguments/third dispatch/repeat attempt is terminal with safe fixed code, not repaired by an extra model call.
- Two valid sequences: initial exact-model answer (1 POST,0 tools); initial exact-model tool request → one tool result → final continuation on identical ID (2 POSTs,1 attempted tool). A privacy/network denial may return a safe tool result and permit that one explanatory continuation. Invalid tool schema is terminal with no retry.
- Per-tool prepare removes tools after attempt. Before-request hook checks cancelled state, exact model/readiness, context and authorization for step2. Raw transport checks again at dispatch. Every response gets its own SentinelObserver and required `[DONE]` before tool side effects or response success are accepted; provisional text/reasoning may still stream. Final run also requires successful AgentRunResultEvent.
- Unknown/tool-unsupported model behavior is an explicit error or not_requested, never an automatic request without tools or substituted model. Feature-disabled path retains the existing one-request/no-tools behavior.

## Query boundary

Model sees normal local context; proposed arguments are untrusted. The guard uses RunSearchInput only to build an eligible term set. Exclude attachment-bearing/oversized/private/code-marked/current-ineligible input, ineligible prior user input, assistant/retrieved terms and secrets. Generic vocabulary is an audited small fixed list (e.g. current/latest/official/documentation/release); a query must also contain an eligible substantive topic term. Reject out-of-vocabulary tokens, control/bidi/zero-width characters, URLs, filter/operator syntax, credentials/local paths/hostnames/code patterns. Casefold/normalization must be deterministic and shared with fixture expectations; no regex-redact-and-send fallback. This is a conservative boundary, not perfect semantic privacy detection. Guard may deny a legitimate paraphrase; expose privacy_skipped honestly.

Tool arguments are never forwarded over browser SSE, logged, stored or treated as reasoning. No query preview is necessary for automatic mode. Provider request receives only accepted minimized query; selected pages receive only public GET requests, no search history or credentials.

## Tool result

Structured bounded result `{v:1, outcome, reason, retrieved_at, sources}` using the exhaustive outcome/reason mapping and tool-result subset in [data model §2.1–3](../data-model.md), with explicit untrusted-source framing. All fields are required; root retrieved_at is null exactly when sources is empty, while each source timestamp is a non-null safe integer. No inferred timestamps for failed/no-tool searches. Successful excerpts and page/snippet quality go to the Agent as a **ToolReturnPart**, not a Node-added user prompt. Progress/provenance comes from trusted tool code, not model claims. Failures return fixed safe reasons with empty sources or explicitly partial evidence; no raw errors. Cancellation raises cancellation/terminates the run, never becomes a failure result that permits another dispatch.

Input accounting before every request covers canonical text (existing400,000 units/20MiB images), plus current-turn generated text/tool args/results and enrichment framing for continuation. Do not raise the existing canonical cap or silently truncate history. Search prepare omits enrichment capability if even its bounded overhead cannot fit; no-tool legacy turns retain existing accounting. Inside the tool, finalize context fitting and reduce/omit only retrieval content before emitting the first immutable source manifest; the continuation hook only rechecks it. If intermediate parts alone make continuation invalid, stop. Pydantic thinking parts are removed before a second request and never become stored history. Aggregate text+reasoning+argument safety accounting remains <=500,000 UTF-16 units/run; per-frame/model SSE limits remain unchanged.

## IPC version2

Upgrade both parsers/worker/client in the same app image. `ready` handshake v2, existing cancel/shutdown/started/activity/delta/reasoning/done/error behavior preserved. Reject v1/v2 mismatch; no mixed-worker fallback. Requests retain 32 MiB cap, events 1 MiB cap and text deltas32Ki units. Python/Node strict field rejection and duplicate-key/depth rules remain.

`run` adds optional `search_input` per data model; missing input disables search safely for that run. The browser cannot supply this object. Worker reads `FIOS_WEB_SEARCH=auto|off` from its allowlisted environment (default auto); never an arbitrary provider URL. Node does not decide a query or trigger retrieval.

New safe events, run-correlated:
- `search_status`: exact payload `{phase,outcome,reason,tool_attempted}`, with exhaustive mapping/state transitions from data model §2.1, no query/raw error. At most16 updates/run; pending/null is nonterminal and finished never uses pending.
- `search_sources`: exact v=1 StoredWebRetrieval manifest from data model §4, excluding excerpts; <=64 KiB. At most2 emissions for nonempty evidence (retrieved_only then sent_to_model); only evidence_state may differ between them. Empty outcomes use status events, no sources event. No model-invented URLs. Final nonempty status immediately precedes its first manifest with no answer delta between; Node validates/stores the pair atomically before relaying it. A missing pair cannot produce a completed answer.
- `answer_reset`: reason exactly `tool_requested`, once maximum, only after validated first-step tool call and before any step2 delta. Node clears its accumulator and saved preliminary answer and emits corresponding UI reset.

New fixed errors: `search_tool_protocol`, `search_budget_exceeded`, `agent_context_limit`; existing upstream/model/error codes preserved. Safe metadata events count as genuine progress for the supervisor's idle timer; no fake polling heartbeats to hide stalled model streams. Search deadline15s remains independent of model actual-data idle180s and worker TERM/KILL cleanup1s/1.5s.

## Stream/error invariants

ToolCallPart/Delta and FunctionTool events are handled explicitly, never rendered as answer/reasoning. Part boundaries can restart indices on step2; tests must not assume one response. Existing run_stream_events is retained, not run_stream's early-final behavior. Preliminary text may stream, then reset upon the validated call; total counters don't reset. If first stream is incomplete, tool must not execute. If second stream lacks `[DONE]`, first sentinel does not mask it: save current partial/error, never complete. Do not append the final aggregate Agent output after deltas.

No additional network operations start after cancellation, terminal event or unavailable-model check. Parser helper/DNS/public sockets close on cancel/EOF/parent death. Python never opens SQLite, exposes a listener or gains runtime execution from tool/page content.
