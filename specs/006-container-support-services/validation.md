# Validation — Containerized Supporting Services

2026-10-25; complete and closed, T001–T008 complete. [PR #3](https://github.com/mcteer/fios/pull/3) merged exact checked head `fdfedcdc2727e275207d7858efe3f92ab6b3ea18` after [all six PR checks](https://github.com/mcteer/fios/actions/runs/40219923110). Merge `84418cdf2ec9d08e44e3bf0f6f59872734be5983` independently passed [all six main checks](https://github.com/mcteer/fios/actions/runs/40220107435), then was deployed. Earlier local-check observations below are historical evidence, not pending release actions.

## Production closeout

- Built app/observer and management images from an immutable archive of checked main, with the exact revision label. All three services were healthy in the OrbStack Fios Compose project: `fios-fios-1`, `fios-readiness-1`, `fios-deployer`.
- Stopped-data backup `fios_fios-data/backups/before-1a17445f6d3` and prior image `fios:rollback-1a17445f6d3` retained; verified completion marker/SQLite file without opening the database. Original data volume and credentials preserved.
- Authenticated production API, actual browser and installed Python harness agreed: three healthy serving hosts and five available models, including exact local Gemma. Browser showed three Online indicators and five enabled choices; no private screenshots/conversation content captured.
- Only controller had the Docker socket; app metadata mount was read-only, app resource bounds unchanged at 1 GiB/2 CPU. No host checkout/config mounts or supporting-service ports. Native jobs/plists/installation directory absent; MLX/RDMA unchanged.
- Containerized controller's actual Docker connection and buildx/private configuration passed a disposable no-RUN scratch build; probe removed. Seeded sanitized deployed-revision state and observed independent persistent polls at 18:15:14 and 18:18:15 UTC, both correctly reporting unchanged, with fresh heartbeat. No native scheduler.
- Later, explicitly authorized real production Gemma attachment/streaming/completion smoke passed and temporary chat was deleted; detailed inference evidence is in spec 004 validation. This is distinct from non-inference readiness verification; no Studio inference or real vision-quality claim.

## Immediate authorized revert

Removed `lab.fios.deploy` (verified idle) and `lab.fios.readiness` from the user launchd domain, their plists and all installed programs/observations/release copies. Removed their installation directory after retaining sanitized prior rollout state under Git-ignored private `backups/deployment-evidence/spec005/`. Reverted only the native installation's `FIOS_READINESS_DIR`/`FIOS_IMAGE` private overrides; credentials unchanged. Production volume, stopped-data backup, prior image and legacy data remain untouched. No native MLX process, RDMA, routing or permission settings changed. During migration absent observations intentionally block remote targets; local Gemma remains usable. The old host installer now always fails safely and cannot recreate jobs.

## Local checks

- `npm ci`, frozen uv lock check, build: passed.
- **47 Node tests + 29 Python tests**, zero failures.
- **8 browser tests passed**.
- npm audit: zero vulnerabilities. Pinned pip-audit 2.10.1: no known third-party Python vulnerabilities; local non-PyPI project lookup skipped explicitly. This is not a claim of a complete OS-package vulnerability scan.
- Inference-boundary guard, syntax checks, quiet Compose validation and diff whitespace checks passed; no resolved secrets printed.
- Hardened native ARM64 isolated recovery rehearsal passed twice; latest peak **504 MiB** under the unchanged app 1 GiB limit (earlier pass 535 MiB).
- Same rehearsal now builds the separate pinned management image, verifies git/Docker Compose/buildx/flock and actual concurrent kernel-lock exclusion/reacquisition **without a Docker socket or network in the test container**. No PR-built test container receives management access.
- Named-volume observer integration against mock MLX: peer available → force-kill observer → after 5.2 seconds evidence unknown → restart → available. Application consumes the volume read-only. No inference used by discovery; existing generation fixture checks remain.
- Existing actual stopped-volume backup, verified image upgrade, injected verification failure → automatic rollback, old→new→old saved-history checks and real backup restore all passed on unique disposable resources. Only those resources were removed.

## Actual container connectivity (no inference)

Fresh probes from the hardened running app container and an isolated host-network container returned HTTP 200 for both Studio health endpoints. Unlike the earlier spec 005 observation, direct container connectivity now works. Root cause of that environmental difference was not established; no network/OS bypass or native proxy was installed.

Built the new app/observer image and management image as temporary validation images. A uniquely named Compose project started **only readiness**, with its own disposable metadata volume and no app database/socket/listener. Actual Node and installed isolated Python readers agreed: **3 healthy hosts, 5 available chat models**. No MLX model loading, prompts or inference. Project/volume cleaned up. The management image separately fetched public main metadata with bounded HTTPS, **without GitHub credentials, Docker socket or host mounts**.

## Coverage/security review

Eight functional requirements and five success criteria map to T001–T008; no unmapped tasks or unresolved clarification, 100% coverage, no constitutional exception. Native inference remains native; all supporting services containerized. App/observer have no Docker socket; only the dedicated trusted controller has explicit daemon-wide Docker authority, root solely for socket access, read-only root/cap-drop/no-new-privileges/no published ports and a separate network. It has no host source/config mounts or personal GitHub token. Do not call that socket read-only or least-authority Docker API: it is a high-trust management boundary.

Public discovery requires the latest exact-main push workflow plus all required checks, repeats both before stopping, rejects redirects/oversized responses, and caps real API requests at 50/hour with server-reset backoff. Idle polling is 20/hour. Linux flock guards the full controller loop, forwards shutdown to the lock-owning process and has kernel-released ownership. Supporting images stay stable while the app is stopped/backed-up/replaced; automatic compatible-image rollback uses `--no-deps` and preserves new records. Incompatible migrations/power loss still require the preserved backup/image and an operator recovery plan; do not interrupt an active rollout.

## Release gates — satisfied

Final-head CI, exact-head merge, independently green merged-main CI, stopped-backup production migration, authenticated/browser/Python verification and persistent container-controller startup were all observed above. No unmerged controller code was executed against production. User requested formal closeout after the remaining documentation/acceptance items were identified; this record reconciles those outcomes without inventing further test coverage.
