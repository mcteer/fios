# Exact registry preparation claim

This source-only layer connects the internal correlated preparation claim to exact local registry metadata. It adds no serving caller or transport operation and does not enable the diagnostic serving guard. It is not a native admission, advertised memory-capacity or device-terminal proof.

`ModelRegistry.claimFiosPreparation` uses the fixed process tracker. Before taking the registry mutex, the helper checks the fixed backend uncertainty probe. Under registry→tracker locks, it validates the exact advertised entry, ≤4096 entries, bounded exact UTF-8 identities and the registry generation range. Missing or mismatched identities, a failed target, loading/evicting entries and known cleanup uncertainty refuse. Unloaded but advertised entries remain eligible for this metadata operation; it never loads a model or changes registry state/generation. Known registry cleanup uncertainty is latched into the tracker and cannot be cleared by a later false observation.

The callback-free tracker edge creates/correlates/model-binds only the new CPU preparation root. It retains the existing guard, maintenance, correlation, model-conflict, mutation and sticky-uncertainty checks. Generation change after creation fences the tracker and retires only that unpublished metadata claim. Existing roots and independent uncertainty remain. This does not issue a transport nonce, reserve native capacity, attest all clients or release an inference lease.

The [three-path patch](../../../platform/studio/native/mlx-serve-current-registry-claim.patch) follows the [correlated claim layer](correlated-preparation-claim.md). The [component checker](../../../scripts/check-platform-current-registry-claim.mjs) verifies exact parent hashes and reverse/reapplication, then compiles the actual tracker and helper with registry-shaped CPU metadata. The [fixture](../../../platform/studio/native/current_registry_claim_test.zig.fixture) covers cold advertised entries/conflicts, identity/phase/uncertainty refusal, probe-before-lock/no-callback ordering and diagnostic guard refusal. Two controls confirm the parent lacks the new callback-free edge. The genuine `ModelRegistry` wrapper has a separate native-root stub test; no real model is allocated.

```sh
node scripts/check-platform-current-registry-claim.mjs --isolated --source /private/tmp/PRIVATE_SOURCE --zig /private/tmp/PINNED_ZIG
```

These selected-input source checks do not complete T002/T019–T022, production installation or Studio acceptance. Whole-task progress remains39/55. Native activation stays closed.
