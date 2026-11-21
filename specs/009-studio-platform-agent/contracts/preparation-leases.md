# Single-use preparation lease bridge

This source layer connects the existing exact registry/CPU claim to a bounded
single-use handle. It is an internal bridge, not an authenticated dispatch wire,
capacity reservation, positive completion issuer or all-client authority.
Production source still refuses through `UnsupportedSourceGuard`; the layer does
not change `primary_guard`, activate a service or invoke a model.

At most32 outstanding entries retain original native tokens, exact UTF-8 model
bytes, correlation, source instance and root sequence. A lease lasts at most5s.
The real ModelRegistry wrapper supplies its own boot monotonic time, including
suspend where supported; callers do not supply wall-clock timestamps. The table
independently fences time rollback. Fixed backend probes run before locks;
metadata lock order is lease→registry→tracker, with no load, device wait, dynamic
callback or network operation under those locks.

Attachment validates the original handle and exact target, then consumes the
entry before calling the generation-bound native attachment. A failure can occur
after a native mutation; it must not permit replay or withdrawal. Successful
attachment leaves the incoming original owner alive and drops only the table's
own original claim reference. A subsequent completion, child exit or lease
expiration cannot clear that incoming owner or independent uncertainty.

Expiration never releases ownership. An explicit withdrawal delegates to the
existing exact unattached tracker check, which refuses attached/forked/uncertain
claims. Successful withdrawal frees only that entry; stale handles cannot name a
later root even when a table slot is reused. There is no timeout sweeper or
process-restart reconciliation inference.

The isolated checker reverses/reapplies the exact two-file parent projection,
checks the module against the proposed overlay and copies the actual tracker and
registry-helper dependency closure. Registry entries are explicit CPU metadata
fixtures; no model is loaded. Cases cover capacity, identity/replay, expiration, exact withdrawal, unsupported guards, sticky uncertainty and competing ingress threads. Each named case runs in a fresh process to avoid
unrelated imported tests sharing the process-global tracker. Review-only output
contains no compiler outcomes. Full native build and real ModelRegistry stub
execution are separate qualifications, not implied by component success.

```sh
python3 scripts/check-platform-preparation-leases.py \
  --source /private/tmp/REVIEWED_SOURCE \
  --zig /private/tmp/PINNED_ZIG
```

T022 remains open: the native transport/serving consumer, complete source
coverage, positive native proof and enrolled operational composition are still
required. Whole39/55 remains unchanged.

The proposed separate `FIP9` codec uses one1104-byte request and88-byte reply.
It requires explicit source instance, nonzero correlation, exact padded model
bytes, operation-specific root/lifetime and zero reserved bytes. It delegates
only to a fixed source interface; malformed/foreign/unavailable requests cannot
become a fallback. Acknowledged withdrawal is not a native not-sent receipt.
The codec is component-tested separately with `--protocol`; authenticated Unix
transport and serving consumption are not yet connected by this increment.
