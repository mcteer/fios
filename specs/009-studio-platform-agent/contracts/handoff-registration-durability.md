# Preserve registration identity when a later lookup fails

The native handoff preparation sequence registers an original root, then reads
its lineage. These are separate bounded calls. A successful authenticated
registration must not disappear when the subsequent readonly lookup is
unavailable or contradicts that registration.

`PendingNativeHandoff` first validates the registration's original peer,
instance, correlation, root and sequence. It retains that reply with optional
validated lineage. A failed registration remains failure; failed lineage yields
registration-only metadata. Neither outcome supplies native admission or model
completion authority.

Before inspecting optional lineage or launching a worker, the broker durably
records the registration against the original dispatched/uncertain scope.
`NativeRequestLineageConsumer.acceptRegistration` checks the original peer,
instance/correlation, pending/register state, uncertainty, clock and sequence
bounds. Root changes fence continuity. A late same-root registration preserves
a newer readonly checkpoint instead of rewinding it. Existing fences cannot be
cleared. Full-width root IDs remain canonical decimal strings.

The checkpoint uses the existing version1 identity format. It is not a live
lineage observation or a terminal receipt, and makes no state/budget/ownership
transition. A nil lineage stops the broker before the worker factory. The
known-unstarted local launch is reaped and its local reservation released;
native uncertainty and spent history remain. No native cancellation, completion
or automatic retry follows from registration-only metadata.

The regression first fails on the original coordinator discarding its verified
root. Debug/optimized suites exercise mismatched lineage, lookup failure and
mid-registration cancellation without spawn, plus registration shape/freshness,
changed-root fencing, checkpoint restoration and newer-readonly ordering.

The private native driver additionally supports:

```sh
node scripts/check-platform-native-handoff.mjs --isolated --capsule /private/tmp/REVIEWED_CAPSULE --sha256 REVIEWED_CAPSULE_SHA256 --preparation-failure
```

This uses a genuine authenticated native registration and actual broker/journal
while injecting only the follow-up lookup failure. Synthetic advisory/capacity
inputs permit the coordination fixture; they do not establish native capacity
or coverage. A real readonly verification lookup is deliberately not persisted,
so restart must recover the root from the registration checkpoint alone. Own
and older independent uncertainty remain, with no model POST or worker grant.
The selected image is private/empty-catalog and is never installed or activated.

### Local storage outage

The preparation retains its once-only completed result until original identity
and the known-unstarted local marker commit. A storage error revokes that
pending launch and keeps its local reservation. Recovery retries local writes;
it never repeats registration, refreshes permission bytes or starts a delayed
worker. Source/storage loss can revoke the job; a sandbox model-only cancel
retains its distinct behavior and does not revoke the whole sandbox job.

An opaque, nonserializable registration value is minted only after the private
producer validates peer/instance/correlation/root and receipt-time freshness.
Its captured receipt time permits storing original identity after a local
outage. It cannot supply fresh lineage or admission: ordinary raw observations
retain their freshness checks, old checkpoints remain identity-only, and a
revoked preparation cannot start a worker. Newer unknown samples can coexist
with original identity without becoming live observations or rewinding clocks.

The separate native fixture mode is:

```sh
node scripts/check-platform-native-handoff.mjs --isolated --capsule /private/tmp/REVIEWED_CAPSULE --sha256 REVIEWED_CAPSULE_SHA256 --preparation-storage-failure
```

It injects finite same-process writer contention in a disposable platform
journal, then advances only the fixture consumer clock by6000ms. That time
advance tests stale identity storage; it is not a measured six-second outage.
The native peer's actual registration remains unchanged. No second manager,
Fios database, native installation or inference is involved.

This repairs identity durability at these RPC/local-write boundaries. It does
not supply the unfinished normalized producer, positive native proof issuer or
atomic dispatch guard, nor qualify arbitrary I/O failure or complete crash
recovery. T021 and whole-task completion remain open; exact evidence belongs in
validation.
