# Optional Engram bounded CPU cleanup

This four-file source increment extends the existing original-custody port.
With `fios_source_sdk`, a serialized parent requests stop, starts one private
joiner and polls its final atomic acknowledgement for at most2s. Thread-start
failure, clock/deadline failure or failed original-scope restoration permanently
latches a distinct cleanup failure and retains the Prefetch allocation, grids,
table references and original descriptor. A late successful join cannot clear
that latch or release quarantined custody. New prefetch publication is refused
after known cleanup failure. Ordinary non-source behavior retains its existing
join path.

The model preflights ahead-reader cleanup before destructive deinit. Plugin
unload checks it before bank/state/weight teardown and rechecks before freeing
outer weights/storage. Prompt replacement and ahead replacement propagate
refusal. Local deferred finish can quarantine a reader after failure; the shared
failure then prevents later enclosing model destruction. The existing serialized
parent/exclusive-model caller precondition remains necessary.

The new latch lives in the existing host-visible SDK utility, using the actual
Shared host/plugin binding. Its value is independent of the existing unproven
participant marker. That older negative marker remains sticky: no coverage,
completion, idle, native resource capacity or admission authority is promoted.
CPU join acknowledgement is solely a storage-lifetime preflight.

The finite checker applies exact pinned parents and compiles actual Prefetch
and model-preflight bodies with real CPU threads, allocators, modeled table IO
and synthetic original host ABI context17. It exercises blocked-read timeout,
late join, retained storage/descriptor, restart refusal, entry/restoration
failure, healthy cleanup and legacy behavior. The modeled parent destruction
edge is not an actual loaded model. Parent compatibility controls invoke its
actual old void finish and must fail the bounded-refusal assertion. Separate
actual host/plugin objects verify one shared latch in both build modes. No
physical backend fault or joiner OS-spawn failure is injected.

```sh
.venv/bin/python -I scripts/check-platform-engram-bounded-cleanup.py \
  --source ABS_PRIVATE_PARENT --zig ABS_PINNED_ZIG
```

Complete native compiler/startup qualification is recorded separately in
[validation](../validation.md). Neither checker nor build grants installed
lifecycle or full all-client acceptance. The patch changes no table arithmetic,
model IDs, generation algorithm or installed policy.

The later `check-platform-engram-native-custody.py` supplement replaces the
synthetic host ABI with the actual selected native tracker and custody module.
Two fixture request roots are retained by the captured descriptor after their
initiating caller clears TLS and releases both references, before table work is
allowed to proceed. Healthy finish releases them; timed-out/late-joined cleanup
retains them. An independently latched native uncertainty also survives otherwise
successful CPU cleanup, keeping its descriptor and both roots. Debug/ReleaseSafe
each run three named cases plus required unnamed import controls.

The table reader remains modeled and the independent backend uncertainty probe
is not enrolled. Fixture-created request roots are not live serving requests.
No model, GPU operation, correlated device terminal proof or native admission
is tested or granted. The source binary is unchanged from the separate build
qualification; this is an additional host-custody test, not a new native profile.

```sh
.venv/bin/python -I scripts/check-platform-engram-native-custody.py \
  --source ABS_PRIVATE_BOUNDED_CANDIDATE --zig ABS_PINNED_ZIG
```

The `--parent-retention` supplement compiles the actual plugin unload body and
model preflight with modeled model resources, using the same actual tracker/
custody ABI and real Prefetch thread. Healthy teardown reaches all modeled
resource edges. On blocked-reader timeout, no such edge is reached, both roots
and the native descriptor remain retained, and a late join cannot authorize a
second unload. The negative control uses the prior unload body with the candidate
helper/resource ports; it is not a pristine prior loaded-model execution. Its
premature cleanup calls must fail the assertion in both modes. No real model,
bank/state/weight destruction, device completion or installed lifecycle occurs.

```sh
.venv/bin/python -I scripts/check-platform-engram-native-custody.py \
  --source ABS_PRIVATE_BOUNDED_CANDIDATE --zig ABS_PINNED_ZIG --parent-retention
```

### Actual host row-read supplement

The additional `engram_native_table.zig.fixture` uses unchanged selected Table
read/deduplication/readAll/advise/Job methods, QuantMode, CRT, Prefetch and real
tracker/custody ABI. It does not use the model opener or GPU dequantizer. A
5120-byte private affine row fixture exercises GCD dispatch, joined CPU threads,
duplicate-row ordering and ordinary bad-row refusal. The captured original
roots outlive caller release until local finish. In a separate diagnostic-only
case, the actual Engram negative getter is enrolled before creating requests;
its real participant-unproven marker is observed after IO. Local join/finish
then retains both roots and the SDK descriptor without inventing a prefetch
cleanup failure or clearing the independent source fence. This is a selected
negative getter, not the complete production backend observation composition.

```sh
.venv/bin/python -I scripts/check-platform-engram-native-table.py \
  --source ABS_PRIVATE_BOUNDED_CANDIDATE --zig ABS_PINNED_ZIG
```

Each case runs separately in Debug/ReleaseSafe, with network denial, finite
compiler/runtime timeout and no linked model/GPU library. Real blocked storage,
model parent cleanup, device terminality and all-client authority remain outside
this component check. Exact receipts are in validation.md; no whole task closes.
