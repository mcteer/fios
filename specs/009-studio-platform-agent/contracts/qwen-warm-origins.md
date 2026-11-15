# Qwen page-cache warm original request custody

This source-only T018/T021 component captures the original host request group before the existing optional page-cache warm thread is published. The Fios SDK profile enters/restores that group around the existing worker. Missing origin or failed entry refuses page IO. Close retains the group through the original local join before requesting descriptor release; failed restoration quarantines the host descriptor. A failed spawn requests release without inventing work completion. Legacy compilation excludes all five custody ABI functions.

The existing independent Qwen negative fence remains sticky. This does not bound join, port all pool/map/model cleanup, prove native terminality, enable admission or install anything. Captured custody describes this IO worker only; it does not prove physical residency or resource availability. Existing model numerics, gather/read policy, progress, file regions, model IDs and warm scheduling remain.

The checker compiles the actual warm fields and warmRegion/startWarm/warmMain/close methods with real threads, the real timestamp code and 8MiB scratch constant. Table/resource ports, pread, logging and host custody calls are explicitly modeled; no real table, mapping, file descriptor, model or native proof is exercised. Debug/ReleaseSafe test original custody through close, missing/failed scopes, absent/disabled warm, legacy behavior and duplicate-start controls. Separate objects remove modeled custody exports to check legacy exclusion and the exact opted-in five-symbol dependency. Enclosing actual native compilation/link/runtime evidence remains a separate scope.

```sh
.venv/bin/python -I -B scripts/check-platform-qwen-warm-origins.py --isolated --source /private/tmp/PRIVATE_NATIVE_SOURCE --zig /private/tmp/PINNED_ZIG
```

Selected source qualification passes36 canonical records, enabled35/35 semantic and32/32 link steps, unit-boundary validation and four private empty-model/current StudioCore checks. No whole task is closed;39/55 complete. Public startup/native admission, installed lifecycle and both-Studio acceptance remain separately unfinished.
