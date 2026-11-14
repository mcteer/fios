# Shutdown persistence negative evidence

`persistAtShutdown` has a finite existing shutdown deadline. A zero deadline continues to return without draining or flushing. With a deadline, known independent native/source uncertainty must prevent new cleanup/persistence work.

The candidate uses existing `model_registry_mod.cleanupUncertain` before draining side queues, again after the drain, and after cache-target enumeration before persistence. Thus a known negative observation at any of those edges stops the next stage. It never clears a latch, treats local drain as native completion, changes a model/cache policy or grants admission. This is a negative-evidence repair, not an atomic all-client/device completion contract.

The patch changes only `engines/mlx/cache/budget.zig` over checkpoint3736ed55; preceding startup/stream-close candidates are preserved in the separate composed source tree. The isolated checker reconstructs and byte-compares that budget source and extracts the actual persistence function. CPU-only drain, cache-enumeration, persistence, clock, log and negative-getter substitutes exercise five independent-process scenarios in Debug/ReleaseFast: healthy, pre-existing negative evidence, negative during drain, negative during enumeration and zero deadline. Required outcomes are six designated original failures, four original healthy/deadline passes and ten candidate passes. Simulated uncertainty is never cleared within a scenario.

No model, Metal/ANE object or hardware fault injection is involved. Full linked source/interface checks and receipts remain distinct from whole-native provenance, positive terminal proof, installed runtime authority and separately gated Studio acceptance. Whole-spec task closure requires those outstanding criteria.
