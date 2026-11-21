# Existing Qwen n-gram warmer: negative source fence

The current native Qwen plugin can read its n-gram table in a background
page-cache warmer after preparation returns. Its worker has no original request
custody port. A quiet request ledger therefore cannot qualify this source as
idle or complete. This fence reports that gap without changing the warmer's
read algorithm, schedules, thread count, model settings or numerical code.

The five-path candidate sets a process-wide atomic immediately before the
existing worker setup/spawn, after the existing absent-region, already-started
and disabled checks. A failed spawn is still negative: it cannot refund a
publication attempt into positive coverage. Worker completion, byte counters,
a new object or a later disabled call cannot reset the latch. There is no reset
API, model call or new wire field.

The plugin and host share one registered `Shared` boolean. Both the fixed
backend getter and serving negative getter consume it. These are negative
reads only, including under existing enclosing locks; they invoke no dynamic
callback, load, synchronization or model operation. No zero/false observation
issues idle, capacity, terminality or admission evidence.

The canonical checker reverses/reapplies the exact five-path patch and verifies
its four parent hashes and one new file. It executes the actual `startWarm`
method with metadata regions and a metadata-only worker on a real thread. It
uses the actual candidate latch declaration, real Shared implementation and
fixed getter. The parent receives that latch declaration only to isolate its
missing pre-spawn write. Named runtime failures, disabled/absent controls and
sticky-after-completion cases run in fresh network-denied processes. Optional
`--shared-units` compiles a separate plugin object and host to check real storage
sharing in Debug and ReleaseSafe. Zero selected tests cannot pass.

This does not execute real table IO, a Qwen model or native inference. Full
native semantic/link/unit and empty-model integration results must be recorded
independently. Current native all-client coverage and admission remain closed;
the actual warmer ownership and bounded parent cleanup still need engineering
and acceptance. No package enrollment, installed change or whole-task closure
follows from this negative source fence.
