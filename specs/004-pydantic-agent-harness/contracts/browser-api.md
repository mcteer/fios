# Browser/API Compatibility Contract

No frontend redesign or new public harness endpoint. Existing same-origin cookie authentication, rate limiting, upload limits, model selection, Markdown/code and copy behavior remain in force. The browser must never import `src/agent/`, see gateway credentials, or contact MLX directly.

## Generation

`POST /api/chats/:id/messages` remains multipart with `content`, exact `model`, and zero to five `files`. Existing auth, origin, existence, upload, context/capability and global-busy validation runs before dispatch. A model removed after selection is rejected on fresh catalog validation (400); a second concurrent generation remains 409. Validation failures create no conversation messages.

If the worker cannot become ready before persistence, return 503 JSON with a safe actionable error and release the generation reservation. If it fails after message creation/SSE headers, use the stream's existing error/done path; retain partial answer and message rows. No direct inference fallback.

### Existing SSE events (retained)

| Event | Payload / behavior |
| --- | --- |
| `meta` | `{user, assistant, chat}` with current metadata shapes; no raw attachment data. |
| `delta` | `{content}` answer increment. |
| `reasoning` | `{content}` transient reasoning increment; not saved as answer/history. |
| `error` | `{error, status}` safe human-readable error; status `interrupted` or `error`. |
| `done` | `{id, status}` existing assistant ID and `complete`, `interrupted`, or `error`. Exactly one terminal finalization. |

Keep SSE headers/no buffering and 15-second comment keepalives. Keepalives do not count as model progress. Persist answer increments while receiving text with at most one second between saves, plus a final save. Keep the existing 500,000 combined answer/reasoning UTF-16 code-unit safety limit.

## Stop and recovery

`POST /api/chats/:id/stop` keeps its idempotent `{ok: true}` response. The response acknowledges the stop request; completion of cancellation is observed through final stream state and `GET /api/chats/:id` returning `generating: false`. Under controlled tests this occurs within two seconds and the mock gateway observes connection closure. Late completion cannot overwrite a stop that already won. Browser disconnect and app shutdown also cancel upstream work.

On worker failure retain the user's message and saved partial assistant answer with `error`; on stop/disconnect/idle abort retain `interrupted`. App restart continues to recover stale streaming rows. Never auto-resend the prior request. User may send a new message after cleanup.

## Non-inference operations

Login/session/logout, `/api/models`, chat list/detail/create/delete and `/health` remain Node-owned and must not create an Agent run or inference request. Catalog refresh behavior from spec 003 is unchanged, including fresh server validation on send and preservation of exact peer IDs. Deleting an active chat is still blocked; subsequent deletion removes related attachments/messages. `/health` remains a liveness check, not a claim of MLX or worker readiness.

No response schema changes are required for existing history; old messages must still render and copy correctly. No persistent reasoning field or SDK transcript is added.
