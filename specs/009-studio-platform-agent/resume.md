# Spec009 continuation — 2026-11-15

Whole tasks: **39/55 complete;16 open**. Detailed historical evidence and retained failures are in [validation.md](validation.md); this file describes current work only.

## Current source and checks

Branch `009-studio-platform-agent`, draft [PR10](https://github.com/mcteer/fios/pull/10). Published head `19ef1826a797cc7cc59da791c5f25257cad5572b`; [CI43679564386](https://github.com/mcteer/fios/actions/runs/43679564386) passed all7 jobs including aggregate. Neither merge nor application/native deployment has occurred.

Current uncommitted increment retains original request ownership in the existing ANE model-build workers, independently of the previously qualified second inference lane. Private source `/private/tmp/fios-009-ane-build-work-om86by09/source`, parent `/private/tmp/fios-009-ane-lane-work-k2x4qnn2/source`. Only native `src/engines/ane/lm.zig` changes; numerical operations and actual serving `primary_guard=false` remain unchanged.

Corrected strict receipt `/private/tmp/fios-009-ane-build-check-vPq6Uf/receipt.json`, SHA `eaa8df6dd1f31eebc00b78970a310eae7413bd37ad956e9031730ac818e49eb0`: full LM AST validation,10 original failures,2 legacy controls and12 candidate cases, Debug/ReleaseSafe with frozen inputs and network denied. Explicit CPU native-compilation and thread-spawn substitutes are component tests, not native terminal/admission authority.93 focused Node/boundary/syntax/whitespace checks pass.

Corrected default native build passed in173.923s with declared inputs unchanged. Fresh separate-process native suite passed162/162, zero skips; binary SHA `d96099b1fd4486f99ada5b718eee67bc0bebb138d8190637ba04ced48994f9dd`. Enabled semantic35/35 passed402.594s; link32/32 passed11.900s. All4 empty-model runtime checks and post-runtime capsule/source verification pass. Aggregate `/private/tmp/fios-009-ane-build-work-om86by09/final-source-qualification.json`, SHA `11b2deb4737fcd6fa8e9c29e548c55221111eed834afcc1bd69895bf826b1f77`. Raw binaryfe542586…, normalizedf3db286c…, capsule486717d1…. All local P32 sessions complete. Ready to commit explicit009 paths, push and bind the new exact-head CI. Continue remaining source work; no whole task closes from this increment.

Preserve initial field-syntax build failure71.500s (`.field-syntax-error` receipts/logs), its erroneous dependent unit invocation (no binary, zero tests), private-method fixture-detection error, initial template assertion and pre-atomic-observer fixture matrix. Superseded6e3ad098 strict receipt was component-only against invalid full-source field syntax. The corrected checker adds AST validation before extraction. Do not report those failures as native passes.

P31 second-lane source is fully qualified/published19ef: strictd391f35d…, default162/162, enabled35/35 semantic32/32 link,4 empty-model runtime checks; aggregate99966bde…. Earlier P29 DS4 status and P30 shared-observer future-time correction are published1935ca7 with all7 CI jobs green. Shared-observer readers reject every future timestamp; native-private clock contracts retain their separate1s limit.

## Current package and scope

Clean declared-input platform package `/private/tmp/fios-009-bound-completion-package-red1e5d1/{source,release}`, revision `4bbcf3c236abdb93f7078921316688454849e376`,9 artifacts. Manifest121ba32a6576efad4504036bc91d55df9b0e514550bff74814661a93bd7c9c1f; source projectione1c0af4584ea6543f422cecd94e327777e3076f6b52d66a6cba831338ac6d765. Both Studio reviews retain5 blockers/no privileged commands. Actual private packaged supervisor/manager status and normal shutdown passed with0 model POSTs/native service actions.

The package's declared projection excludes native patch/fixture/checker/docs and agent Python source. Unchanged package inputs therefore do not certify current interpreter/native or whole-repository provenance. Completion/enrollment/activation remain false; approved runtime images remain empty.

The operator explicitly approved **image only** for `sha256:0406a8451a382eef038d8ac37035ccfb4e2a1e4e7b22c4a349fd9c4648a77c0b`; T033 is complete. No approval question is pending. This grants neither publisher/build authenticity nor installation, enrollment, activation or native admission. Preserve the original review receipt and separate decision record.

## Remaining work and limits

T002 audited all-client contract;T008 installed resources;T009 installed runtime;T018 all enabled modalities;T019 whole switch/guard/cancel/restart;T020 authoritative normalized producer;T021 genuine native proof issuer/reconciliation;T022 atomic native admission;T027 production lifecycle/custody/GUI handover;T028 actual drain/force;T030 whole US3integration;T036 enrolled sandbox runtime;T045 production task wiring;T049 protected installer/rollback/uninstall;T051 separately approved two-Studio acceptance;T055 final exact CI/reviewed merge/green merged-main automatic verified application deployment and separately gated native rollout. Partial source/mock receipts do not close whole tasks.

Continue authorized source engineering/isolated fixtures without another scope question. Native installation/activation, privileged/disruptive acceptance and merge remain separately gated. Cybersecurity/pen-testing and physical hardware-fault work are excluded. No receipt/profile flag, local join/reap, zero count, HTTP completion or service acknowledgement may clear independent native inference uncertainty or manufacture positive all-client authority.008 stays parked at3936da2.

Five finite Core-only requests for exact `mlx-community/gemma-4-e4b-it-4bit` have been consumed. **No sixth POST or new model plan.** All stopped claims retain uncertainty; Core24GiB small-model development evidence is not Studio acceptance. Do not move this model to a Studio or substitute a larger one on Core.

Protect unrelated WIP: README.md;specs/003-live-model-catalog/{spec,tasks,validation}.md;src/main.jsx;src/styles.css;tests/browser/catalog.spec.js;untracked docs/model-inventory.md. Stage only explicit009 paths; never `git add .`. Preserve all private candidates/failures. No subagents without explicit authorization.

## Tools

Use uv0.13.5 `/private/tmp/fios-009-uv-xh120djv/uv` and CPython3.11.17 `.venv/bin/python -I -B`; system Python is3.15. Reinstall the locked noneditable fios-agent after any Python source change. No agent Python source changed in this increment.

Zig `/private/tmp/fios-009-port-26112-ft5mnlcq/source/.zig-toolchain/zig`, SHA1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523. Do not fmt the whole native LM file: this compiler rewrites unrelated enum conversions. Existing drivers use2 compile jobs with finite deadlines; keep dependent stages sequential.

Keep analysis brief and concrete, commentary within60s, whole-task counts at least every10min. Continue implementation; do not end with a status-only final.
