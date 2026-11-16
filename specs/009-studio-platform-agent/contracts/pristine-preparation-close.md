# Pristine preparation closure — implementation in progress

Existing withdrawal removes an exact CPU bookkeeping reference. Historical
retains may already have retired, so current reference counts cannot establish
that the reservation was never exposed. Its acknowledgement remains unqualified.

The private native source adds monotonic retention history and a separate
atomic close for a reservation that remains unconsumed and never shared. Scalar,
union and queued reference acquisition mark that history before publication;
reference release never resets it. The lease and tracker locks serialize close
against attachment. Wrong identity, consumed/attached state, any historical
sharing, independent uncertainty and replay refuse. Ordinary withdrawal retains
its existing weaker cleanup semantics.

The native primitive returns no standalone inference proof. The serving guard
remains false; production composition, installation and model effects remain
closed. CPU tests use the actual tracker and lease code with a fixture registry,
not models or a qualified all-client source.

The distinct operation uses FIP9 version2/op3 and FIV9 version2/op3. Version1
reserve/withdraw remain unchanged. Mixed versions/operations refuse before the
source callback. A missing optional close callback refuses; installed observation
mode still denies every preparation frame before dispatch. The serving callback
passes through the original registry's lease table. It never enables the serving
primary guard.

The Core client has a separate closure/sample type and strict decoder. Its
bounded reply checks preserve peer authentication at the existing Unix exchange,
exact process epoch/correlation/root/model, increasing sample sequence and clock
quality. An old acknowledgement cannot decode as a pristine closure, or vice
versa. Unknown source clock remains unknown. This type is CPU metadata only;
there is no conversion to native inference proof.

Source review finds the sole serving consumer in the chat router: it consumes
the exact JSON model's lease before scheduler.ensureLoaded. The lease records
consumption before tracker attachment, including attachment failure. Reference
acquisition in scalar, union and queued paths records retention before exposing
references. The lease lock precedes tracker locking for both close and attach.
That review does not qualify other backend/client routes or device completion.

The Core coordinator now has an isolated compound decision path. It accepts
only the original factory's opaque metadata3 never-spawned evidence with a
preparation binding, matching journal scope/root/peer, no worker grant and a
durable local reap marker. It commits a version4 lineage checkpoint marked
`attempted` before sending at most one close request. Existing version1–3
readers reject this new decision format; the SQLite schema version stays9.

A fresh exact version2/op3 close from the same peer may then resolve only that
original scope as `not_sent`, atomically with its version4 receipt. Missing,
foreign, stale, replayed or unknown-clock replies preserve uncertainty. A
storage error retains the original in-memory reply without repeating the RPC.
A restart retains `attempted` and cannot reconstruct permission to resend. The
standalone CPU acknowledgement, missing lineage, HTTP completion, process exit
and reference zero remain insufficient. Other inference records are untouched.

The coordinator covers never-spawned workers only. Broker cancellation now
uses it when the configured preparation source supports the distinct operation.
A cleanup-only binding can preserve authenticated historical identity without
live lineage or a current lease; it cannot produce launch observations or worker
permission. Sources without this operation retain ordinary weaker cleanup.
Refusal of a strong close never triggers another close request or upgrades a
weak withdrawal reply. Checked zero-POST/reaped preparation workers remain
unfinished. Manual model cancellation preserves the enclosing job; automatic
source/storage revocation records separate job-revocation intent.
The serving guard, production composition, installation and model effects stay
closed. This source/component increment does not complete T002 or T021.
