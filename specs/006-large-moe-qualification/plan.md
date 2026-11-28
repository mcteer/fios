# Implementation plan · Large MoE qualification

**Feature** `006-large-moe-qualification` · **Design date** 2026-11-27 · [Specification](spec.md)

## Summary

Introduce a private `large-moe` choice that only becomes available for a measured two-Studio profile. Reuse admission, leases, grant fencing, native rank execution and checked publication from 005. Add evidence that the larger architecture actually shards, survives failure and leaves at least 32 GiB free per Studio across the supported workload. A preference for GLM determines evaluation order. It grants no release authority.

## Technical context and project structure

Use the existing Python standard-library controller, private SQLite ledger, same-origin OrbStack UI and native macOS MLX workers. Keep one management container per host. The Mini runs synthetic workers, the catalog, UI, policy and administrative controls. Large weights, activations, cache, rank processes and cross-rank model traffic stay on the two Studios. No new database service or public network endpoint is required.

| Area | Change |
| --- | --- |
| Catalog and scheduler · `src/backend/model_catalog.py`, `pair_trial.py`, `scheduler.py`, `job_protocol.py`, `enroll.py` | Add a profile class and pair-only evidence version. Classify by reviewed artifact identity, enforce at import, scheduling, prepare and promotion, reject old worker protocols. Resolve required slots on the controller. In one transaction corroborate each result against actual completed/failed jobs and retain the per-host budget. Keep existing matched-baseline promotion for 005. |
| Native rank · `src/agent/paired_runtime.py`, `jaccl_executor.py`, `jaccl_transport.py`, `macos_memory.py` | Stage only the allowlisted probe after metadata review. Issue full-pack staging authority after both probe receipts pass and cleanup and per-host budgets are verified. Check downloaded tensors against the reviewed manifest before loading. Run an independent watchdog before load until exit in serving and trials. Record phase transitions, footprint, headroom, pressure and swap with monotonic times. Perform a terminal read before releasing either hold. Prove actual forward-pass transport on the pinned devices. |
| Evaluation · `tests/fixtures/`, `tests/macos/` and a private admin evidence path | Pre-register limits and fixtures. Let only the reporter send bounded synthetic fixture output to a private reviewer store. Obtain blind human scores and deterministic coding results bound to case and output digest. Raw text expires after review or abort. Keep only verdicts and hashes in the ledger. |
| Conversation and UI · `src/backend/conversations.py`, `native_chat.py`, `chat_dispatch.py`, `src/frontend/chat.html`, `chat.js` | Present a distinct model choice and unavailable/busy reason. Preserve an explicitly selected model through queueing and retries. Assign its bounded 900-second job deadline and profile output cap server-side. Maintain 004/005 defaults for other aliases. Publish a complete approved answer and title once. |
| Verification · `tests/`, `tests/macos/`, `Makefile`, `.github/workflows/ci.yml` | Portable negative/contract/race tests, disposable Mini browser acceptance, then gated Studio canary. Keep large downloads and live hardware outside CI. |

## Constitution check

| Principle | Design and acceptance gate |
| --- | --- |
| Observed capacity | Each Studio covers its own ceiling and floor. Missing evidence gives zero capacity. Verify asymmetric refusal and mid-attempt pressure. |
| Control-plane authority | Only admin can qualify/promote. Only authenticated ranks settle their own observations. Trial grades and content follow separate authorized paths. Test spoofed/replayed/expired messages, unauthorized roles and real checker rejection. |
| Private expansion | Keep existing private enrollment and loopback user ingress. Acquisition is operator-scoped to immutable artifacts. Inference has no download credentials, discovery or arbitrary tools. |
| Mini first | Complete portable and disposable Mini acceptance and preserve preview before any Studio change. Require the current 005 exact-runtime release result before large staging or native Studio trials. |
| Scoped cleanup | Use owned processes and tagged trial paths, remove failed downloads and temporary review data, preserve shared caches/history and other active services. Recheck preview and per-rank capacity. |

Pre-design and post-design reviews agree on these gates. The additional evidence path is needed because 005's same-candidate one-rank comparison is incompatible with the operator's pair-only rule.

## Delivery, threats and recovery

1. Establish binding between artifact, allowed placement, pinned loader and both device/build identities. Separate core-local synthetic fixtures from the hardware trust path. A candidate cannot bypass placement through a legacy alias, manual single-rank recipe or a stale config.
2. Extend the authenticated worker protocol additively. Require the large-profile capability at both ends. Check the proposed per-host ceiling plus floor before launch. The watchdog independently kills the owned process group on stale authority or capacity violation. Quarantine either host lacking cleanup proof.
3. Record each real run against a frozen evaluation suite. Use restricted read-only SQL fixtures and blinded synthetic campaign briefs. Model output is untrusted data. Keep raw text, identifiers of real users and secrets out of diagnostics. Rate-limit and size-limit offline evidence imports.
4. Rehearse disallowed placements, recovery and a private UI turn on the Mini. After the 005 gate, authorize a size-bounded two-rank probe. Record its outcome, recheck capacity and disk per Studio, and authorize the exact full pack separately. Qualify one candidate at a time. Record competing candidate dispositions.
5. After the native quality, resource and recovery gates, let the admin open a bounded rehearsal for one fixture principal and frozen cases. Use the normal UI, the actual checker and the same authoritative Studio reservation ledger. Each timed browser job supplies both native model timings and a WebKit submit-to-render observation. Join them by candidate, suite, case, repetition, job and attempt before accepting the report. Private trial output goes only to the reviewer. Rehearsal history and usage belong to disposable fixture state. Rehearsal access expires at the end of the bounded run and grants no production alias. Back up ledger and conversation state together before migrating persistent service. Restore using the existing incarnation rotation, invalidate live grants and promotions, and reconcile both workers. Withdraw or roll back through compare-and-swap after cleanup. A previous profile qualifies for rollback only if all current identities still match.

The [data model](data-model.md), [protocol](contracts/qualification.md) and [validation guide](quickstart.md) define implementation boundaries. Cluster operations T009 and live search retain their own scopes.
