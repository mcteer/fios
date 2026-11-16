# Explicit private native background exclusion build

This source increment connects the previously tested C++ constructor mode to
both executable and unit-test roots through `-Dfios-source-background-seal=true`.
The flag requires the existing private source-SDK composition and its source-only
version suffix. The default remains false. It does not set or rewrite any
MLX/model configuration, enable the serving guard or qualify model effects.

The isolated Core fixture selects an empty catalog and performs two separate
bounded starts. With the ordinary refresh default it requires startup refusal
from the sealed SDK hook. A second private child explicitly uses interval0 and
must serve health/empty catalog/control metadata while reporting no untracked
refresh participant. The fixture still reports unknown coverage and no native
admission authority. A successful seal is not all-client inference coverage,
resource completeness, device terminality or an installed policy.

The new checker independently reconstructs both the constructor and build-file
patches from pinned local parent hashes and validates a model-free private
capsule before any execution. An ordinary capsule without the build declaration
refuses before launch. Source and helper bytes are rechecked after the fixture.

No current installed profile selects this build, no model is loaded or requested,
and no production/native setting changes. Strict35/32/20 compile graphs and the full-process startup fixture pass. The
specific missing-SDK build guard also refuses as expected; its first attempted
control stopped on a missing WebP argument and is excluded. The default-option build and ordinary startup/manager-background regressions also pass; the strict checker rejects that unsealed artifact before launch. None of this closes a whole task or qualifies
positive all-client/native admission.
