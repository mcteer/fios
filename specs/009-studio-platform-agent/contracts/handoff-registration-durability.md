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

This repairs identity durability at that RPC boundary. It does not supply the
unfinished normalized producer, positive native proof issuer or atomic dispatch
guard, nor qualify storage-failure retry or complete crash recovery. T021 and
whole-task completion remain open; exact evidence belongs in validation.
