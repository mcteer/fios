# Optional source checked synchronization status

The pinned b11429 source exposes `llama_synchronize` as void. Its Metal
implementation can retain `has_error` after checking command buffers, without
returning that status through the public call. The current shim's ordinary void
wait therefore cannot supply a checked result before context destruction. This
source finding is bound to commit d81235049384534c167caea52b85a694f6103d14; the
staged release label alone does not attest how its prebuilt binary was built.

The additive source ABI declares `LLAMA_FIOS_CHECKED_SYNC_V1` and
`llama_fios_synchronize_checked_v1`. With the vendor's exclusive-context caller
precondition, it classifies every backend before synchronizing. Known synchronous
CPU is supported; the Metal callback returns its existing reported error state
following synchronization, and the synchronous BLAS callback also requires its
helper futures to be joined. Unsupported backends, invalid status, exceptions or
prior failure return0 and latch the context permanently. Null context returns0.
No read can clear that latch.

An optional new-header shim path checks both target and draft before destroying
any batch, backend context or enclosing parent reference. Nonpositive status
retains those resources and the existing independent source uncertainty. There
is no void-API fallback after a checked failure. Prior headers retain the
existing ordinary behavior. No numerical implementation, model selection or
installed configuration changes.

This API reports local known synchronization status. It is not all-client
coverage, an original-request terminal proof, device-wide quiescence, resource
capacity or native admission. Other lifecycle and source-contract work remains.

The finite source checker applies the exact seven-file vendor and one-file
native increments against pinned parents. It extracts actual methods/cleanup
bodies and compiles them with declared synthetic CPU/backend ports. Its modeled
failures do not inject a device fault or prove physical backend behavior. The
new/prior header paths remain separate. CI never runs a model or live host.

```sh
.venv/bin/python -I scripts/check-platform-llama-checked-sync.py --isolated \
  --vendor-source ABS_PINNED_PRIVATE_VENDOR_PARENT \
  --native-source ABS_PINNED_PRIVATE_NATIVE_PARENT
```

The separate private source build follows the upstream static archive merge,
keeps CPU/Metal/Apple BLAS and embedded kernels, and uses only two compiler jobs.
Tracked-source snapshots, exports and real empty metadata/ABI controls remain
selected build/component evidence, not installed or publisher authenticity.
See the exact results and failures in [validation](../validation.md).

Source references: [public synchronization declaration](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/include/llama.h),
[Metal synchronization](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/ggml/src/ggml-metal/ggml-metal-context.m),
[BLAS execution](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/ggml/src/ggml-blas/ggml-blas.cpp).

A separate optional `mlx-serve-llama-checked-decode.patch` applies after the
checked-cleanup increment. Target decode checks the local synchronization status
before advancing positions or entering dependent draft catch-up. Each draft
step checks before reading logits/hidden output, recording a draft token or
trimming its speculative KV range. Failure uses the existing sticky uncertainty
path and performs no void-status fallback. Prior headers preserve their original
path. This adds no numerical operations or inference engine.

`check-platform-llama-checked-decode.py --native-source ABS_PRIVATE_CHECKED_PARENT`
extracts both actual function bodies against a pinned parent. Synthetic ports
exercise successful status, zero, negative and invalid positive status in Debug
and optimized builds; failed calls cannot re-enter decode. Original parent
bodies must fail the same failure assertions. This is local control-flow evidence,
not a real model, physical error injection, all-client completion or admission.
