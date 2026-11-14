# Cache-budget revision negative evidence

The existing budget revision may shrink a cache and evict native-backed state. Known independent native/source uncertainty must therefore stop further resolver/setter work and residency publication.

The candidate keeps the existing optional resolver and current-model-last order. Existing dynamic `cleanupUncertain` reads run before taking the registry mutex and before residency publication. Fixed/cached `cleanupUncertainLocked` reads run under that mutex before/after each resolver and after each setter. The mutex now has a scoped deferred unlock so every negative early return releases it before publication or return. No negative latch is cleared. A setter that reports uncertainty may already have partially changed local state; this is retained as uncertain, not rolled back or reported as a complete native transition.

Healthy budgets, grow-only skip behavior, absent resolver and disabled RAM-cache behavior are preserved. No new budget algorithm, model selection, numerical engine, retry or admission authority is introduced.

The patch layers over the preceding shutdown-persistence and idle-flush budget overlays on checkpoint3736ed55. The isolated checker reconstructs all exact budget overlays, compares the file and extracts the actual revision function. CPU registry, resolver, cache setter and publication substitutes plus dynamic/fixed getters assert lock context. Eight independent-process scenarios in Debug/ReleaseFast require eight original failures, eight original healthy/skip successes and sixteen candidate successes. Tests check exact current-model ordering, retained metadata on negative return and released locks; simulated uncertainty is never cleared within a process.

No model, Metal/ANE object or hardware fault is involved. Source/callback checks do not establish whole-native provenance, all-client completion, atomic admission, installed runtime authority or separately gated Studio acceptance. Whole tasks retain those remaining criteria.
