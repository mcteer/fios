# Versioned registry claimability metadata

The prior readonly registry frame distinguishes ready, transitioning and
uncertain entries, but an owned unloaded target and an errored target can both
have none of those flags. A preparation consumer must not treat those identical
flags as proof that the target remains available.

Version4 retains the67168-byte coupled capture and adds claimable bit4 in each
row's flags byte. The registry computes it under the existing registry lock:
only an unexceptional unloaded or ready entry is claimable. Loading, eviction,
error and uncertain entries are not. This describes eligibility for the existing
CPU registry claim, not native resource capacity, terminality, complete source
coverage or a dispatch permission. Capturing it never loads a model.

Version3 keeps its original flags/encoding. The decoder preserves its unknown
claimability instead of synthesizing false or true. Current Core explicitly
requests4 and refuses a3 response on that request; there is no automatic fallback.
The parser/diagnostics reject contradictory flags, missing coupled data,
continuity/format changes, replay and reserved bytes. The independent source
coverage ceiling and unsupported native guard remain unchanged.

The isolated checker verifies the exact three-file parent/reapply projection
and copies the actual tracker, registry-helper and protocol closure. Explicit
CPU registry entries exercise unloaded/ready versus error/loading/uncertainty,
contradictory provider flags, unsupported versions and legacy encoding. Actual
Zig frames are separately decoded by current Core Debug/optimized binaries;
these are interoperability checks, not all-client or hardware acceptance.

```sh
.venv/bin/python -I scripts/check-platform-registry-claimability.py \
  --source /private/tmp/REVIEWED_SOURCE --zig /private/tmp/PINNED_ZIG
node scripts/check-platform-registry-claimability-cross-frames.mjs --isolated \
  --receipt /private/tmp/REVIEWED_RECEIPT --sha256 REVIEWED_SHA256
```

The new internal NativeOwnedPreparationCoherence check is deliberately narrower
than generic activity normalization. It requires a separately supplied reviewed
all-client ceiling, an original current registration, fresh matching live root
and v4 registry capture, exactly that one preparation owner, a claimable target,
no competing work/transition/uncertainty and at most one registry-ready model.
It keeps the preparing target and the ready declaration separate during possible
on-demand replacement. It does not relabel the latter as the target or export
global idle/eligibility. Generic conflicting busy/resident normalization remains
unknown. The result creates no process, permission, capacity or terminal proof.
Default/unsupported source coverage yields no scoped result.

This is not yet an observation export or broker/worker integration. Existing
Python metadata2/handoff1 behavior remains unchanged. Owned preparation must not
be implemented by accepting generic unknown activity or by treating this flag as
all-client authority. T020/T022/T045 and whole-task progress remain open39/55.
