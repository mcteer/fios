# Spec009 resume — 2026-11-13

Whole tasks: **38/55 complete;17 open**. Partial source/component receipts do not complete whole tasks. Continue authorized source engineering and isolated tests; native installation, activation and disruptive acceptance remain separately gated. Fios remains the custom frontend for existing MLX-Serve APIs. The native patches change ownership bookkeeping, not numerical model implementations or new engines.

## Branch and delivery

- Work on `009-studio-platform-agent`; draft [PR10](https://github.com/mcteer/fios/pull/10) targets `main`.
- Pushed `56e27e6c037cde88f77bc709ed54af87064f695b` contains52 source layers. [CI43493577533](https://github.com/mcteer/fios/actions/runs/43493577533) passed all6 prerequisites and aggregate. This is the last verified head; consult the PR for newer exact-head CI.
- The branch now adds the verified53rd wrapper and54th SDK cleanup layers. Private native `ffdad50` commits54 layers; preserve its unrelated vendor/build-job WIP.
- Previous `3d3fe76`/[CI43488388641](https://github.com/mcteer/fios/actions/runs/43488388641) passed all6 prerequisites and aggregate. This does not certify newer heads.
- No merge, production deployment, Studio installation or native activation occurred. Approved merge must still lead to exact merged-main green CI and verified automatic application delivery with backup/rollback. Native delivery remains separately gated.

## Current source work

The54th layer propagates checked ANE MLP cleanup refusal through SDK Unit/AnePrefill and the existing Transformer parent. It separates checked child close from CPU-container disposal, retains all sibling containers on later refusal, prevents cleanup replay, keeps private resident gauges unchanged on refusal and retains constructor error-unwind allocations when child cleanup refuses. The optional engine is reserved in its existing parent before fallible build effects. Local close/join success grants no native terminality or admission authority.

Current evidence:

- Explicitly adapted unchecked-disposal baseline:110/113 pass,3 expected allocator/ownership assertions. This is an injection seam around the original unchecked flow, not an unmodified upstream binary or real native failure.
- First correction:113/113 pass. Adding the later-unit refusal control reproduces its partial-container-retirement bug:113/114 pass,1 expected assertion. Two-phase correction passes114/114 in fresh processes (54 current/60 supporting tests).
- Source review61/61, working-tree162 Node/106 noneditable installed Python tests pass. Both full builds and each exact binary’s3 empty-model runtime checks pass, as do dedicated closure/lint and repeated DS4154-input verification. Do not edit private source during future builds or runtime input checks.
- All79 declared patch-changed files match the sequential54-layer tree, excluding preserved vendor/build-job WIP. This is changed-file equality, not whole-native provenance.
- Actual C wrapper4/4 O0/O2 controls pass again at `/private/tmp/fios-009-ane-mlp-wrapper-current-a0b4_xnh/receipt.json`; tiny healthy IOSurface≤32KiB, no ANE model/API or inference.

All current54 source checks are complete. Record/commit this layer, push and update PR with fresh exact-head CI; do not cancel a running native lane with another push. Exact receipts are in [native port evidence](native-26112-port.md), [validation](validation.md) and [tasks](tasks.md). Earlier layer52 unit109/C-root2 and layer51 C64/root16 receipts remain historical exact-input runs, not fresh54-layer evidence.

Further review remains for optional SDK bank splitting/build callbacks, constructor/error/allocator/opaque cleanup paths, external plugin kits and complete native producer/client/modalities/terminal/admission coverage. Actual joined-worker/constructor/native/device paths are not established by callback spies. Do not enable positive native admission or infer readiness from gauges, local disposal, process identity or sampled zero activity.

## Private source and finite tools

- Native source: `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/source`; scripts/logs/receipts in its parent. Upstream26.11.2 pin: `4e231ceebe63308cc038117d40b9f9b64bd0372e`.
- Sequential layer tree: `/private/tmp/fios-009-port-26112-ft5mnlcq/layer-check`.
- Zig0.17: `/private/tmp/fios-009-port-26112-ft5mnlcq/source/.zig-toolchain/zig`; SHA `1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523`.
- Current54 scripts: `ane-sdk-cleanup-multi-{check,runtime,final-run}.py`. Build/runtime labels and baselines must not be overwritten. Full builds use2 jobs/1200s; runtime checks use separate empty homes and≤90s bounds. Finish one build and its runtime checks before another build.
- DS4 candidate: `/private/tmp/fios-ds4-build-JWkM7w/candidate.json`, SHA `c0167dbfdb302551562d5beeb35433dd0a38625891605961a048695cb0bb3bf3`;154 declared inputs only.
- uv0.13.5: `/private/tmp/fios-009-uv-xh120djv/uv` (not in shell PATH). Use locked noneditable CPython3.11.17 installation. No sibling uvx exists; equivalent `uv tool run --python 3.11.17 --from pip-audit==2.10.1 pip-audit --path .venv/lib/python3.11/site-packages` works.
- Package at `/private/tmp/fios-009-current-package-379v4djl/release` is historical development data with incomplete package/enrollment and activation false. Its declared subset/26.10.3 template is not current Studio/native provenance or installation authority.

## Preserve unrelated work

Do not stage or overwrite the user's `README.md`, `specs/003-live-model-catalog/{spec,tasks,validation}.md`, `src/main.jsx`, `src/styles.css`, `tests/browser/catalog.spec.js`, `a.out` or `docs/model-inventory.md`. Working-tree application results include those frontend changes; exact-head CI is separate evidence.

Preserve private native `lib/mlx-src`, `lib/mlxc-src` and `scripts/build-mlx.sh` WIP. Never stage them with the current source layer. Keep008 parked at3936da2; no routing/OpenWebUI restoration, RDMA/network/SSH configuration changes or legacy data deletion.

Small-model inference is authorized only on `fios-core`, the24GiB M4-family Mini. Studios host larger models only; do not move core models or substitute a larger one for acceptance. This continuation used zero real inference and no SSH. Cybersecurity/pen-testing/native fault campaigns remain excluded.

## Remaining whole tasks

T002, T008, T009, T018, T019, T020, T021, T022, T027, T028, T030, T033, T036, T045, T049, T051 and T055 remain open. See their actual acceptance criteria in [tasks](tasks.md). Keep coverage unknown/native admission unsupported until the audited all-client contract and separately gated operational acceptance exist. Desired service state is durable intent, not actuation. Stage-release copies private data only; local cleanup and acknowledgements never clear independent native inference uncertainty.
