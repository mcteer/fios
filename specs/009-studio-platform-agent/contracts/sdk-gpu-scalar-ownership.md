# Core SDK GPU scalar ownership check

This explicit development check executes an existing MLX four-element addition
on Core. It adds no numerical implementation, model engine, serving route or
model request. CI must never invoke this hardware check.

The checker binds the selected native source snapshot, repaired SDK build and
20-case SDK composition receipt. It uses the actual native request hooks,
original SDK descriptor and native event ledger. A test observer verifies both
original request tokens at Metal origin and retirement before calling the actual
ledger. The mapped library must match the reviewed private SDK path.

One explicitly owned fixture thread waits with a captured SDK descriptor. The
initiating caller releases both of its root references before allowing that
thread to enter the SDK scope and compute. Both roots must remain represented
while only the captured descriptor retains them. Actual event receipts, correct
numeric output and callback/context cleanup are required before local roots
retire. This tests local request attribution and lifetime; it grants no
all-client coverage, device-wide completion, native reservation or admission.

Each fresh Debug/ReleaseSafe process has a ten-second deadline and a sampled
2GiB process-memory abort threshold. Its four-element graph uses a private
64MiB allocator guideline and disables only its own allocator cache. The
guideline is not a hard GPU quota. Residency refresh is explicitly zero only in
this private child. No installed settings, services, state or model policies
change. Process reaping cannot clear independent native uncertainty.

Run with pinned reviewed private inputs:

```sh
.venv/bin/python -I scripts/check-platform-sdk-gpu-scalar.py --isolated \
  --source ABS_PRIVATE_NATIVE_SOURCE --sdk-work ABS_PRIVATE_SDK_WORK \
  --zig ABS_PINNED_ZIG
```

The source projection and SDK workspace are selected local component evidence,
not whole-native or publisher provenance. This receipt is not a replacement for
the unchanged model prerequisites or a renewal of consumed inference plans.
