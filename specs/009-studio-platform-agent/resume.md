# Spec009 resume — 2026-11-13

Whole tasks: **38/55 complete;17 open**. Partial source/component receipts do not complete whole tasks. Continue authorized source engineering and isolated tests; native installation, activation and disruptive acceptance remain separately gated. Fios remains the custom frontend for existing MLX-Serve APIs. The native patches change ownership bookkeeping, not numerical model implementations or new engines.

## Branch and delivery

- Use `009-studio-platform-agent`; draft [PR10](https://github.com/mcteer/fios/pull/10) targets `main`.
- Pushed `5ee5bb2259c79cb6ba32c49e39fe5de50571b8c7` contains54 source layers. [CI43499500420](https://github.com/mcteer/fios/actions/runs/43499500420) is running: five lanes passed, native process lane pending. Let it finish before another push.
- The next root commit adds verified55th-layer artifacts/evidence. Private native `91f1ded` commits55 layers; its only remaining WIP should be the preserved vendor/build-job changes.
- Last independently all6 prerequisites+aggregate green: `56e27e6`/[CI43493577533](https://github.com/mcteer/fios/actions/runs/43493577533). Consult the PR for newer exact-head CI; older green runs do not certify newer heads.
- No merge, production deployment, Studio installation or native activation occurred. Approved merge must still lead to exact merged-main green CI and verified automatic application delivery with backup/rollback. Native delivery remains separately gated.

## Completed current source increment

The55th layer retains a newly returned compiled ANE bank before fallible owner-array adoption. Rejected checked cleanup preserves the same unpublished pointer; local disposal or array adoption clears only the transferred reference. Pending native ownership blocks Unit cleanup. Known uncertainty stops SDK enqueue/compile splitting and host builder passes/publication, while the already reserved parent retains pending quantized inputs. No local close, join, counter or pointer transfer proves native terminality/admission.

- Adapted unchecked-close baseline:117/118 pass,1 expected model-free lost-owner assertion. The original adaptation patch/fixture, binary and receipts are preserved; this is not an unmodified upstream binary or native failure.
- Final118/118 fresh-process tests (58 current/60 support), source-review62/62 and working-tree163 Node/106 noneditable installed Python tests pass.
- Both full builds30/30 and each exact binary’s3 empty-model correlation/startup/authenticated-manager checks pass, with unchanged declared inputs. Dedicated closure/lint and repeated DS4154-input verification pass.
- All79 declared patch-changed files match the sequential55-layer tree, excluding preserved vendor/build-job WIP. This is selected changed-file equality, not whole-native Git provenance. Builds precede the private source commit; binary/input hashes identify the developer fixtures.

Record/commit this layer, then push/update PR and follow fresh exact-head CI after the current run finishes. Exact hashes/checkpoints are in [native port evidence](native-26112-port.md), [validation](validation.md) and [tasks](tasks.md). Earlier layer54 native114, layer53 C-wrapper4, layer52 unit109/C-root2 and layer51 C64/root16 receipts retain their original input scopes; do not relabel them fresh55-layer runs.

## Next actual ownership review

The readonly three-file receipt `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/ane-media-owner-audit-receipt.json` SHA72118da3ed094ec8b75906299db39536f897d000d92b59aebfbc20d5f7377894 identifies existing optional media callers:

- `src/plugins/krea/krea.zig`: Dit.aneDeinit discards engine cleanup and clears/frees fields; Engine.deinit retires text before Dit.
- `src/plugins/acestep/acestep.zig`: Engine.aneDeinit discards cleanup and clears/frees fields before other engine teardown.
- `src/plugins/minimax_h3/h3.zig`: Model.deinit frees MLX arrays/blocks before aneDeinit, which discards cleanup and clears/frees fields.

Their builders also have `errdefer eng.deinit()` and independent rest cleanup. No caller repair is claimed. Read actual constructor/ABI parent/callback paths before implementing checked propagation; initialize any added state before fallible effects. Keep known uncertainty independent and preserve numerical/default policy. Joined-worker, constructor/allocator/device/opaque callbacks, external plugin kits and complete producer/client/modalities/terminal/atomic-admission acceptance remain unproven. Do not enable positive native admission or run native fault campaigns.

## Private source and finite tools

- Source: `/private/tmp/fios-009-current-sdk-server-h_mvvlhq/source`; scripts/logs/receipts in its parent. Upstream26.11.2: `4e231ceebe63308cc038117d40b9f9b64bd0372e`.
- Sequential tree: `/private/tmp/fios-009-port-26112-ft5mnlcq/layer-check`.
- Zig0.17: `/private/tmp/fios-009-port-26112-ft5mnlcq/source/.zig-toolchain/zig`, SHA `1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523`.
- Current55 scripts use `ane-bank-adoption-{check,runtime,final-run}.py` and `current-ane-bank-adoption-closure.py`. Preserve labels, baseline artifacts and receipts. Full builds:2 jobs/1200s; runtime checks: separate empty homes/≤90s. Finish each full build and its runtime checks before another build or source edit.
- DS4: `/private/tmp/fios-ds4-build-JWkM7w/candidate.json`, SHA `c0167dbfdb302551562d5beeb35433dd0a38625891605961a048695cb0bb3bf3`;154 declared inputs only.
- uv0.13.5: `/private/tmp/fios-009-uv-xh120djv/uv` (not in PATH). Use locked noneditable CPython3.11.17. No sibling uvx exists; use equivalent `uv tool run --python 3.11.17 --from pip-audit==2.10.1 pip-audit --path .venv/lib/python3.11/site-packages`.
- `/private/tmp/fios-009-current-package-379v4djl/release` remains historical development data with incomplete package/enrollment and activation false. Its declared subset/26.10.3 template is not current Studio/native provenance or installation authority.

## Preserve unrelated work

Do not stage or overwrite the user's `README.md`, `specs/003-live-model-catalog/{spec,tasks,validation}.md`, `src/main.jsx`, `src/styles.css`, `tests/browser/catalog.spec.js`, `a.out` or `docs/model-inventory.md`. Working-tree application results include those frontend changes; exact-head CI is separate evidence. Preserve private native `lib/mlx-src`, `lib/mlxc-src` and `scripts/build-mlx.sh` WIP; never stage them with a source layer.

Keep008 parked at3936da2; no routing/OpenWebUI restoration, RDMA/network/SSH configuration changes or legacy data deletion. Small-model inference is authorized only on `fios-core`, the24GiB M4-family Mini. Studios host larger models only; do not move core models or substitute a larger model for acceptance. This continuation used zero real inference and no SSH. Cybersecurity/pen-testing/native fault campaigns remain excluded.

## Remaining whole tasks

T002, T008, T009, T018, T019, T020, T021, T022, T027, T028, T030, T033, T036, T045, T049, T051 and T055 remain open; follow their actual [acceptance criteria](tasks.md). Coverage stays unknown/native admission unsupported until the audited all-client contract and separately gated operational acceptance exist. Desired service state is durable intent, not actuation. Stage-release copies private data only; local cleanup/acknowledgements never clear independent native inference uncertainty.
