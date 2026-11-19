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

`ModelBroker` commits its local inference claim and worker launch plan, then marks the attempt dispatched before starting the off-loop preparation exchange. That durable mark says the native mutation may have happened; it is deliberately earlier than native effect publication and cannot act as a source lock. The separate native `Tracker.reservePreparation` uses the tracker mutex for exact parent/model association and transition refusal, not a compare-and-hold covering all producers. A positive admission guard would have to validate the original scoped observation and insert a non-preemptive hold in the same source critical section used by conflicting external publication, then keep the hold through dispatch and exact native terminal evidence. Local claim serialization, a preparation root, and a still-current lease cannot individually close that race.

`Tracker.retirementSnapshot` advances the diagnostic capture sequence on read; that sequence is not the mutation revision needed for compare-and-hold. A future receipt must bind to the exact source epoch and one non-reused hold/root, not merely the model identity, latest capture sequence, or a subscriber's successful read. Consuming one receipt must leave sibling holds for the same model intact, including any conflicting-admission fence they impose. The serial model checks those negative edges only; it does not qualify the tracker retirement ring as the receipt producer.

`backendKnownUncertain` deliberately invokes its fixed negative-only getter outside the tracker mutex, then fences on a positive result. A false read may precede a backend gap that has not reached the tracker; neither moving the read closer to reservation nor reading twice makes that transition atomic. Positive authority requires the actual gap producer to publish its fence in the same ordering domain as conflicting admission and hold installation, or the source must remain unsupported. The optional SDK callback hook latches failure in the same atomic cell as readiness. If failure wins during configuration, the initializer cannot publish readiness and fences the tracker; if readiness wins, the failure path forwards the fence. The source-local latch and tracker fence remain distinct observations, so this is neither a census of unhooked producers nor an atomic admission guard. For the reviewed 26.11.2 background-source variant, the readiness overlay is exercised only by `check-platform-current-sdk-readiness.mjs` against exact parent bytes. It is not applied to historical source patches or approved for installation.

The reviewed HTTP host path enrolls a connection before its handler runs. Its primary diagnostic bind occurs after registry resolution and before normal ensure-loaded, followed by a distinct active transition. A candidate guard must protect the canonical bind-to-load boundary; an accepted connection without a resolved target is not idle, and a successful bind is not a backend publication. Early model-less handler return, a persistent connection's teardown, and ending its tracked native work require distinct facts. The existing partial host path explicitly keeps the primary guard disabled; this review does not qualify the other routes or enable it.

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
Validation now also rechecks the serialized journal's dispatched scope, active
launch and original root against a private journal-instance/observation stamp.
Any committed lineage poll conservatively invalidates the captured stamp,
including an unknown reply in the same millisecond. A restarted journal cannot
reconstruct the live stamp. Changed inference state, root or launch also refuses.
This is a local revocation fence, not a fresh native observation or a grant.
The manager must still serialize validation with its launch decision.

Tests use finite semaphore-controlled native-source ports, never models. Twelve
receipt scenarios exercise held off-loop work, once-only calls/results, lookup
failure/mismatch, clock/expiry, peer and exact Unicode model identity. Genuine
same-process SQL writer contention on an isolated database checks retained
receipt identity, retry without RPC and reopen with both own/older holds intact.
Plan tests reject uncheckpointed roots, missing lineage, another plan and expiry,
without consuming a plan or starting a process. Full Debug/optimized policy/mock
suites cover the existing handoff path after shared identity-validation changes.

This reservation layer originally preceded the model-broker/worker mode. The
subsequent [worker preparation client](worker-preparation-client.md) implements
metadata3/preparation1, original-plan/journal-bound observation export, optional
broker/factory wiring and the reserved atomic-consumer header. Caller-supplied
reserved headers still refuse before counting or sending a model POST; task
frames cannot select the preparation identity. Production execution composition
and the positive all-client source/proof/capacity issuer remain unfinished.
These source paths do not authorize enrollment, installation or native activation
and do not close a whole task;39/55 remains.
