# Qwen page-cache warm original request custody

This source-only T018/T021 component captures the original host request group before the existing optional page-cache warm thread is published. The Fios SDK profile enters/restores that group around the existing worker. Missing origin or failed entry refuses page IO. Close retains the group through the original local join before requesting descriptor release; failed restoration quarantines the host descriptor. A failed spawn requests release without inventing work completion. Legacy compilation excludes all five custody ABI functions.

The existing independent Qwen negative fence remains sticky. This does not bound join, port all pool/map/model cleanup, prove native terminality, enable admission or install anything. Captured custody describes this IO worker only; it does not prove physical residency or resource availability. Existing model numerics, gather/read policy, progress, file regions, model IDs and warm scheduling remain.

The checker compiles the actual warm fields and warmRegion/startWarm/warmMain/close methods with real threads, the real timestamp code and 8MiB scratch constant. Table/resource ports, pread, logging and host custody calls are explicitly modeled; no real table, mapping, file descriptor, model or native proof is exercised. Debug/ReleaseSafe test original custody through close, missing/failed scopes, absent/disabled warm, legacy behavior and duplicate-start controls. Separate objects remove modeled custody exports to check legacy exclusion and the exact opted-in five-symbol dependency. Enclosing actual native compilation/link/runtime evidence remains a separate scope.

```sh
.venv/bin/python -I -B scripts/check-platform-qwen-warm-origins.py --isolated --source /private/tmp/PRIVATE_NATIVE_SOURCE --zig /private/tmp/PINNED_ZIG
```

Selected source qualification passes36 canonical records, enabled35/35 semantic and32/32 link steps, unit-boundary validation and four private empty-model/current StudioCore checks. No whole task is closed;39/55 complete. Public startup/native admission, installed lifecycle and both-Studio acceptance remain separately unfinished.


## Real descriptor IO supplement

`check-platform-qwen-real-io.py --isolated --source ABS_CURRENT_SOURCE --zig
ABS_PINNED_ZIG` renders the exact current warm fields,8MiB scratch constant and
warmRegion/startWarm/warmMain/close bodies, then links the real host custody ABI
and selected SDK. A private16MiB sparse file is read through actual libc pread;
the test gate forwards to that real operation and close forwards to libc close.
No model/table-format parser, weights, GPU mapping or numerical inference runs.
Pool/embedded ports are inactive resource fixtures and progress logging is
suppressed; these limits are explicit in the receipt.

Twelve Debug/ReleaseSafe stages cover the same methods with ownership disabled
in a test profile (genuine expected failure, not pristine upstream), normal
original-root retention across two reads/join/close, missing-origin refusal
before IO, independent uncertainty after actual read/join, close while a read is
held, and restored normal behavior. Original context is observed on the actual
IO thread. Local joins/close never erase independent uncertainty.

This supplements the earlier modeled-IO checker; it does not prove physical SSD
access, page-cache residency, resource availability, bounded join, complete pool/
map/model cleanup or native terminal/admission authority. Native source/libraries
and serving settings are unchanged. Full all-client/Studio acceptance remains
open. Initial duplicate Shared module ownership and old integer open-flag syntax
failed before IO; retained corrected projections use the actual host-owned Shared
utility and current packed flags.
