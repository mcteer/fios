# Implementation plan for authenticated Studio enrollment

**Feature** · `002-studio-enrollment` · 2026-11-27 · [Specification](spec.md) · [Foundation milestone T005](../001-platform-foundation/tasks.md#following-milestones)

## Summary

Enroll two configured Studio slots under explicit local operator authority. On the Mini, a native service owns trust decisions, sessions and receipt of authenticated heartbeats. The OrbStack dashboard reads sanitized Studio inventory and continues to read the Mini's existing sample file. Workers initiate outbound connections on the private management network. Each worker can report only its own host observations.

## Technical context and structure

| Area | Planned touchpoints |
| --- | --- |
| Runtime | Existing Python 3.11+ and standard library (`ssl`, `sqlite3`, `secrets`, sockets and JSON). Use a reviewed OpenSSL 3 or 4 executable at a fixed path for offline certificate tooling and explicit public-leaf profile checks. Verify versions on the core before qualification. |
| Native backend | `src/backend/enrollment.py` owns bindings, authorization and sessions. `src/backend/heartbeat.py` owns the native listener and wire validation. `src/backend/enroll.py` provides the local CLI. `src/backend/host_agent.py` reuses the Mini sampler in remote mode via `src/backend/worker.py`. |
| Dashboard | `src/backend/core.py`, `src/backend/studio_inventory.py` and `src/frontend/dashboard.py` read and render sanitized states. Reuse the telemetry bounds and display format. Keep `src/agent/` dedicated to the AI harness. |
| Operations | `ops/launchd/` templates for the native service and worker, `Makefile` for isolated acceptance and `README.md` for operator procedures. Use a separate native state directory and owner-only socket, outside the container mount and checkout in live use. |
| Verification | Python unittest with temporary SQLite stores, real local TLS peers and controlled clocks. Extend existing Linux CI for portable cases. Reserve launchd, native telemetry and OrbStack host networking acceptance for fios-core. |
| Capacity | Two workers, five-second reports, 30-second freshness and a ten-second healthy recovery target. No model, job, lease or user-auth integration in this slice. |

The testable decisions are in [research](research.md), the [state and validation model](data-model.md), the [interface contract](contracts/interfaces.md) and the [operator validation guide](quickstart.md).

## Delivery sequence

1. Establish isolated certificate and service fixtures on the Mini. Preserve the foundation acceptance tests. Make the local operator boundary and a single authenticated slot work from CLI to dashboard.
2. Add two-worker sequencing, source age checks, per-host freshness, overload handling and deterministic examples for invalid reports. Serialize validation and acceptance with revocation. The service alone owns the DB and the live state.
3. Qualify worker and root rotation, restart and revocation persistence, native supervision, diagnostics and rollback. Keep audit events for 30 days with bounded storage (10,000 most recent changes); retain retired-pin tombstones independently. Rate-limit rejection diagnostics and export reason counts.
4. Record core evidence from the same agent build intended for the Studios. Deploy that verified revision one Studio at a time only after the operator identifies the real machines, management addresses, SANs and CA. Stop after the first Studio if the Mini loses access, observations cross slots or trust checks fail.

## Threat and recovery review

| Boundary or failure | Control | Verification |
| --- | --- | --- |
| Untrusted worker or spoofed header claims another slot | Private-IP listener, mTLS, leaf pin and authorized slot rechecked at accept time. Dedicated CA with separate server/client usages. | Wrong core SAN/root, wrong EKU, missing, expired, unapproved, revoked and cross-slot leaves fail. Observe zero heartbeat bytes sent to a false core. |
| Network client tries management or exhausts the service | Separate listeners and roles. Operator commands require OS-verified Unix peer. Limit TLS connections, request duration, body and rate before storing data. Keep the local read/admin path responsive under saturation. | Denied actors and routes, oversized/stalled clients and concurrent good peers. Verify no private data in logs or UI. |
| Reconnect, replay, concurrency or clock change | Fresh core-issued session, serialized pin/session/sequence check and commit, bounded source age, elapsed-clock deadline. | Boundary, race, restart, suspend/wake and delayed delivery cases. Verify last-good time and values are unchanged after rejection. |
| Store failure, partial rotation or stale backup | Commit durable admin decision and audit before success, discard transient state on startup. On missing/corrupt existing DB refuse to serve trusted workers. Explicit first-use initialization only. | Inject failed commit, retry with expected binding, restart and confirm revoked pins remain denied. Restore only a verified current enrollment ledger. With uncertain provenance start closed and manually reapprove new leaves. |
| Worker credential theft or anchor compromise | Native key material is readable only by the service owner. Signer remains offline. A copied active key can impersonate its assigned worker until revoked. | Retire compromised pins immediately. For anchor compromise close the listener, remove compromised trust on both sides, issue new leaves via independent provisioning and reapprove. |
| Unavailable collector or old export | Fail closed for Studio reads, keep native Mini sampler and dashboard health independent. | Broker outage and hostile or historical Studio files yield zero reporting Studios. Verify Mini read access throughout rollback. |

## Constitution check

| Principle | Before design | After design |
| --- | --- | --- |
| Observations and capacity | Require separate inventory evidence | Dashboard reports measurements only. Expired evidence contributes zero reporting workers. |
| Control-plane authority | Reserve enrollment for the local admin | Private worker operations accept sessions and heartbeats only. Native admin CLI derives role from OS identity. |
| Local-first trust boundaries | Require private transport and recovery review | Synthetic trust, rotation and rollback precede live provisioning. |
| Core-first agent qualification | Require evidence before touching either Studio | Gate A in the [quickstart](quickstart.md) covers startup, health, two peers and recovery. Gate B requires Gate A and operator approval. |
| Scoped cleanup | Isolate run-owned resources | Unique paths, job labels and image tags have an owner and teardown check on success and failure. |

Design gates pass. Runtime qualification and operator approval of the live trust bindings remain open execution gates.
