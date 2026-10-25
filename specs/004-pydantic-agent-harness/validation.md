# Validation Evidence — 004

Date: 2026-10-25. Branch: `004-pydantic-agent-harness`.

## Result

Complete and closed (2026-10-25), all T001–T052 complete. Initial implementation `1a9de23`; [PR #1](https://github.com/mcteer/fios/pull/1) merged as `64c05daa26f3b34a8636af3f400e44c4e8c37a1d` after all six exact-head checks passed ([final PR CI](https://github.com/mcteer/fios/actions/runs/40208026801), [merged-main CI](https://github.com/mcteer/fios/actions/runs/40208173668)). Production rollout was separately authorized and subsequently completed, including the container-only stack in [PR #3](https://github.com/mcteer/fios/pull/3). Implementation-stage observations below are historical, not current outstanding gates.

## Authorized real production inference — 2026-10-25

After the user explicitly said “proceed”, ran `node scripts/check.mjs 'mlx-community/gemma-4-e4b-it-4bit'` against production `84418cdf2ec9d08e44e3bf0f6f59872734be5983`. Authentication and discovery succeeded; the exact local model was initially on demand. A temporary text attachment contained `workspace_name = "Fios connected"`. The real Fios → Pydantic AI → native MLX-Serve request streamed **`Fios connected`**, reported successful completion and passed the attachment-context assertion. The script's finally cleanup deleted the temporary test conversation successfully. No fallback, automatic retry, substitution or Studio-model inference was used. The model may remain loaded; no unload was requested. This verifies real text/attachment inference and completion, not all models, vision semantics or real remote compute cancellation.

## Planning and implementation history

- Specify, clarify, plan, tasks and read-only analyze completed before implementation; no blocking analysis findings. Requirements quality checklist remained 16/16 passing and was not modified by implementation.
- No `.specify/extensions.yml` exists; no pre/post extension hooks applied.
- Setup/foundation T001–T012 were completed first, initially with 19 Node and 12 Python tests. The worker intentionally failed closed until the Agent was connected; those counts were an intermediate checkpoint, not final acceptance.
- Agent code and its Node bridge now live in `src/agent/`. Express's raw Chat Completions request and obsolete upstream parser were removed. The browser API and SQLite schema remain unchanged.
- Protocol/supervisor/worker and context/transport/harness tests were observed failing before their respective implementations. API/browser regressions were then exercised through the real installed Python Agent against mock MLX.
- Pinning refinement: use uv-managed CPython **3.11.17** in both development and the Bookworm image, rather than a mutable apt patch version. uv **0.13.5** is enforced in project metadata; Node/uv base-image digests are pinned. The frozen lock resolves **27 packages** including `pydantic-ai-slim[openai]==2.61.0`, `openai==3.37.0`, and `httpx2==2.16.0`.
- Tagged upstream API research was confirmed in implementation. Pydantic model-error wrappers, the SDK's default retry behavior, buffered mock streams, and the default Pydantic banner were explicitly handled. Retry count is zero, the banner is disabled, and `[DONE]` plus final Agent success is required for completion.

## Final validation results

| Check | Observed result |
| --- | --- |
| `npm ci` | Passed; 252 packages installed, 253 audited. |
| `uv lock --check` | Passed with pinned uv 0.13.5. |
| `uv sync --locked --no-editable --reinstall-package fios-agent` | Passed; isolated import and exact package versions verified on CPython 3.11.17. |
| `npm test` | **34 Node tests + 23 Python tests passed**, zero failures. |
| `npm run build` | Passed; agent modules are not frontend imports/assets. |
| `npx playwright test` | **7 passed**, including existing desktop/mobile/catalog flows and new harness attachment/reasoning/error-recovery flows. |
| `npm audit` | **0 reported vulnerabilities**. |
| Pinned `pip-audit==2.10.1` against installed Python environment | **No known third-party vulnerabilities found**. Local `fios-agent==0.1.0` is not a PyPI package and is explicitly skipped by the advisory lookup; project code is covered by its tests/review, not a registry advisory claim. |
| `docker compose config --quiet` | Passed without printing resolved settings. Production Compose boundaries remain unchanged. |
| `node scripts/check-agent-boundary.mjs` | Passed: no production inference outside the Python harness, browser imports, tools or fallback. Paired with runtime no-bypass tests. |
| `node scripts/check-agent-container.mjs` | Passed on **aarch64 Linux / CPython 3.11.17** with UID 1000, read-only root, existing 1 GiB/2 CPU limits, private worker and localhost-only app port. |
| `node scripts/check.mjs` without model argument | Passed against the **unchanged deployed app**: 5 chat entries, covering Mini plus both Studio peers. No inference requested. This is baseline discovery evidence, not proof of a deployed harness. |
| Diff, local-link, ignore and secret-pattern checks | Performed before commit; local `.env`, environments, databases and generated artifacts excluded. |

## What the suites prove

- Actual Pydantic Agent traversal for local and peer-qualified mock IDs; exact ID preservation and one upstream attempt on successful sends, HTTP failures and SDK timeout. No fallback when Python is unavailable, and no tools executed on unexpected tool output.
- Incremental text/reasoning without duplicate initial/final content; `[DONE]`-only valid streams, usage chunks, truncated/malformed streams and output-overflow handling. Reasoning is never saved or replayed.
- Existing text/PDF extraction wrappers and inline image bytes survive translation. Text-only models reject image histories. UTF-16 counting matches JavaScript; maximum 400,000-unit text plus 20 MiB decoded image context passes through the actual worker.
- A synthetic legacy SQLite fixture retains all original records/blob content, can be continued without duplicated turns, survives app restart, recovers stale streaming rows and cascades deletion. No simultaneous app/test DB access occurred.
- Stop with and without first tokens, browser disconnect, worker crash, completion races, repeat stop, parent SIGKILL/stdin EOF, and a SIGTERM-resistant wedged worker all reach coherent terminal state. Controlled cancellation/cleanup stays below two seconds; the wedged-process path takes approximately 1.56 seconds. A later user request recovers without replaying the failed request.
- Authentication/origin rejection, catalog refresh, CRUD and health checks produce zero inference calls. Tests inspect child-environment filtering, fixed safe diagnostics and absence of known content/key markers in captured logs/browser assets. No listener or SQLite dependency exists in the worker.

## Hardened container and recovery rehearsal

The script built a distinct temporary feature image and used unique Compose project/network/volume names, mock MLX only, and a free **127.0.0.1** port. Production `fios_fios-data`, native services, RDMA and the detached legacy Open WebUI volume were not touched.

1. Started prior image `fios:0.1.0` on the disposable volume and saved a synthetic conversation.
2. Stopped that app before copying its SQLite snapshot to a backup on the same disposable volume.
3. Started the new harness image and verified record fidelity plus new streaming/stop behavior.
4. Exercised maximum Unicode/image context with a deliberately slower consumer and measured cgroup peak memory. Successful passes measured **498–552 MiB**, below the unchanged **1,024 MiB** cap; latest pass **498 MiB**. No claim of a universal production memory bound beyond these tested scenarios.
5. Killed a test Node parent in the container and verified the private worker did not remain live; Compose init reaped it.
6. Stopped the new app, switched back to the prior image, and verified all post-upgrade messages remained readable without schema migration.
7. Stopped that app, restored the actual pre-upgrade backup, restarted, and verified the original records exactly.
8. Removed only the test project's containers/network/volume and temporary image. Prior production image and service remain intact and healthy.

Latest successful test image: `fios-agent-test:aaf865a6-b4f` (removed after validation). Prior image: `fios:0.1.0` (preserved). Local build/test log: `/var/folders/hq/9t1wgm2x713f5qykp8y8wldc0000gn/T/fios-agent-test-aaf865a6-b4f.log` (not committed).

Two initial test-harness runs exposed OrbStack behavior around dynamic port reporting and `internal: true` network port publishing. They were cleaned up. The test harness now selects a free localhost port explicitly and uses a separate ordinary bridge network, with no mock host port. This was a test-network correction, not a production network or cluster change.

## Hosted CI follow-up

The user requested project CI before merging this PR. Added `.github/workflows/ci.yml`, scoped this release-gate extension in FR-015/SC-007, and updated operating/agent guidance.

- Triggers: PR, push to main, manual dispatch and weekly schedule. No path filters that could silently omit a gate.
- Read-only repository permissions, no persisted checkout credentials, SHA-pinned actions, explicit timeouts and cancellation of superseded runs. No production secrets, native hosts, real model inference, remote execution or deployment.
- Node **22.23.4** and **24.15.0** on Ubuntu 24.04: clean npm/frozen Python install, lockfile consistency, build, **34 Node + 23 Python tests each**, and boundary guard.
- Chromium browser job: **7 passed** with installed frozen Python harness and mock MLX.
- Dependency audit job: npm reports **zero vulnerabilities**; pinned pip-audit reports **no known third-party vulnerabilities**, with the local non-PyPI package explicitly skipped as documented above.
- Native `ubuntu-24.04-arm` job: builds the immutable pre-harness commit `526f8c9747ac17b0ba6df5261338f0b60134d24b` as its disposable baseline, then runs hardened image, cancellation, maximum-context, parent-death, upgrade/rollback and actual backup restore tests. Peak observed in the green run: **530 MiB** under the unchanged 1 GiB cap. Compose validation uses ephemeral test-only settings and suppresses resolved output.
- Mock-only failure diagnostics have seven-day retention. The stable `CI gate` requires every job to succeed and fails on failed, cancelled or skipped prerequisites. It does not convert missing or pending checks to success.
- Local validation: **actionlint 1.7.12 passed** (release checksum verified); all action references are full SHA pins. The gate's actual Node expression was exercised against **16 combinations** of successful/failed/cancelled/skipped prerequisites and returned the expected exit status for each.

Observed runs:

1. [40206877273](https://github.com/mcteer/fios/actions/runs/40206877273), commit `aab51b7`: all six job/check results green on the first hosted run. GitHub warned that initial action versions used deprecated Node 20 runtimes.
2. Upgraded to SHA-pinned current releases: checkout **7.0.1**, setup-node **7.1.0**, setup-uv **10.3.2**, upload-artifact **7.0.2**, without changing application dependencies. [40207384697](https://github.com/mcteer/fios/actions/runs/40207384697) surfaced an existing Node 24 test timing race: the 300 ms test-only watchdog could expire before a busy runner submitted its first mock request. The aggregate gate correctly failed; no failed-check bypass or blind retry was used.
3. Fixed that test in `7960f67`: observe the mock request before arming the short idle deadline, and await actual worker exit instead of a 50 ms sleep. Production watchdog/cancellation settings were not relaxed. Five consecutive local focused runs passed.
4. [40207715628](https://github.com/mcteer/fios/actions/runs/40207715628), commit `7960f67c45a6a6b2ebe7548781ceb6b9c74f34b2`: **all six checks green**, covering both Node runtimes, browser regressions, audits, native ARM64 container recovery and aggregate gate with the current action pins and deterministic regression.

This evidence commit must itself pass hosted CI before merge. The merge operation must match the exact checked PR head SHA and must not use administrator bypass. No branch-protection settings or production deployment changes are made by adding CI.

## Deliberately not claimed

- Production deployment and the explicitly authorized local Gemma inference test are verified above. No real Studio-model inference, real vision understanding or large cold-model behavior is claimed.
- Mock image fidelity is not evidence of real model image understanding.
- Closing/cancelling the client stream is verified; remote native MLX compute termination, cluster failover, distributed RDMA performance and large cold-model behavior are not claimed.
- ADR 0002 is accepted. Conditional exact-head merge approval, subsequent production-delivery authorization and the later explicit real-inference authorization were distinct events; none authorizes native cluster changes or direct-to-main feature commits.
