# Publish the existing Qwen reader after successful construction

The source-only overlay `mlx-serve-qwen-warm-publication.patch` moves the
existing `NgramTable.startWarm()` call to the end of `trunk_load.load`, after
construction of the complete return value. The reader holds `st.table` by
pointer. Previously, MTP loading, the ternary-bias check and conversion of the
owned-weight list could fail after publication and enter the existing table
cleanup, including its unbounded reader join.

GPU selection and calibration remain in their original position. The same
local-layer/rank and GPU/embedded-table predicates gate the one reader start.
The table remains at its final allocated address. No numerical operation,
model ID, native inference implementation, file-read loop or ownership ABI is
added or changed. Successful construction starts warming slightly later;
failed construction starts no warm reader. Earlier allocations and existing
error cleanup remain unchanged.

The exact-parent checker applies and reverses the one-file patch and verifies
that publication follows every explicit fallible operation in the load body.
It also compiles the unaltered load-tail control flow with explicit substitutes
for model/GPU values, MTP/bias errors and owned-list failure. The fixture uses a
real allocated parent and a real reader thread. Injected failures must unwind
without publishing a reader; successful cases preserve local-layer/rank and
GPU/embedded predicates. These are component failure injections, not execution
of a complete failed model load or physical model-data reads.

```sh
.venv/bin/python -I -B scripts/check-platform-qwen-warm-publication.py --isolated --source /private/tmp/REVIEWED_NATIVE_SOURCE --zig /private/tmp/PINNED_ZIG
```

This removes publication from load-error unwinding. It does not bound shutdown
of a successfully constructed table. Returning from `close` while its reader
still holds the table would be unsafe: callers destroy the parent allocation.
Bounded cleanup requires an independently retained worker context or checked
retention through every parent cleanup path. The original sticky uncertainty
and native-admission refusal remain. Full native compile/link and runtime
evidence are recorded separately in validation; no task closes from this
component alone.
