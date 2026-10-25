# Agent IPC Contract v1

Private implementation boundary; not a network or browser API. Node spawns the fixed installed Python module with `shell: false`. Only that parent receives the inherited pipes. The OS process boundary, plus existing Express authentication before dispatch, provides access control; no listener or bearer credential is introduced.

## Framing and limits

UTF-8 JSON, one object per LF-delimited line. Protocol version `v: 1` is mandatory. Schemas reject unknown fields, wrong types, unknown versions and unknown message kinds. stdout contains protocol frames only; stderr contains redacted diagnostics only. Never log request/event frames.

- Incoming worker request line: at most **32 MiB** including JSON encoding (excluding final LF).
- Outgoing worker event line: at most **1 MiB**. Split answer/reasoning into chunks of at most **32 Ki UTF-16 code units**, preserving Unicode characters, before encoding; enforce the byte limit as well.
- Raw upstream SSE frame: at most **4 MiB**, parsed across arbitrary byte boundaries and CRLF without retaining the complete stream.
- At most **one active run** and one outstanding start frame; no unbounded command/event queue. Respect pipe backpressure. Control reader must run concurrently with inference and not block on HTTP or stdout writes.
- Handshake deadline **10 seconds**; no inference before `ready`. Invalid startup config, process exit or handshake mismatch leaves Node's non-inference APIs usable.
- Bounds are enforced while accumulating frames, not only after parsing. Discarding a too-large/invalid frame by killing the worker is preferable to allocating unbounded memory.

## Parent → worker

### `run`

Required fields: `v`, `type: "run"`, `run_id` (UUID), `model` (nonempty, ≤1,024 UTF-8 bytes, exact), `context` (ordered list, nonempty, final role `user`). Each context item has only `role` and `content`:

- `role`: `user` or `assistant`.
- `content`: string, or nonempty list of `{type: "text", text: string}` and `{type: "image_url", image_url: {url: string}}` for a user message. Assistant content is a nonempty string.
- Image URL must be an inline data URL with one allowed MIME, valid base64 and matching signature. No remote URLs or nested arbitrary content.
- Context bounds/translation follow [data-model.md](../data-model.md). System instructions, gateway URL, credentials, arbitrary settings and command names are not accepted in this envelope.

Start is not queued behind an active run. An additional run receives terminal `error` with `busy` for that new ID and does not affect the original. Node must normally prevent this via its global generation reservation.

### `cancel`

Required fields: `v`, `type: "cancel"`, `run_id`. Idempotent. Cancels the matching token; never cancels another run. A stale/unknown ID is ignored. A parent-aborted request is not dispatched; after a `run` frame the worker allocates its cancellation token before processing subsequent control frames so an immediate cancel cannot be lost.

### `shutdown`

Fields: `v`, `type: "shutdown"`. Stop accepting runs, cancel active work, close SDK client/streams, exit. stdin EOF has the same meaning. Parent imposes its bounded kill/reap deadline.

## Worker → parent

| Type | Fields besides `v`/`type` | Semantics |
| --- | --- | --- |
| `ready` | none | Imports/config validated, control reader ready. No model request made. Once per worker. |
| `started` | `run_id` | Valid run accepted; no guarantee upstream has responded. |
| `activity` | `run_id` | Actual upstream bytes received; throttled to at most once per second. Not a synthetic keepalive. |
| `delta` | `run_id`, `content` string | Append new answer text only. |
| `reasoning` | `run_id`, `content` string | Append transient thinking text, never persist. |
| `done` | `run_id`, `status: "complete"` | Final Agent result AND upstream `[DONE]` observed. No aggregate text appended. |
| `done` | `run_id`, `status: "interrupted"` | Cancellation cleanup finished. |
| `error` | `run_id`, `code`, optional `upstream_status` integer 400–599 | Terminal failure; content-free safe code, no raw exception/body/trace. |

Error codes: `busy`, `invalid_request`, `upstream_unavailable`, `upstream_http`, `upstream_timeout`, `incomplete_stream`, `invalid_stream`, `unsupported_output`, `output_limit`, `internal_error`. Node-local failures use `agent_unavailable` or `agent_protocol_error` and are translated without requiring a worker frame. Unknown codes are protocol errors. A validated run emits at most one terminal frame. Invalid/unparseable envelopes without a valid UUID terminate the worker, and the supervisor terminalizes any active run.

## Completion, cancellation and recovery

- For text/think `PartStartEvent`, emit its initial content once; subsequent `PartDeltaEvent` emits only its increment. Never emit the final result string again.
- Tool-call or other unsupported parts immediately fail the run; no tools are registered, retries are zero and request limit is one. No raw direct-model fallback exists.
- HTTPX2 stream observation must flag `[DONE]` before forwarding its bytes to the SDK. Normal SDK completion alone is insufficient. `[DONE]` without a successful final Agent result is also insufficient.
- Missing sentinel, malformed JSON/SSE, provider error, output limit and EOF before terminal frame cause an explicit error, retaining Node's received answer text.
- Parent uses an idle watchdog of **180 seconds** from dispatch or last genuine activity; browser heartbeats do not extend it. SDK connect timeout **10 seconds**, write timeout **30 seconds**, read timeout **180 seconds**; retries zero.
- Stop/disconnect/idle expiry requests cancellation. At **1 second** without terminal acknowledgement, parent sends SIGTERM; at **1.5 seconds**, SIGKILL if necessary. Reap child, terminalize once and free the slot within **2 seconds** in controlled tests. OS or remote MLX compute guarantees beyond closing/reaping the client are not claimed.
- Once Node accepts a stop, late output/completion is discarded and the persisted outcome is `interrupted`; if completion already finalized, stop is a no-op. Worker crash without prior cancellation is `error`.
- After failure, start a replacement only on a later new request (one attempt, 10-second handshake); never replay a run or loop-restart indefinitely.
- Node process shutdown uses the same cancel/kill/reap path. Parent death closes stdin so the worker cancels and exits; test both orderly shutdown and parent SIGKILL.

## Security and privacy

Worker receives only an allowlisted runtime environment plus explicitly configured MLX endpoint/key; no FIOS authentication/session secrets, ambient OpenAI keys or proxy variables. Explicit endpoint, no redirects, no remote attachment fetches or telemetry. Logs never contain frame contents or provider exception text. Errors are rendered through Node's fixed safe messages, optionally including numeric HTTP status.
