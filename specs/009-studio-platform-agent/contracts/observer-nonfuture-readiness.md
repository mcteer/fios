# Nonfuture shared-observer readiness

The shared container readiness metadata used by Express and the Python harness must satisfy `0 <= readerNow - checkedAt <= 5000` milliseconds. A timestamp even1ms ahead of the reader is unknown, regardless of otherwise healthy gateway data, matching endpoint fingerprint or an advertised exact model. This enforces the operator's existing readiness rule at the worker/frontend boundary; it grants no native activity or admission authority.

Both readers previously allowed1,000ms of future skew. They now reject `checkedAt > now`. Existing fingerprint, explicit-peer, own-catalog, metadata bounds and status checks remain in place. Unknown observations do not trigger direct peer probing, inference, model loading, fallback or substitution. Native-private protocol clock contracts are separate from this shared-observer schema.

Deterministic-clock regressions exercise both public discovery paths with peer metadata at now, exactly5seconds old,1/500/1,000/1,001ms ahead and5,001ms old. Only gateway health/catalog GETs are permitted; the exact selected alias remains unchanged. The old readers reproduce improper availability at the three future offsets within their former allowance. The current readers accept the inclusive fresh boundaries and reject every future offset.

Python verification uses the installed noneditable package after locked reinstall with uv0.13.5/CPython3.11.17. Component readiness tests and working-tree mock/browser/container results are recorded separately from exact-commit CI and production delivery. No real model request or deployment is part of this correction.
