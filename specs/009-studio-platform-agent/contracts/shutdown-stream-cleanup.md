# Shutdown stream-close negative evidence

Scheduler deinitialization already refuses known native/source uncertainty. The inference loop's separate GLM stream-close path must apply the same negative evidence before closing or clearing handles. A void close is not a completion receipt.

The source candidate checks existing `cleanupUncertain` before taking the registry mutex. Within that mutex, it uses only existing fixed/cached `cleanupUncertainLocked` reads before and after each stream close. If uncertainty is known, it returns without clearing the current handle or touching later entries. A later invocation sees the same independently retained fence. It does not clear uncertainty, authorize a model switch or claim native terminality. Healthy close behavior remains unchanged.

The patch layers over the startup-load custody candidate on private checkpoint3736ed55. `check-platform-current-shutdown-cleanup.mjs` reconstructs both overlays and compares all three current source files. It extracts the actual close function and tests it against explicitly substituted CPU registry/stream-close and fixed negative-evidence getters. Healthy, pre-existing-uncertainty and uncertainty-during-close scenarios use separate processes; no scenario clears a simulated latch. Debug/ReleaseFast require four designated original failures, two original healthy successes and six candidate successes. No Metal/ANE object, model or hardware fault injection is involved.

This repairs a known negative-evidence cleanup edge. It does not supply missing all-client census, native proof issuance, atomic admission, installed lifecycle or Studio acceptance. Other shutdown paths remain subject to the whole-spec audit. Installation/activation remain separately gated.
