# Data Model — 004

## Ownership and persistence

No database migration. Existing `chats`, `messages` and `attachments` tables remain canonical, with Node as their only owner. Python receives a bounded request snapshot, not a database path or store handle. Test fixtures use synthetic pre-upgrade records and their own SQLite files.

## Agent run (ephemeral)

| Field | Constraint / meaning |
| --- | --- |
| `run_id` | UUID string, unique per dispatch, never reused on retry/restart. |
| `model` | Nonempty exact gateway ID, at most 1,024 UTF-8 bytes; no trimming, prefix interpretation, suffix removal or replacement. |
| `context` | Ordered nonempty list; roles `user` or `assistant`; final item is `user`. Empty assistant entries have already been filtered by the current builder. |
| state | `starting`, `running`, `cancelling`, `complete`, `interrupted`, `error`. |
| answer | Concatenated answer deltas; persisted in the existing assistant message. |
| reasoning | Concatenated transient reasoning deltas; never saved or supplied to the next run. |
| counters | Combined answer/reasoning at most 500,000 UTF-16 code units, matching JavaScript string-length behavior. |
| cancellation | Fresh per-run token; idempotent stop; finalization exactly once. |

`run_id` correlates process messages only; browser and DB continue to use existing chat/message IDs. Node keeps the mapping without sending chat IDs to Python. No automatic run resume/replay.

### Lifecycle

- Global reservation is taken before multipart parsing as today; at most one active generation, including validation/cancellation.
- Pre-dispatch validation/worker-readiness failure releases reservation without inserting messages.
- Successful validation creates user message, attachment records and one `streaming` assistant row transactionally, then dispatches.
- `starting → running → complete` only after final Agent result plus upstream terminal sentinel.
- `starting/running → cancelling → interrupted` for user stop, disconnect, shutdown or existing idle-abort behavior; persist partial answer.
- `starting/running → error` for provider/protocol/worker failures and output overflow; persist partial answer.
- Once a terminal outcome has won, later frames/stop/completion cannot mutate it. After completion, a stop request is a no-op. During stop, late deltas are discarded.
- Worker death does not lose the already persisted partial answer; Node terminalizes the current row. If Node also dies, existing startup recovery converts `streaming` rows to `interrupted`.
- Slot is released only once cancellation cleanup or worker reaping has completed. New user action may start a new worker; the old request is not replayed.

## Conversation context and attachments

Reuse `server/lib.js::buildContext` ordering and bounded validation. The IPC content shape is a string or ordered text/image parts, but is not a public OpenAI endpoint.

- User message limit: 100,000 UTF-16 code units; attachment-only message keeps the existing default prompt.
- Per upload: at most five files, 10 MiB each, 20 MiB total. Each extracted text attachment at most 100,000 UTF-16 code units.
- Aggregate context text: at most 400,000 UTF-16 code units, including document wrappers. Python rechecks using UTF-16 unit counts, not Python code-point counts.
- Aggregate decoded image context: at most 20 MiB. Each image at most 10 MiB; MIME allowlist `image/png`, `image/jpeg`, `image/webp`, `image/gif`.
- Images are inline base64 data URLs from Node's validated blobs. Worker rejects external URLs, malformed base64, unsupported MIME, mismatched signatures and decoded-size violations before model invocation.
- Text and extracted PDFs retain existing `<attached-document>` wrappers as untrusted user context. No raw PDF submission or file-upload API.
- Prior user turns become `ModelRequest` with `UserPromptPart`; prior nonempty assistant answers become `ModelResponse` with `TextPart`. Final user entry becomes the new prompt exactly once, not also a history entry.
- Use Pydantic `BinaryContent` for image parts. Neither reasoning, SDK retries, tool messages, nor synthetic turns are stored or replayed. Agent supplies the existing instruction once, not once per stored turn.

## Model target

Exact ID plus advertised capabilities are validated afresh by Node before persistence, including existing image-history checks. Python does not rediscover peers or route around the configured gateway. A target removed after validation can still return an upstream error; that does not trigger substitution or retry.

## Diagnostics

Ephemeral safe fields: run ID, lifecycle phase, duration, byte/character counts, normalized error code, optional numeric upstream status. They are not a conversation transcript. No credentials, raw provider bodies, model content, attachment names/content or full environment logs.
