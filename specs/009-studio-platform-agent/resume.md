# Resume after macOS updates — 2026-11-12

## Latest resumed checkpoint

The operator resumed work. The Llama slot-retirement source change now passes the actual scheduler case3/3 and complete native executable/link build; see validation for exact hashes and limitations. Whole tasks remain38/55.

Current private source base: `/private/tmp/fios-009-resume-sources-yyrvdgjh`; the earlier base below expired during updates. All canonical native submodules, pinned Zig/Llama, CMake, Apple headers and fresh MLX/DS4 source dependency receipts are restored. `slot-command.json` retains the exact finite build argv; `slot-native-build-complete.log` is the successful final build. Earlier failed recovery/build logs remain separately retained. The installed application is now26.11.2; the fixture uses a private original26.10.3 library copy with unchanged exact hashes through `--bundle-frameworks`. No installed code changed.

Next: inspect exact-head PR CI after pushing this checkpoint, then continue ordinary functional source integration. Loaded GGUF/MTP synchronization behavior/latency, all-client native admission and installed lifecycle acceptance remain unproven. Do not relabel this empty-handle scheduler test as loaded-backend or Studio acceptance. No model/server/Studio/SSH/lifecycle/deployment action occurred.

## Historical pause note


Operator is updating edge-a, edge-b and this development Mac and requested a pause/resume note. Work is paused for those updates. Continue authorized implementation when asked; do not treat host disappearance during updates as terminal inference proof.

## Branch and preserved work

- Branch: `009-studio-platform-agent`; committed head `6eb4f38b86a36665016d3d0c5229d4853a9a77e3`, already pushed. Draft PR: https://github.com/mcteer/fios/pull/10.
- Exact-head CI run https://github.com/mcteer/fios/actions/runs/41535723987 reports success for all six prerequisites and aggregate CI gate. This is PR CI, not merge, deployment or native acceptance.
- Whole tasks remain **38/55 complete**, 17 open. Do not mark partial source receipts as whole-task completion.
- Uncommitted implementation: `platform/studio/native/mlx-serve-26.10.3.patch` and `scripts/check-platform-native-fixture.mjs` only. Preserve other existing user edits in README, spec003, main.jsx, styles.css, browser/catalog.spec.js, a.out and docs/model-inventory.md.

## Current change — incomplete, not committed or activated

Actual Llama `decode_rows` starts MTP catch-up via `llama_process` on the draft context; sampling target output does not establish draft completion. Existing `Slot.deinit` released the original request/model references without calling the existing exact-context target+draft terminal primitive.

The uncommitted patch adds `Slot.fiosRetireLlama` before ANY slot destructor field capture, reference release or destruction. It invokes `seq.ctx.terminal()` and retains the entire slot/model/request on refusal, fencing the original tracker. Non-Llama slots do not call a Llama barrier. This applies to ordinary completion and decode cancellation through their existing cleanup funnel; it does not grant all-client coverage or native admission.

New actual scheduler test: `fios native slot cleanup retains refused Llama request custody`. It supplies a genuine lifetime-fenced context with no native handle and only the slot fields needed for refusal. The actual destructor must return before touching absent fields, preserve the original owner, and leave sticky uncertainty. The native fixture builder now allows this named functional test and declares `native_llama_slot_retirement_version` when present.

**Validation so far:** focused Node source/review/model-capability/DS4 tests passed 24/24 (`/private/tmp/fios-009-llama-slot-node.log`). This does NOT compile or execute the new Zig scheduler test. Native compilation, that runtime test, existing Llama/C++ regression checks and source review remain required. Loaded GGUF/MTP acceptance is not established; do not substitute core Gemma and claim Llama coverage. Inspect `fiosRetireLlama` placement/comments, real synchronization latency, and all normal/cancel/OOM cleanup paths before committing.

## Recovered private build inputs

Old `/private/tmp` trees expired during interruption. New private base is `/private/tmp/fios-009-resume-sources-q0dezhm9`, also recorded in `/private/tmp/fios-009-resume-sources-current.json`. It contains:

- `native`: exact046b647 checkout with current canonical root patch applied, pinned upstream `scripts/fetch-llama.sh` and `scripts/fetch-zig.sh` run successfully. Zig `.zig-toolchain/zig` SHA256 is `1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523`; llama `lib/llama/lib/libllama.dylib` SHA256 is `10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b`.
- `mlx`: exact64ea011 with canonical owner-uncertainty patch applied.
- `ds4`: exact9139e2a with canonical request-origins patch applied.
- `mimo`: exactfcb4011 with canonical request-origins patch applied.
- clean `json`9cca280, `fmt`407c905, `webp`4fa2191, `mlx-c`56b2d39 checkouts.
- downloaded `metal-cpp_26.zip` and `cmake.tar.gz` (CMake4.2.3 macOS universal). Downloads completed; extraction and pinned artifact hash checks still pending.

Private source recovery logs are in this base and `/private/tmp/fios-009-resume-{llama,zig,metal,cmake}-fetch.log`. New DS4 and MLX build receipts have NOT been generated. Do not reuse missing old artifact receipts or relabel old test results as new ones.

## Next concrete steps

1. Re-read constitution and active009 tasks/plan; resolve active feature with prerequisite script. Keep008 parked; no new login/password interface or unrelated features.
2. Verify recovered inputs after reboot, extract/verify CMake and Apple headers, restore native canonical submodule header directories from exact pinned sources. Rebuild genuine reviewed MLX/DS4 dependencies using existing finite ordinary build commands.
3. Run `check-platform-native-fixture.mjs` with recovered root/Zig/WebP/Metal inputs, fresh DS4/MLX receipts and MiMo request-origins variant, `--mimo-request-origins --ds4-request-origins --functional-test 'fios native slot cleanup retains refused Llama request custody' --functional-build-only`. Read its fixed argument order. Freeze every native input during the build; no concurrent MiMo graph fixtures. No historical mutation/counter/fault campaigns.
4. Run relevant existing Llama/C++ and boundary checks, review the patch, and record actual results/limitations in tasks/validation. Update PR description beyond its older9ef4692 description and then commit/push only reviewed009 changes.
5. Continue remaining implementation. Source/native acceptance remains incomplete; do not stop merely because this partial change passes. Installed handover/service activation/privileged or disruptive acceptance are separately gated. Core-only small-model inference standing authorization remains; Studios are large-model hosts.

No installed service, native inference process, model policy, RDMA, network or deployment action occurred in this resumed turn. No SSH/Studio action was performed. No build or download process remains intentionally running for the update.
