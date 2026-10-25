# ADR 0002: Route Fios inference through a private Pydantic AI worker

Status: Proposed — user selected Pydantic AI slim and `src/agent/`; integration design awaits feature PR review. Implemented and mock/browser/isolated-container tested on the feature branch; not deployed to production.

Date: 2026-10-25

## Context

[Spec 004](../../specs/004-pydantic-agent-harness/spec.md) requires Pydantic AI's slim distribution as the mandatory harness for all interface-originated model inference. Fios currently serves a React frontend through Express, owns persistent conversations in Node/SQLite, and calls the native MLX-Serve gateway directly. Pydantic AI is a Python library, so adoption requires a runtime boundary without weakening local-first security or breaking existing chat behavior.

## Decision

Install `pydantic-ai-slim[openai]` and supervise one long-lived Python worker from Express over private inherited stdin/stdout pipes. Keep all agent code, including its Node bridge, under `src/agent/`. Use a versioned, bounded JSON Lines protocol for runs, streamed events, cancellation and readiness.

The Python worker constructs the Pydantic Agent and explicit OpenAI Chat Completions provider for the configured MLX gateway. Exact model IDs are preserved; SDK and Agent retries are disabled, requests per run are limited to one, and no tools, cloud fallback or direct inference bypass are allowed. A small transport observer preserves incomplete-stream detection while Pydantic remains the sole inference path.

Express retains authentication, model discovery, attachment parsing, the current browser SSE contract, and exclusive SQLite ownership. No new network listener, inference host, database migration or remote execution facility is introduced. Existing non-inference operations do not become Agent runs.

## Alternatives considered

- **Python HTTP sidecar:** viable but adds a network/service authentication boundary and more deployment configuration for the existing single-user, single-run workload.
- **Rewrite the backend in Python:** avoids cross-language IPC but expands scope to replacing working authentication, attachment and storage behavior.
- **Spawn Python per request:** simpler lifecycle but repeated library import/startup overhead and weaker central readiness handling.
- **Retain direct-call fallback:** rejected because it violates the mandatory harness requirement and can duplicate inference.

## Consequences

- Ship and maintain a Python runtime, frozen dependency lock and protocol/supervision tests alongside Node.
- Explicitly handle startup readiness, bounded buffers, cancellation escalation/reaping, crash recovery and safe diagnostics. Never replay an interrupted run automatically.
- Existing user data and frontend experience remain the baseline. Agent internal messages are transient translations of stored history, not a second canonical transcript.
- No RDMA, native inference, LAN/public exposure, Docker-socket or arbitrary execution changes are authorized.
- The feature branch and reviewed PR demonstrate mock-backed real-harness integration, history/image parity, no retry/bypass, stop behavior, hardened deployment and rollback safety. Documentation research is not runtime validation.

## References

- [Plan](../../specs/004-pydantic-agent-harness/plan.md)
- [Research and pinned upstream references](../../specs/004-pydantic-agent-harness/research.md)
- [IPC contract](../../specs/004-pydantic-agent-harness/contracts/agent-ipc.md)
- [Constitution](../../.specify/memory/constitution.md)
