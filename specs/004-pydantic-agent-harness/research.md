# Research — Pydantic AI Agent Harness

Date: 2026-10-25. Scope: documentation/source inspection and existing Fios code review, not implemented compatibility or real inference testing. Research was performed directly in this session; no subagents were available. Hosted `ai.pydantic.dev` documentation requests returned HTTP errors, so the official repository's version-tagged Markdown and source were used instead.

## 1. Distribution and reproducibility

**Decision:** use managed CPython 3.11.17 on the existing Debian Bookworm runtime; declare `pydantic-ai-slim[openai]==2.61.0`, `openai==3.37.0`, and `httpx2==2.16.0`. Use `uv==0.13.5`, `hatchling==1.32.4` as build backend, and a committed root `uv.lock`. Use stdlib `unittest` including `IsolatedAsyncioTestCase`; audit via pinned `pip-audit==2.10.1` outside production dependencies. Declare Python `>=3.11,<3.12` and provision 3.11 locally for parity. Keep Node 24.15.0, current npm pins, and the single-container deployment.

**Rationale:** PyPI metadata confirms these releases and Python requirements; Pydantic AI 2.61.0 requires Python >=3.11 and OpenAI >=3.26.0 for its OpenAI extra. The extra supplies the compatible provider without unrelated provider SDKs. OpenAI 3.37.0 uses HTTPX2, not legacy HTTPX; use matching transport types. Base Pydantic dependencies such as graph/telemetry APIs can exist transitively without enabling their services.

**Alternatives considered:** full `pydantic-ai` adds unneeded extras; adding a web framework is unnecessary for private IPC; Python 3.12+ would add an unnecessary version change. Implementation refinement: pin uv-managed CPython 3.11.17 and copy it plus the frozen venv between build/runtime stages rather than depend on mutable apt Python patch resolution; this matches the tested macOS patch and avoids runtime downloads. Node and uv base-image digests are pinned. Resolve and audit the full lock during implementation; registry metadata alone is not proof of a working lock or vulnerability-free image. Never silently upgrade the selected libraries.

Sources: [slim install](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/install.md), [package metadata](https://pypi.org/pypi/pydantic-ai-slim/2.61.0/json), [OpenAI README](https://github.com/openai/openai-python/blob/v3.37.0/README.md), PyPI release metadata for [uv](https://pypi.org/pypi/uv/0.13.5/json), [HTTPX2](https://pypi.org/pypi/httpx2/2.16.0/json), [hatchling](https://pypi.org/pypi/hatchling/1.32.4/json), and [pip-audit](https://pypi.org/pypi/pip-audit/2.10.1/json).

## 2. Integration boundary

**Decision:** Express supervises one long-lived Python worker using versioned JSON Lines over inherited stdin/stdout. All harness implementation, including the Node bridge, lives in `src/agent/`. Express retains authentication, upload/PDF validation, model catalog, SQLite ownership, and browser SSE. No Python listener or second database connection is added.

**Rationale:** one user and one active generation are already enforced in `server/index.js`. A private pipe is not addressable by browser or network callers. This avoids a new internal HTTP authentication scheme and keeps conversations usable when the worker fails. The supervisor must explicitly handle readiness, bounded framing, cancellation, backpressure, crashes and shutdown.

**Alternatives considered:** a Python HTTP sidecar adds transport credentials and deployment surface; rewriting Express adds unrelated auth/storage risk; spawning Python per request imposes repeated import cost. A persistent private worker is the least disruptive bridge, not a new general-purpose command runner.

## 3. Explicit provider, no fallback or retries

**Decision:** construct `OpenAIChatModel` with the exact gateway ID and an explicitly supplied `OpenAIProvider`/`AsyncOpenAI` client. Always pass the configured MLX base URL; never infer provider/model from a string prefix. Set client/model retries to zero, Agent retries to zero, and `UsageLimits(request_limit=1, tool_calls_limit=0)`. Register no tools, toolsets, output tools, MCP clients or external telemetry. Text output only.

**Rationale:** OpenAI's default client retries twice independently of Agent retries. Pydantic's default `openai:` inference now selects Responses API, whereas MLX uses Chat Completions. Explicit construction avoids both pitfalls and preserves `@peer` IDs. Configure the model profile to use `max_tokens` rather than `max_completion_tokens`, and merge system instructions into one leading system message. The pinned adapter sends standard `stream_options.include_usage=true`; leave continuous usage statistics off and cover usage-only chunks in mock compatibility tests. An endpoint rejection is an explicit failure, not grounds for an automatic retry with altered options. Keep 8,192 output tokens. Use an explicit local placeholder API key only when `MLX_API_KEY` is absent; never fall through to cloud environment variables.

**Alternatives considered:** inferred provider names, default retries, structured-output tools or a fallback model would violate exact-model/no-retry/no-tool requirements. No custom raw inference path is retained.

Sources: [custom endpoints and profiles](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/models/compatible-apis.md), [OpenAI configuration/retries](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/models/openai.md), [usage limits](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/pydantic_ai_slim/pydantic_ai/usage.py).

## 4. History and multimodal translation

**Decision:** retain `buildContext` as the existing bounded, attachment-aware context builder. Translate its private request envelope to Pydantic `ModelRequest(UserPromptPart)` and `ModelResponse(TextPart)` objects in Python. Remove the final user item from history and pass it once as the current prompt. Use `BinaryContent` for decoded, validated image data; existing PDF extraction remains in Node. Carry the existing Fios instruction once via Agent instructions.

**Rationale:** the database remains the canonical conversation record. Serializing Pydantic's internal history to SQLite would introduce a migration and provider coupling not needed for this feature. Existing answer-only assistant history must not gain reasoning, retries, tools or synthetic turns. The SDK supports inline image bytes; do not use upload APIs or remote image downloads.

**Alternatives considered:** passing the current prompt both in history and as input duplicates it; raw PDFs would change validation and model compatibility; replacing history storage would broaden scope.

Sources: [message history](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/message-history.md), [image input](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/input.md), `server/lib.js`, `server/attachments.js`, `server/store.js`.

## 5. Streaming and honest completion

**Decision:** consume `Agent.run_stream_events()` to map `PartStartEvent` and `PartDeltaEvent` text to answer deltas, and thinking parts to the existing transient reasoning event. Emit each starting part's initial text once; do not append the final aggregate result a second time. Reject tool-call parts, malformed data and unexpected output modes. Completion requires a successful final Agent result AND observation of upstream `[DONE]`.

**Rationale:** current Fios treats EOF without `[DONE]` as failure. The default compatible-provider profile can accept EOF without a finish reason. Requiring a finish reason alone would break the existing mock's valid `[DONE]`-only streams and does not preserve the current sentinel check. A small HTTPX2 transport stream wrapper, consumed by the SDK, observes framing/terminal sentinel and activity without issuing requests itself or reconstructing the answer. It also bounds SSE frame buffering. Keep profile finish-reason enforcement off and enforce the stronger existing sentinel contract at the adapter boundary. The wrapper must mark the sentinel before yielding its bytes because the SDK may stop iterating at that sentinel. No new independent inference implementation.

**Alternatives considered:** `stream_text()` alone loses separate reasoning events; trusting normal SDK completion loses truncated-stream detection; adding a second Node raw inference request is prohibited.

Sources: [agent event streaming](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/agent.md), [incomplete streams](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/models/compatible-apis.md#detect-incomplete-streamed-responses), [OpenAI model source](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/pydantic_ai_slim/pydantic_ai/models/openai.py), `server/index.js`.

## 6. Cancellation, resource bounds and lifecycle

**Decision:** fresh Pydantic `CancellationToken` per run. The worker control reader remains active while inference runs. Stop/disconnect cancels that token, closes the upstream stream, and acknowledges one terminal state. Supervisor escalates an unacknowledged cancellation at one second to SIGTERM and at 1.5 seconds to SIGKILL, reaps the worker, and releases the run by the controlled two-second deadline. Restart only for a later new run; never replay the failed run. Stop received before submission must prevent dispatch.

Keep a 180-second no-upstream-data watchdog (not refreshed by synthetic heartbeats), 10-second connect timeout, 30-second write timeout, 500,000 combined answer/reasoning UTF-16 code units, one active run, 32 MiB request frames, 1 MiB event frames, and 4 MiB upstream SSE frames. Use chunked output frames and drain-aware writes; no unbounded queues. A 10-second startup handshake failure makes inference unavailable without taking down non-inference APIs.

**Rationale:** async cancellation alone cannot handle a wedged process. A process boundary permits bounded cleanup without altering MLX services. Existing startup recovery remains Node's responsibility. These limits fit the present 20 MiB image context after base64 encoding plus 400,000 text code units; test worst-case Unicode and image envelopes under the existing 1 GiB container cap.

**Alternatives considered:** passive connection closure without cancelling the Agent can leak work; automatic process/run replay risks duplicate inference; timeouts that reset on app heartbeats can hide a stalled model.

Source: [cancellation tokens and streaming cancellation](https://github.com/pydantic/pydantic-ai/blob/v2.61.0/docs/agent.md#cancelling-a-running-agent). Closing the local socket is testable; actual remote model compute termination is owned by MLX and is not claimed by mock tests.

## 7. Validation and remaining implementation gates

**Decision:** use Python unit tests with model requests disabled except approved local transport mocks; Node/API/browser tests must exercise the real Python Agent against mock MLX. Update mock OpenAI chunk envelopes to include standard id/object/created/model/choice index fields; retain explicit `[DONE]`-only and missing-sentinel variants. Capture request counts to prove one attempt, exact IDs, input parity and no bypass. Add fake-process tests for supervision only, not as substitutes for real-harness integration.

At research time no code/lock/runtime compatibility was claimed. Implementation has since resolved the 27-package lock and exercised the pinned provider/observer on macOS and ARM64 Linux; observed evidence is in validation.md. The provider wraps SDK HTTP/connection/timeout exceptions in Pydantic model-error types, which the harness handles without exposing bodies. Pydantic AI's default startup banner is explicitly disabled to keep protocol/diagnostics clean. Buffered MockTransport responses need direct observer inspection, while production responses remain streamed. Required gates remain frozen install/audit, actual Agent integration, bounded cancellation/memory, full regressions and reviewed PR. If a selected API fails these checks, update this plan/ADR explicitly; never weaken requirements or add a bypass.
