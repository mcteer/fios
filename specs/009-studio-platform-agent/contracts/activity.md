# Authoritative activity and future008 consumer contract v1

## Required source capability (G2)

The installed native serving boundary must supply trustworthy, coherent observations covering **every enabled inference path and client**, including direct native, LAN-tunnelled and manager requests. Count or conservatively represent ingress/preparation/loading, queued work, compute and response delivery. Include server instance identity, monotonic sequence/sample age, model identity/ownership and transitional/unknown state. No prompt/result/client-private content is required or exported.

Sampled scheduler gauges, multiple independent catalog/metrics GETs, loaded flags, process liveness, GPU utilization and manager ledgers are not by themselves sufficient. Existing26.10.3 source is candidate research, not an attested source satisfying this contract. Source-only native integration/testing is already authorized. Native installation/activation, privileged/disruptive acceptance and real inference remain separately gated; never scrape denied LAN routes or inject into the server.

Native protection must prevent different-model work from evicting/invalidating active ownership across snapshot→dispatch races, including work from bypass clients. It must cover queued/preparing/stream-delivery ownership, not only a decoding GPU slot. Additional same-model requests may share a resident model within native capacity. Native on-demand loading may replace an idle resident model. A loaded-only option is not required. The native boundary must reject or safely defer a different-model request while conflicting active ownership remains, without displacing it. A catalog recheck is advisory, not an atomic lease.

## Export

A version1 observation≤64KiB contains host, enrolled endpoint SHA256, manager epoch/sequence, native instance/sequence, sampled UTCms, source age, coverage `all_clients|unknown|unsupported`, resident exact identity or null, bounded per-model activity counts, preparation/transition flags, resources/service state and fixed safe reason. Per-model list≤64 entries, each counter0..2147483647; overflow or contradictory counts yields unknown rather than truncating to an idle-looking view. Multiple residents invalidate the configured single-model host.

Poll/sample every2s. Consumer rejects observations>5s old,>1s future, wrong host/endpoint/profile/native generation, repeated/regressing sequence after reconnect, unknown schema, missing fields or invalid numbers. A signed/authenticated transport does not excuse stale data. On reconnect/restart, obtain fresh epoch evidence before accepting sequence resets; never revive a cached idle snapshot.

`idle` requires all-client coverage, coherent absence of ingress/loading/queue/active/response ownership, no transitional native state and no unresolved local ownership incompatible with that proof. Unknown coverage is explicit and cannot pass SC-002/008. Busy attribution may be withheld if model identity is unknown; such a host is ineligible for conflicting requests.

### Source coherence implementation checkpoint

`NativeActivityCoherence` is an internal pure source-adapter component, not a new wire schema or an installed adapter. It accepts five disjoint ownership phases (ingress, preparation, queue, compute, response), global totals, unattributed counts, up to64 exact-byte model entries and a transition flag. Every count and the aggregate ownership sum must fit0..2147483647. Totals must exactly equal per-model plus unattributed counts; repeated byte identities, malformed IDs, more than one resident, conflicting busy/resident models, multiple busy models, transitions or unattributed ownership produce unknown with no exported ownership number. Unknown is never presented as zero. Preparation/ingress takes precedence over active/response, which takes precedence over queued; slow-reader response ownership remains active. These counts require a coherent source capture; the normalizer does not make separately sampled counters coherent.

Effective coverage is bounded by an independently reviewed code-only source ceiling. A frame's `all_clients` claim cannot raise unknown/unsupported source coverage. The existing compact `ObservationValidator` now defaults to an unknown ceiling and compares native generations by exact UTF-8 bytes; explicit all-client construction is currently synthetic test enrollment only. Its compact legacy schema is unchanged and does not yet carry this detailed phase model. Identity, freshness, monotonic sequence, durable local ownership and native atomic admission remain separate required checks; the pure normalizer cannot authorize dispatch by itself. No production source ceiling is issued by this checkpoint.

## Owned requests and reconciliation

Before every actual manager-originated model POST persist one `(job_id,attempt)` record. Release it only on correlated native terminal proof, fully processed correlated response with completion evidence, proven non-dispatch, or authoritative same-instance quiescence including ingress/queued work. Disconnect, cancellation, worker exit, process restart, residency or elapsed time alone do not prove native completion. Completing a newer request never clears an older uncertain row.

Server epoch change invalidates old snapshots. Establish old process termination and absence of surviving compute/children before declaring its ownership quiescent; new health alone is not enough. If proof cannot be obtained, retain uncertain ownership and block conflicts. Native external clients are covered by the source, not forged into the manager-owned ledger.

## What future008 receives

A readonly adapter fixture and contract give008 host/model/endpoint-bound activity and native-compatibility evidence. Activity is selection evidence, not a transferable lease.008 must still implement durable per-POST permission and its own routing budgets/context/UI. An idle cold-capable host may be preferred over busy warm reuse by008;009's task worker does not implement008 routing policy; it may use ordinary on-demand inference for an explicitly authorized exact target within its resource envelope. No changes to008 source or activation are part of009.

## Required tests

Idle; ready-but-preparing before scheduler enqueue; direct/tunnelled/manager requests; queued/prefill/streaming/slow-reader response; overlapping same-model completion; busy different-model race; external arrival between snapshot and dispatch; cancellation with compute continuing; manager/native restart; delayed/replayed/mismatched/overflowed observations; multi-resident contradiction; unsupported modality; source outage; old uncertain row surviving a successful new request; idle replacement and busy-conflict admission races. Both Studios need separately authorized evidence, not just mocks.
