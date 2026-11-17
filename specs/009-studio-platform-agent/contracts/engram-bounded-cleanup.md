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
