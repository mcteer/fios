# Original preparation receipt and launch-plan binding

The off-loop preparation producer performs one bounded reservation and one
optional readonly lineage lookup. It performs no SQLite access, process spawn,
permission export, retry, automatic withdrawal or native claim release.

Before mutation, it checks request framing, the requested checkpoint and peer
shape. Its once-verified registration binds exact peer identity, epoch,
correlation, UTF-8 model bytes, full-width root, operation, lifetime and original
local request/receipt times. An unavailable/mismatched later lookup does not
throw away that original identity. The result is delivered once; callers retain
it through local storage retries rather than repeating the native operation.

The registration's timing predicate is only a necessary condition. Unknown,
old/future source clock, expiry or local clock rollback cannot become a current
lease. Later persistence or a fresh caller timestamp cannot renew it. A verified
identity can still be stored after the original timing window has expired.
It does not provide current native activity, compatibility, capacity or proof.

The journal checkpoints that original preparation identity against its existing
exact scope/root continuity. Original model bytes must match. Shared identity
validation preserves the existing handoff clock/peer/sequence behavior, retains
newer unknown observations and never makes registration into a live lookup.
These identity-only payloads keep their existing schema; preparation withdrawal
ACKs are not accepted by the old cancelled-handoff proof producer. They do not
resolve inference rows or clear older uncertainty.

An opaque WorkerPreparationBinding additionally requires the original active
launch plan, dispatched scope, committed original root, fresh matching lineage
and original lease timing. It binds the actual plan object and nonce; it creates
no process or bearer permission and cannot be reused for another plan. The
factory's once-only plan consumption and independent source/resource/budget/
native admission checks remain necessary. The broker must revoke on subsequent
source loss; this binding is not a replacement for current source eligibility.

Tests use finite semaphore-controlled native-source ports, never models. Twelve
receipt scenarios exercise held off-loop work, once-only calls/results, lookup
failure/mismatch, clock/expiry, peer and exact Unicode model identity. Genuine
same-process SQL writer contention on an isolated database checks retained
receipt identity, retry without RPC and reopen with both own/older holds intact.
Plan tests reject uncheckpointed roots, missing lineage, another plan and expiry,
without consuming a plan or starting a process. Full Debug/optimized policy/mock
suites cover the existing handoff path after shared identity-validation changes.

This layer is not yet the model-broker/worker preparation mode. The current
Python metadata2/handoff1 path is unchanged. Production execution composition,
owned-preparation observation, the atomic worker transport contract and full
positive native coverage/proof/capacity remain unfinished. No enrollment,
installation, native activation or whole-task closure follows;39/55 remains.
