# Operator and worker interfaces

These proposed additions are enabled only for a configured scheduling service. The first executor profile is a deterministic fake on fios-core. Keep the existing dashboard GET-only and keep the Spec 2 enrollment interface usable with scheduling disabled.

## Local operator contract

Extend the native CLI and owner-only Unix socket dispatcher. Resolve the OS peer to the local admin at every call. Never accept caller-supplied identity, memory demand, price or worker destination. Validate exact fields and bounded JSON messages using the existing transport limits.

| Operation | Input | Result |
| --- | --- | --- |
| job-context | none | Return the current ledger incarnation to the authorized caller. |
| job-submit | expected ledger incarnation, request key, versioned profile, bounded token limit and relative deadline | Created or original job and current state. Compare normalized relative deadline on retry, retaining the original absolute expiry. Check incarnation inside the submission transaction before lookup, insertion or queue checks. Reject a missing incarnation as invalid and a mismatch as `ledger_changed`, even for a surviving key. Check duplicates before queue limits. |
| job-get / job-events | job ID, optional event cursor | Owner-authorized state, reason, held slots, attempt, labeled usage by direction, measured totals and cost completeness, and up to 50 ordered events. Unknown and inaccessible IDs return the same response. |
| job-list | optional cursor | Up to eight authorized jobs in creation order, with queue and cleanup reasons. Use the final row's position as the next cursor. |
| job-cancel | job ID | Recorded state after idempotent cancellation. No machine caller can invoke this operation. |

Obtain the incarnation before first submission and retain it with the key and intent across lost responses and client restarts. The CLI must accept this original envelope on retry. On `ledger_changed`, stop and surface the conflict. Only an explicit new submission may fetch a new context and create a fresh key.

Empty lists succeed. Return stable reasons for invalid profile/limits, conflict, forbidden access, queue full, insufficient capacity and ledger unavailable. At queue saturation suggest retry after five seconds. Exclude secrets, paths and user content.

## Private worker contract

Add bounded POST operations under `/v1/jobs/` on the native mutual TLS listener. In T006 activate dispatch only in explicitly enabled synthetic loopback mode. Production Spec 2 workers continue heartbeating with dispatch disabled. Each request has version 1, slot and session. Verify the peer's current binding, session, operation and resources under the enrollment lock at commit time. Reuse TLS, framing, absolute deadlines and per-peer concurrency limits. Give scheduler calls a separate per-slot budget of 30 per ten seconds.

| Operation | Input in addition to identity | Response / behavior |
| --- | --- | --- |
| capacity | advancing sequence, sampled time, available bytes, resident revision or null | Accept or reject the entire observation. Never refresh capacity on a duplicate. |
| poll | none | Wait with delay, a prepared assignment, a start authorization, stop/cleanup challenge or exclusive unload request. Repeated poll returns the same active instruction until acknowledged. |
| ready / renew | job, generation, slot grant | Ready is idempotent. Renew only before expiry on a current grant. Never extend a job deadline. Workers poll for start after readiness. |
| finish | grant tuple, bounded result code and optional tagged input/output counts | Record one participant outcome. Only the designated reporter may supply job-wide counts. A matching retry returns the prior receipt while the credential and session remain valid. Conflicting or fenced submissions cannot alter settlement. |
| cleaned | slot-specific current reconciliation challenge, disposition, new capacity sequence | Accept only after the worker has stopped the old operation, dropped its local grant and supplied a fresh report sampled after the challenge. Repeat acknowledgment is harmless. |

For each supplied direction, accept exactly `{"kind":"measured","value":0}` or `{"kind":"estimated","value":0}` with any permitted nonnegative integer, or `{"kind":"unknown"}`. A missing direction means unknown. Reject bare numbers, unexpected fields, booleans, negative counts or an unknown tag with a value. Compare normalized tags as well as counts when deduplicating settlement.

A fake worker keeps a single assignment and serializes start, stop and unload. A lost response triggers a poll or an idempotent acknowledgment. The worker must stop on lease loss independently of the core. After a worker restart, authenticate again and reconcile any residual executor state before reporting clean. A replacement identity must establish exclusive control of the same host and prove it quiescent before releasing old holds. Otherwise keep the slot unavailable.

**Preview defaults.** Poll every two seconds, renew every five seconds, expire a lease at 15 seconds and unload an unclaimed warm revision after 60 seconds. Use a fake clock for deadline tests. Back off with bounded jitter up to five seconds on transient errors. An authenticated but stale worker may reconcile and cancel its own residual work. Only fresh workers may acquire or renew a lease.
