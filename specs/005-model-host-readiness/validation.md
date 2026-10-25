# Validation — Model and Host Readiness

Date: 2026-10-25. Branch: `005-model-host-readiness`.

## Scope and design gates

Read constitution and upstream Spec Kit prompts, resolved active feature templates/path, specified/clarified/planned/tasks/analyzed before release. Requirements quality checklist: 16/16 passing (read-only during implementation). No extension hooks configured. Ten functional requirements plus five success criteria have task/test/release coverage; no unresolved constitutional exception. Follow-up operations work implements the user's previously requested automatic delivery policy rather than silently leaving merge-only delivery in place.

Current source checkpoint: implementation and local validation complete; hosted CI, merge and production outcomes must be recorded separately in the feature PR and completion report. Do not infer production deployment from these local results.

## Local automated checks

- `npm ci`: passed, 253 packages audited, zero vulnerabilities reported.
- uv 0.13.5 lock check and noneditable installed-package rebuild: passed, frozen 27-package environment on CPython 3.11.17.
- `npm test`: **43 Node tests + 29 Python tests passed**, no failures. Real installed Pydantic Agent against mock MLX; no live inference.
- `npm run build`: passed; no agent/host-observer code in browser assets.
- `npx playwright test`: **8 passed**, including explicit host states, blocked unavailable selection, retained draft/model and recovery.
- `npm audit`: zero vulnerabilities. Pinned pip-audit 2.10.1: no known third-party vulnerabilities; local non-PyPI `fios-agent` advisory lookup skipped explicitly.
- Static inference boundary guard, Node syntax checks and quiet Compose validation: passed. Credentials/resolved configuration were not printed.
- Native ARM64 isolated hardened container/recovery script: passed. Latest measured peak **488 MiB** under unchanged 1 GiB cap; earlier successful feature pass **527 MiB**. Covers existing maximum context/cancellation/parent-death/history upgrade/image rollback/actual backup restore plus the **new delivery function's stopped-volume backup, verified replacement and injected post-upgrade verification failure with automatic prior-image recovery**. Only unique disposable resources were used/removed.

## What new tests establish

- Shared Node/Python fixtures cover unloaded availability, direct rather than cached loaded state, absent/stale peer models, unverified host, mismatched suffix, unmarked peer ID, reserved gateway-name bypass and loss of chat capability.
- Host health failure, unauthorized response, malformed/oversized catalogs, bounded slow responses, endpoint/config validation and restoration. Gateway credentials never reach peers; payload URLs are never followed.
- Express rejects unavailable targets before any inserted message. Direct Python harness separately rejects the same target; inference request count remains zero. Successful recovery sends exactly the original peer-qualified ID, with no retry/substitution.
- Native observer snapshots are endpoint-bound and expire after five seconds. Missing files, altered fingerprints, stale/future timestamps and invalid states fail closed. Container-mode tests forbid direct peer network access. A direct harness test proves missing/expired peer evidence produces zero inference POSTs.
- Delivery checks require all six checks completed successfully; missing/pending/skipped/cancelled/failed are rejected. Unit tests cover stopped-backup ordering, immutable target image, backup/stop/verification failure rollback, rollback failure reporting and superseded-revision refusal before stopping the app.
- Existing authentication, history, images/PDF, transient reasoning, stop/crash/disconnect, no-retry and frontend/mobile regressions remain passing.

## Real local MLX interruption (no inference)

Observed twice with a feature app on a free **127.0.0.1** port, unique temporary SQLite database and generated test-only authentication. No production app/database/credentials were used by that test app.

1. Native gateway advertised exact model **`mlx-community/gemma-4-e4b-it-4bit`**, available with `loaded:false` (on demand).
2. Verified the local listening process was the installed native MLX-Serve child. Used **SIGSTOP**, not termination/reconfiguration, to interrupt service while preserving its arguments, parent and process identity. A `finally` path guaranteed **SIGCONT** restoration.
3. Feature API reported gateway unavailable and Gemma unavailable. A send returned **HTTP 503**, with **zero persisted messages**.
4. A direct real Python harness run while the service was unresponsive returned **`model_unavailable`** before inference.
5. Resumed the same native process; exact Gemma ID returned to available, still unloaded. Temporary app/database were removed.

This is a real unresponsive-process test, **not** a claimed graceful quit/relaunch or physical host shutdown. Connection refusal is covered by automated tests. No remote Studio process, RDMA, model configuration or model loading was changed. No user stop/start assistance was needed.

## Real hardened-container peer discovery

An initial read-only image probe discovered that the native Mac could reach both Studio endpoints but the container could not: direct peer requests timed out. Local Gemma remained available, while remote models correctly became unavailable. No routing, RDMA or public port was changed to bypass this boundary.

Implemented the native metadata-only observer and read-only directory bind. A one-shot observation expired while an image built and correctly yielded **unknown** peer status. Running the observer continuously then verified, from the hardened nonroot/read-only/1-GiB/2-CPU ARM64 image:

- **3 verified healthy hosts** (gateway/local and both existing Studio peers).
- **5 available chat models**, preserving exact peer-qualified IDs.
- Exact local Gemma available on demand.

No app listener, database, production volume or Docker socket was present in this image probe; only health/catalog reads occurred. Temporary observer, images and metadata directory were cleaned up. Only the explicit peer allowlist was appended to private deployment configuration; credentials were left unchanged and never printed.

## Delivery requirements still enforced after this source checkpoint

Open the dedicated PR, require all latest-head CI checks, merge only the checked head, wait for successful merged-main CI, and install reviewed stable native observer/local delivery programs from clean main. The local outbound-only agent must build/archive that exact approved revision, retain prior image/stopped-data backup, verify health/authenticated catalog/Python readiness and image revision, and publish actual outcome. No hosted CI production access or remote runner is introduced. A user login plus working local Docker/GitHub CLI is required; report any installation/rollout block rather than claiming success.

Backups remain private inside the existing application volume and must also be exported for disk-loss protection. This feature does not change SQLite schema; automatic image rollback preserves current records. Incompatible future schema upgrades require an explicit restore plan, not blind data replacement. No real inference quality, native compute cancellation, RDMA/failover behavior or universal memory bound is claimed.
