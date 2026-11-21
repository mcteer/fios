# Checked Llama context publication

This source overlay extends the existing optional checked-synchronization shim.
It adds no model engine or serving API. Exact parents are recorded in
`platform/studio/native/native_llama_checked_publication_parents.json`; apply
`mlx-serve-llama-checked-publication.patch` after the preceding qualified overlays.

With `LLAMA_FIOS_CHECKED_SYNC_V1`, context construction must receive exact success
from the target context and, when present, its draft context before returning
the constructed shim context. Failure, unsupported status, or an exception
records the existing sticky uncertainty and returns no context. The retained
parent graph must not be reclaimed by treating this local failure as successful
native terminality. The old-header path retains its prior behavior.

The vendor context constructor can perform scheduler reservation followed by
synchronization. Its ordinary void synchronization does not itself provide the
checked result required here. The extra check covers publication of these two
local contexts only: it does not establish all-client coverage, device idleness,
resident memory authority, request completion, or permission for admission.
The primary guard, source coverage and admission capability remain unchanged.

Run the finite component checker against the exact parent source:

```sh
.venv/bin/python -I scripts/check-platform-llama-checked-publication.py --source /ABS/PRIVATE/PARENT/source
```

The checker extracts the actual constructor and compiles it with synthetic
library status ports. Parent healthy controls, parent missing-check failures,
candidate checked behavior and legacy-header compatibility remain distinct.
The separately recorded complete-shim checks use genuine headers/libraries with
empty metadata parents; neither test invokes a model. Enclosing source builds
and startup checks are recorded separately in validation.md.

Compiler qualification must also distinguish requested parallelism from observed
admission. `scripts/platform-compiler-gate.py` provides a private development-only
two-slot wrapper for pinned compiler root jobs. It is not installed, is not a
supporting service, and supplies no native workload authority. Its finite
metadata-child controls are reproducible with:

```sh
.venv/bin/python -I scripts/check-platform-compiler-gate.py
```

A successful metadata check is not proof that an enclosing native build used the
wrapper. The build must separately bind the compiler, wrapper, configuration and
admission-event log; retain failed runs and unknown cleanup rather than deleting
or reclassifying them. The two-job bound concerns admitted compiler roots, not
all descendant threads or any inference/GPU quota.
