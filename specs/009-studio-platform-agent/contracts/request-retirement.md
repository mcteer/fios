# Correlated local request retirement

This connects a missing reconciliation input: live lineage previously disappeared
when its final reference was released. Absence remains unknown. A distinct,
bounded local history now records the original correlation and root after every
slot/descendant for that root has released its references. It is not native
completion, not-sent evidence, all-client coverage or admission authority.

The tracker stores256 records in a ring. Source-local retirement sequences never
wrap; exhaustion fences uncertainty. Eviction discards history, never a claim.
Queries bind both correlation and original full-width root, so slot/correlation
reuse cannot substitute a newer request. Independent uncertainty remains sticky.
The mutex covers the final slot release and record publication, with no IO,
backend callbacks or allocation inside that operation.

The readonly private FIE9/FIZ9 exchange is64/88 bytes. It binds source instance,
correlation, root, capture sequence, local retirement sequence and explicit
recorded/uncertain flags. Missing, malformed, foreign-instance, stale or replayed
records provide no accepted observation. It supplies no process/lifecycle action.

Swift requires the original root to have been observed live first. Journal
observation persists the existing root/peer/replay checkpoint before returning
local metadata. It never changes inference state or releases a reservation.
Manager restart still makes dispatched work uncertain; a later local retirement
record cannot clear that uncertainty. Native terminal reconciliation requires a
separate genuine native proof issuer.

The existing ingress companion patch remains immutable. A separate companion
increment reproduces the current standalone source modules; a distinct overlay
ports the tracker to current3736ed55 host Shared storage and another ports its
protocol/transport. No new global storage or model engine is introduced.

Validation covers canonical tracker/protocol units, current host-module units,
strict Swift wire/consumer/journal tests and an actual source Unix bridge with
four separate Swift client/journal lifetimes. The latter exercises live root,
root release with retained child, final local release and independent fencing.
All activity is CPU metadata; it does not simulate successful native inference
by relabeling local completion. Full-image qualification is recorded separately.

The remaining handoff gap is explicit: a fast request can finish before the
manager ever observes its root live. The manager must not adopt a root inferred
from aggregate counters. A source-bound, once-only handoff must establish the
original request identity before a POST can occur, preserve it across manager
restart, and distinguish atomic pre-handoff refusal from uncertain dispatch.
That handoff and genuine native-completion reconciliation are not implemented by
this local-history increment and remain required before production admission.
