# Specification closeout

Reconciled 2026-10-25 at the user's request to close all current specs. This is an administrative status index, not a new feature or permission to restore retired infrastructure.

| Spec | Final disposition | Evidence |
| --- | --- | --- |
| 001 — Open WebUI | Retired/archived; deliberately not restored or falsely marked implemented | [ADR 0001](../docs/adr/0001-replace-open-webui-with-custom-frontend.md) |
| 002 — Custom frontend | Complete; current visual design accepted by the user's closeout instruction after visual approval was explicitly identified | [Tasks](002-custom-frontend/tasks.md), [validation](002-custom-frontend/validation.md) |
| 003 — Live model catalog | Complete and deployed; original tasks already checked | [Tasks](003-live-model-catalog/tasks.md), [validation](003-live-model-catalog/validation.md) |
| 004 — Pydantic AI harness | Complete, merged/deployed; explicitly authorized real Gemma inference passed | [Tasks](004-pydantic-agent-harness/tasks.md), [validation](004-pydantic-agent-harness/validation.md), [PR #1](https://github.com/mcteer/fios/pull/1) |
| 005 — Host/model readiness | Complete, merged/deployed; native supporting-service topology rejected and superseded by 006 | [Tasks](005-model-host-readiness/tasks.md), [validation](005-model-host-readiness/validation.md), [PR #2](https://github.com/mcteer/fios/pull/2) |
| 006 — Containerized supporting services | Complete, merged/deployed; three healthy services in the OrbStack Fios stack, no native supporting jobs | [Tasks](006-container-support-services/tasks.md), [validation](006-container-support-services/validation.md), [PR #3](https://github.com/mcteer/fios/pull/3) |

Spec 007 was opened after that closeout: [live web search](007-live-web-search/spec.md) was merged/deployed through [PR#8](https://github.com/mcteer/fios/pull/8), but is **not fully live-model accepted/closed**. The user's subsequent SearXNG fix remains within007. Its [validation record](007-live-web-search/validation.md) distinguishes historical blocked DDG acceptance from successful partial SearXNG provider retrieval, separately opt-in/unrun real-model competence and exact-commit release evidence.

## Evidence boundaries

Baseline production release `84418cdf2ec9d08e44e3bf0f6f59872734be5983` passed 47 Node, 29 Python and 8 browser tests, independent PR/main CI, hardened ARM64 upgrade/rollback/backup restore, authenticated discovery and production browser/installed-Python checks. Real local `mlx-community/gemma-4-e4b-it-4bit` inference returned the expected `Fios connected` from a text attachment, streamed to completion and cleaned up the temporary conversation. No Studio-model inference, real vision understanding, native compute-cancellation guarantee, RDMA performance or cluster failover is asserted. Those are scope limits, not secretly completed tests.

Historical intermediate checkpoints remain dated/historical; their old pending statements do not override final closeout records. Open WebUI's archived unchecked tasks remain historical rather than being fabricated as done. MLX-Serve/RDMA remain native; all supporting services stay containerized. Routine docs-closeout merges still follow exact-head CI and automatic checked-main application delivery; resulting administrative PR/run/deployment outcomes are recorded in their PRs without a self-referential source-update loop.
