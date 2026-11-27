# Native service interfaces

## Worker to Mini

Production listens on the single approved private management IPv4 address on port 8742. Reject wildcard, public, RDMA and unconfigured destinations at startup. Synthetic tests bind loopback on an allocated port. Each request uses a fresh TLS handshake, one request per connection, no session tickets, redirects, proxies or fallback. The worker checks the configured core SAN and dedicated root. The core requires a verified client leaf and maps its DER fingerprint to the active slot. Host and role headers cannot confer identity.

| Request | Success | Mutation |
| --- | --- | --- |
| `POST /v1/sessions` with `{"version":1,"node":"studio-a"}` | 201 with `{"version":1,"session":"<32 lowercase hex>"}` | Replace the active session for the calling slot. |
| `POST /v1/heartbeats` with the eight Heartbeat fields in the [data model](../data-model.md) | 204 with an empty body | Advance the authenticated slot's sequence and publish its accepted observation together. |

Accept only UTF-8 JSON objects, an exact field set, a single valid Content-Length, a 4 KiB maximum body and at most 8 KiB of headers. Deny duplicate keys, nonfinite values, ambiguous lengths, transfer encoding, query strings and unsupported versions. Allow at most eight concurrent connections and three per source address, a three-second absolute handshake/request deadline and bounded backlog (eight). Close on denial. Each slot can open four sessions and submit twelve reports per ten seconds. Report overload separately from stale data.

| Failure | Outcome |
| --- | --- |
| TLS validation fails | Close before processing a body. Worker sends no report to an unauthenticated core. |
| Unapproved, retired or wrong-slot leaf | 403. |
| Unknown or retired session, repeated/regressing sequence | 409 with fixed reason `session` or `sequence`. |
| Invalid schema or timestamp / oversized body / rate limit | 400 / 413 / 429. |
| Unknown route / unsupported method / temporarily unavailable | 404 / 405 / 503. |

No rejection updates the last good sample or sequence. On missing session the worker opens a new one. On ambiguous delivery discard the old sample and collect a fresh one with a higher sequence. On transient failure back off from one to at most five seconds including jitter, with one request in flight and no offline queue. An authentication failure closes the connection, logs a bounded reason and only retries the configured endpoint with full verification. Sample immediately when service returns. Target first accepted report within ten seconds once supervision, trust and connectivity are healthy.

## Local operator

A native CLI talks to an owner-only Unix socket under an operator-owned mode-0700 directory on the Mini. The enrollment service runs as the trusted local operator in this bootstrap. Check the socket caller's OS identity against the configured operator before every privileged dispatch. Later user identities must map to the same server-side admin check. No Internet or worker route can call it. Proposed CLI entry point is `python -m backend.enroll` using `--socket PATH`.

Initialize the enrollment ledger locally, before starting the service, with `python -m backend.enroll init --state-dir PATH`. Run it as the configured local operator. Require a new directory under a trusted parent and create it with mode 0700. Refuse an existing path, including an empty directory or symlink. Normal startup opens the configured ledger in read/write mode without creating it and fails closed if it is missing, corrupt or incompatible. Recover an existing deployment with the verified ledger or explicitly provision a new directory and reapprove fresh credentials.

| Command | Required inputs and semantics |
| --- | --- |
| `status` | Display slot, public binding state and fixed diagnostic counters. |
| `approve` | Slot, verified machine label and new public leaf file. Require absence or the expected revoked binding. Check the signed profile, SAN machine label and current validity before pinning. |
| `rotate` | Slot, expected current fingerprint, approved machine label and new public leaf for the same machine. Commit replacement and retirement together. |
| `revoke` | Slot and expected current fingerprint. Persist withdrawal and invalidate the slot before acknowledging. |

An operator-controlled trust bundle on each endpoint supplies the CA set. Root rotation uses staged file replacement and supervised restarts as described in the [quickstart](../quickstart.md). The worker reader and admin CLI accept no arbitrary commands. Keep certificate material and paths out of audit output.

## Dashboard

Use a fixed read-only `GET /v1/studios` on native IPv4 loopback port 8743. Require the same local peer, Host and Origin checks as the preview, adjusted for this port. Return exactly the two configured Studio entries, including enrollment state, observation state and at most the last good sample. Return no credentials, session IDs, diagnostic input or management methods. Apply a one-second dashboard read deadline and an 8 KiB response cap. A bad, missing or partial snapshot marks Studio telemetry unavailable. Never read legacy Studio JSON files. Use the live snapshot on each UI read, with no intermediary caching.

Preserve the public local `GET /api/v1/cluster` envelope, host IDs, existing observation shape and existing `state` values. For Studio entries add `enrollment` with `not_enrolled`, `active`, `revoked` or `unknown`. Use `state=awaiting` for never-enrolled, revoked and awaiting-first-report. Use `invalid` with `unknown` for unavailable, `reporting` and `stale` as defined in the model. Render the distinct labels in the [state table](../data-model.md), along with the reporting count. Preserve the Mini's original path, loopback/role checks, GET-only routes and health semantics. Hosting an enrollment record grants no allocatable resources.
