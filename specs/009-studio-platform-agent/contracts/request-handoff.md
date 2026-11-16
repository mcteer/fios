# Original native request handoff

This source increment establishes a request identity before a worker can POST.
It does not grant model admission, infer idle or certify device completion.
Production worker/factory activation and native proof reconciliation remain gated.

The native tracker can register at most32 pending original roots within its
existing256-owner bound. Registration carries only correlation and source-created
identity; it selects no model, URL, role, executable or lifecycle operation.
Pending roots cannot bind a model or acquire callback references. The manager
can observe/checkpoint the original live root before handing anything to a worker.
The journal's root lookup is original identity only, not fresh authorization.

Only the explicit handoff association can consume that registration. It checks
correlation and original root under the same mutex which cancels registrations.
The incoming native HTTP owner receives the original correlation root before the
registration reference is dropped. A cancelled, consumed, absent or evicted root
cannot fall back to ordinary association. Legacy requests remain independent.

The fixed `X-Fios-Handoff-Root` header is a canonical nonzero decimal UInt64.
It requires the existing explicit native-instance and request-ID headers. Parsing
and native association precede model handling. Mismatch returns a static refusal;
there is no fallback to another target, legacy association or another process.
This header is identity data, not authentication or native admission authority.

The private64/88-byte FIJ9/FIK9 exchange has only register/cancel operations,
fixed source/correlation/root/operation binding, a monotonic capture sequence and
explicit pending/handed-off/cancelled/unknown state. Wrong instance or malformed
frames perform no handoff action. Existing native private UID checks and Swift
kernel/image verification apply. No task/operator JSON selects a socket or PID.

Cancellation can remove only an unconsumed original registration. If incoming
association won the mutex, the work remains independently owned. Source loss,
uncertainty and missing history remain unknown. Historical cancellation is
bounded; eviction never manufactures a positive result. Even after eviction,
a late request naming the old original root cannot consume a newer registration.
No timer releases a pending root or clears native uncertainty.

The typed cancellation acknowledgement is not wired to resolve inference claims.
The production worker must bind its fixed POST to the registered original root,
and a separately reviewed proof issuer/reconciler must validate non-dispatch or
native completion before releasing that claim. HTTP errors, local retirement,
registration and child exit alone remain insufficient. All-client coverage,
physical completion, installation and Studio acceptance remain separate.

Validation distinguishes deterministic orderings,32 actual two-thread races,
strict header/wire checks, current native source-module tests and full-image/
HTTP/Swift-journal integration. Model-free empty-catalog requests are separate
from real model inference. See validation.md for executed evidence and limits.


The private worker factory now accepts an optional `WorkerHandoffBinding` captured
from the original live, once-only launch plan and its already-dispatched,
checkpointed native root. It validates the exact scope and peer before launch,
passes only the root and derived correlation through the sanitized private child
environment, and carries that binding through launch ownership transfer. The
installed Python transport validates the full UInt64 decimal root, exact command
correlation, native epoch and model before adding `X-Fios-Handoff-Root` to its
single permitted POST. Partial or invalid bindings fail closed; supplied request
headers cannot override the parent identity.

For a bound handoff, child no-spawn, zero-POST, completion and reap release no
independent native claim. Durable terminal native evidence, if separately
accepted, is preserved when subsequent child cancellation/output arrives. The
legacy unbound fixture path retains its existing local not-sent transition.
This binding API does not itself create native proof. The subsequent coordinator
composition below supplies root acquisition; production enrollment and all-client
proof remain open.


The ModelBroker now has an optional trusted `NativeHandoffPreparing` port. With
that port it checkpoints dispatched intent before beginning one off-loop native
registration followed by one lineage read. Both replies must bind the original
peer, instance, correlation, full-width root and increasing native sequence. The
serialized coordinator checks age, lease and source, persists the original live
root, and captures the launch binding before invoking the worker factory. Its
preparation participates in the existing two-worker resource reservation and
active-launch accounting. The manager supplies this port only from its existing
internal native-control client; public observation-only startup supplies none.

Cancellation/source loss while preparation runs never spawns a child. Failed,
stale or mismatched replies release only the known-unstarted local launch slot;
the dispatched native claim stays uncertain because registration may have
succeeded. No automatic cancellation ACK, absent lineage, worker exit or counter
is treated as native completion. Source retention allows this request's own
preparation after initial admission, rather than mistaking its root for a new
conflicting dispatch. The atomic all-client guard and proof issuer remain open;
this wiring supplies neither admission authority nor production enrollment.
