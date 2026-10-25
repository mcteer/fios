# Implementation Plan: Model and Host Readiness

**Branch**: `005-model-host-readiness` | **Date**: 2026-10-25 | **Spec**: [spec.md](spec.md)

## Summary

Probe configured gateway and explicitly allowlisted peers using bounded health + own-catalog reads. Express annotates discovery and rejects bad targets before persistence; the Python harness independently repeats the availability preflight immediately before inference. Native clients probe directly. The hardened production container verifies fresh, endpoint-bound observations from a native read-only observer because live testing proved it cannot reach the Studio addresses directly. Both implementations follow shared state contracts and parity fixtures. Keep discovery independent of worker availability and do not add inference to health checks.

## Technical Context

JavaScript Node 22/24, React/Vite, CPython 3.11.17 and frozen httpx2/Pydantic AI slim. No new dependencies or SQLite migration. Node tests, Python tests, Playwright and existing native ARM64 CI/recovery gate. Deployment remains existing hardened localhost Compose on macOS with native MLX unchanged.

## Constitution Check

Pre- and post-design: PASS. Spec precedes implementation; exact model IDs and local-first UX preserved; probes are read-only and inference-free; peer URLs explicitly configured and credentials isolated; data backup and rollback mandatory; local interruption is explicitly authorized, remote changes are not. No Docker socket in the application, new listener, public port, tools or RDMA changes.

## Research and Clarification

Live non-inference discovery confirms `mlx-community/gemma-4-e4b-it-4bit` exists locally with state `unloaded`. `/health` responds 200. `/v1/models` includes `lan_peers` with URLs, but upstream LAN code retains peers across transient discovery failures, so the gateway listing alone cannot establish host readiness. Both existing Studio hosts independently return health and their own model catalogs. Use `MLX_PEER_URLS` as an explicit name-to-v1-base map; do not trust URLs in payloads and do not forward the gateway API key to peers. Unknown/missing credentials fail closed. See [research.md](research.md).

## Project Structure

- `src/agent/availability.js`: bounded Node discovery/annotation; no inference.
- `src/agent/fios_agent/availability.py`: matching preflight used directly by harness.
- `server/index.js`: catalog and pre-persistence gate.
- `src/useModelCatalog.js`, `src/main.jsx`: visible host/model states, no silent substitution.
- `tests/availability*.test.js`, `tests/agent/test_availability.py`, mock fixtures/browser tests: parity, security, lifecycle and recovery.
- `scripts/observe-hosts.mjs`: native fixed-endpoint read-only observer; atomic metadata file, no listener or inference.
- `scripts/deploy.mjs`, `scripts/install-deployment.mjs`: outbound-only checked-main polling and explicit installation of reviewed stable launchd programs; isolated backup/rollback rehearsal before production.
- `specs/005-model-host-readiness/`: spec, plan, research, model, contracts, tasks and observed evidence.

## Design

Read `/health` and `/models` on each configured v1 base, with root health derived by removing the terminal `/v1`. Bound each request to 2 seconds, catalogs to 1 MiB and configuration to 16 peers. Run host probes concurrently. Health must return `{status:"ok"}`; model payload must contain a valid `data` array. No redirects, environment proxy inheritance in Python, arbitrary probe URLs or discovery retries.

A local model is available only if gateway health and catalog are valid. A peer model additionally requires an explicitly configured matching peer, valid direct peer health/catalog, and the same bare ID in that peer's local entries. Retain exact gateway IDs, distinguish loaded from availability, reject inconsistent suffix/peer identity. Missing, unauthorized or malformed verification is unknown/unavailable with fixed safe reasons. Backend retains prior observed rows only as unavailable on outage/removal, never as cached-ready. Host statuses remain visible even if no models are returned.

Production peer transport refinement (observed during implementation): host-native peers are reachable, but direct container probes time out. Do not alter routing, RDMA or expose a host port. The native observer probes configured endpoints and atomically writes a metadata-only file. Compose binds only that directory read-only. Node/Python independently validate each peer observation's endpoint SHA-256 fingerprint, schema and age (at most 5 seconds, future clock tolerance 1 second). Missing, mismatched, malformed or expired files are unknown and blocked; there is no stale-ready or network fallback. Observer cycles wait 500 ms after bounded probes. No credentials or URLs enter snapshots. Direct native/development clients without a configured snapshot still probe the explicitly configured endpoints directly.

Python independently obtains and validates its observation before its one possible inference POST, returns fixed `model_unavailable` on rejection, and honors cancellation before proceeding. HTTP mock transports cover discovery separately from inference so request-limit assertions continue to count only inference POSTs.

## Validation and Delivery

Tests precede implementation. Cover common fixtures in both languages, stale peer success at gateway + direct failure, absent models, blocked/redirect endpoints, size/time bounds, zero inference/persistence on rejection, real harness preflight rejection, recovery and browser controls. Run all existing gates and hosted CI. Then observe Gemma on an isolated feature app, stop local MLX safely, verify unavailable/no send, restore and observe recovery. Preserve the local service's original launch configuration. Do not use production SQLite from test instances.

Before production: green checked PR head, merged-main CI, immutable image build, stopped-data backup and old image preservation. Deploy existing Compose with explicit peer config, verify health and authenticated discovery, roll back a failed application upgrade. Install an outbound-only local launchd poller from the checked merged revision, alongside the native observer. Require successful main-push CI and every exact-head check before archiving/building an immutable release. Use native macOS `lockf -k -s -t 0` to serialize installer/deployer execution with kernel-released advisory locks; preserve prior image and stopped-volume backup before replacement. Update only the private image/bind-path settings, preserving credentials. Keep routine deployment off GitHub runners and away from developer worktree changes. Any missing mechanism or permission must be reported, not silently treated as done. No real inference is needed for readiness acceptance.

## Complexity Tracking

No constitutional exceptions. Node/Python discovery duplication is deliberate: Express discovery must work when the agent worker is unavailable, while Python must independently protect direct harness calls. Shared fixtures and parity tests guard drift.
