# Correlated preparation claim

This source-only layer adds `Tracker.claimCorrelatedPreparation`: guarded creation of a root, correlation association and exact model binding under one tracker mutex. It is an internal metadata primitive, not an admission protocol or authority issuer. It has no serving caller or transport opcode. The actual diagnostic serving configuration remains `primary_guard=false` and refuses it.

The fixed backend uncertainty probe runs before taking the mutex. The locked operation rejects unsupported guard, uninitialized/uncertain state and a zero correlation ID, then uses the existing entry, duplicate-correlation, model-conflict and transition checks. A failed unpublished claim retires only its own CPU metadata. Existing roots, retained references and independent uncertainty survive; consumed sequences are never reused. This does not establish advertised-model membership, memory capacity, native reservation, device completion or terminal proof.

The incremental [patch](../../../platform/studio/native/mlx-serve-correlated-claim.patch) applies after the qualified coupled-registry layer. The [checker](../../../scripts/check-platform-correlated-claim.mjs) reverses/reapplies that exact one-path projection and verifies the parent hash before compiling the actual tracker dependency closure with the [fixture](../../../platform/studio/native/correlated_claim_test.zig.fixture). Network access is denied and no model is used. Both Debug and ReleaseSafe run five named cases in separate processes: overlapping same-model roots and conflicting model refusal; duplicate correlation and maintenance; unsupported guard and uncertainty; model transition and retained older uncertain ownership; concurrent conflicting claims with exactly one retained winner. Two parent controls confirm the primitive is absent before the layer.

This does not complete T002, T019, T020, T021 or T022. Installation, activation, all-client native admission and both-Studio acceptance remain closed. Whole-task progress remains39/55.

Run only against a private source tree carrying the preceding reviewed layers:

```sh
node scripts/check-platform-correlated-claim.mjs --isolated --source /private/tmp/PRIVATE_SOURCE --zig /private/tmp/PINNED_ZIG
```

The tool requires the pinned Zig digest, owned private regular inputs and the expected source base/projection. It preserves its bounded logs and receipt under a fresh private directory. These are selected-input component receipts, not whole-repository or native provenance.
