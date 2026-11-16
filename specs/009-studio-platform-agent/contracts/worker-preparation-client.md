# Original preparation worker client

Private worker metadata3 adds native_preparation_version1 while retaining
pipe1/handoff1. Current Core accepts strict metadata2 for the legacy handoff
path and strict metadata3 with preparation1; mixed/missing/unknown fields and
unsupported versions refuse. This is protocol support, not native authority.
The complete positive native source issuer remains unfinished.

An original preparation is selected only by the private parent environment's
FIOS_PLATFORM_PREPARATION_ROOT and FIOS_PLATFORM_PREPARATION_CORRELATION. Both
must exist and bind the permission's exact correlation/native instance/model.
The root is a canonical positive full-width UInt64 decimal string. Any partial,
invalid or competing handoff binding refuses. Task frames cannot select these
values, headers, roles or URLs.

The readonly preparation query uses the existing private observe.sock and its
UID/ownership/framing/deadline checks. Its payload has exactly job_id, attempt,
root_sequence and correlation_id. Its response has exactly version, id, ok,
epoch and preparation. Unsupported/unknown responses refuse; global activity
is never a fallback. The observation has exactly these fields:

- version1; host, endpoint_hash, profile_hash, manager_epoch, native_epoch;
- job_id, attempt, canonical_model, native_model, root_sequence, correlation_id;
- source_coverage=all_clients, reservation_sequence, lineage_sequence, native_sequence;
- source_sampled_at, lease_requested_at, lease_expires_at, registry_generation, registry_ready_model.

The subject and selected models must match the original trusted mapping.
Sequences satisfy 0 < reservation < lineage < native, with native at least the
parent's native minimum. Registry generation and interoperable numbers are
bounded; the root remains a string. Original lease length is1..5000ms, source
capture is within that lease and not in the future, and both lease and existing
permission must still be current. Reading cannot renew either. Registry-ready
identity stays distinct from the target and may describe an idle replacement.
A native atomic consumer still independently decides whether the root may attach.

One accepted model POST receives X-Fios-Preparation-Root, its original request
correlation and native instance, with no handoff header. A second request,
unknown scope or caller-supplied reserved header refuses before an actual POST.
No retry, direct inference fallback, tools, SQLite or listener is introduced.
Metadata/import/health operations still invoke no model.

The manager recognizes this readonly query for observer/operator roles and
refuses task/sandbox roles. Its typed observation relay defaults to nil. A checked
observation can be built only from the original binding, current active job and
launch, separate all-client ceiling and coherent native samples. Encoding rechecks
the same journal instance/checkpoint/revision and original lease; any other
unresolved inference refuses, even when native metadata looks fresh. No read
changes an inference row or spent budget. The broker now connects the original preparation producer, checked observation
and factory through explicitly configured trusted ports. The client cannot grant production eligibility: native source guards,
all-client proof/capacity and installed enrollment remain closed. Fixture
responses do not qualify those capabilities or complete T022/T045.

The factory's explicit preparation entry requires metadata3/preparation1, the
original live plan/binding, current checked observation/journal and the original
independent dispatch binding. It consumes once before off-loop Process.run and
sets only the preparation root/correlation environment. The live child retains
the typed preparation identity separately from handoff identity; successful
output, zero POSTs and local reap cannot resolve the registered native claim.
Cancellation before Process.run or withdrawal of the original unused plan
produces local no-spawn evidence only. Its durable acknowledgement reaps the
local launch while retaining native uncertainty and spent history. It cannot
enter the old handoff cancellation/not_sent producer.

The broker's optional preparation mode requires independent all-client coverage
and metadata3/preparation1 before reserving local resources or issuing a native
RPC. It has no handoff fallback. Reservation, lineage and primary capture run
once off-loop; missing observations retain an already verified registration.
The serialized broker commits original identity before construction/spawn and
serves its checked cached observation through TaskController. Generic unknown
activity remains closed for new admission; metadata identity/freshness alone
may retain the original already-bound operation, with the independent source
ceiling and scoped checks still mandatory.

Cancellation or journal-write failure revokes the original plan. The once-only
completion is retained across local write retry and cannot become a delayed
launch. When a native RPC may have happened without an acknowledgement, factory
no-spawn evidence explicitly retains that possible native claim. Its local ack
cannot use the no-native-request branch. Known unused CPU claims may receive
one exact asynchronous withdrawal; its reply is metadata only and does not
resolve an inference. Failure/expiry does not clear ownership. The public
manager leaves preparation mode disabled and source coverage unknown.
