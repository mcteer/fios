# Spec009 completion status

Updated2026-11-16. **39/55 whole tasks complete;16 open.**

The central missing capability is a trustworthy, atomic native admission and
completion boundary. Current source provides ownership tracking, conservative
refusal, partial diagnostics and original-request handoff. It does not yet
provide a working positive all-client admission path. A fresh catalog, zero
counters, HTTP completion, child exit or local thread join cannot substitute for
that boundary.

This is why the task count has stayed at39 despite many source changes and
passing component tests. Individual ownership/lifetime repairs have accumulated,
but the normalized producer, positive completion issuer and atomic native guard
remain unfinished. Other tasks depend on those capabilities. The remaining work
is larger than an acceptance-test pass or a final packaging step.

Fios remains a frontend/backend for existing MLX-Serve. The native patches add
ownership, refusal and lifecycle integration around existing implementations;
they do not introduce model engines or numerical algorithms. Spec009 adds a
separately gated Studio management boundary. Spec008 routing remains parked.

| Remaining work | Tasks | Required outcome |
| --- | --- | --- |
| Native authority | T002, T018–T022 | Audited enabled-route/backend coverage; trusted all-client normalized activity; original-request terminal/non-dispatch and process-epoch reconciliation; an atomic non-preemptive guard across native preparation and dispatch. Current negative-only and component paths are insufficient. |
| Operational integration | T008, T009, T027, T028, T030, T036, T045 | Complete enrolled resource/runtime composition; desired/observed service reconciliation; bounded drain/force and full lifecycle integration; sandbox and private-worker task wiring through the native boundary. |
| Protected installation | T049 | Actual reviewed artifact/configuration installation, switching, rollback and removal. Present tooling reviews and stages private data; it does not implement protected installation. |
| Acceptance and delivery | T051, T055 | Separately approved scenarios on both Studios, final functional review, approved PR merge, exact merged-main CI and observed automatic application deployment. App delivery and native acceptance are separate. |

Source engineering and isolated functional tests remain authorized. Work should
continue without another request for that scope. Current Studio installation,
activation and disruptive acceptance remain separately gated. Small-model Core
results do not satisfy Studio acceptance. The settled sandbox approval covers
the exact image only.

Earlier continuation work repairs load-error reader publication and tests a
bounded reader-join preflight that retains the complete model on refusal.
Original native registration identity now also survives failed follow-up
lineage lookup without starting a worker or resolving uncertainty.
Completed preparation and its local reservation survive temporary journal-write
failure; storage recovery cannot turn the old result into a delayed launch.
An unused plan can now produce factory no-spawn evidence and close only its
own not_sent decision when exact native cancellation independently succeeds.
An internal bounded single-use preparation lease bridge now connects the exact registry claim to ingress; the actual native test graph also links the real ownership ports and keeps the shared ANE latch within the SDK dependency boundary. A private source-fixture reservation transport, exact serving consumer and typed Core acknowledgement client now pass local checks. The all-client proof/capacity issuer and production execution composition remain unfinished.
The pristine preparation path now combines a never-consumed/never-shared lease
close with original factory never-spawned or checked reaped zero-POST evidence for only that request's
`not_sent` decision. Its durable attempted checkpoint prevents close replay after
a crash. Cleanup-only identity cannot authorize launch; manual model cancellation
preserves its enclosing job. The raw CPU acknowledgement still proves neither
device completion nor all-client idle. Positive native completion, full process-epoch reconciliation and the serving
admission guard remain unfinished. An asynchronous reply newer than its poll
tick now remains retained until a later observing tick, without restamping or
renewing its lease.
The original preparation observation, readonly RPC, metadata3/preparation1
worker and optional broker/factory mode are implemented. The public manager
still supplies no execution ports and leaves source coverage unknown. The
remaining work is the trusted positive source/proof/capacity issuer and eligible
production composition, rather than rebuilding those existing data paths.

Current source reconciliation also confirms that media/vision/embedding queue
custody, authenticated five-phase registry v3/v4 transport, claimability decoding
and conservative manager normalization are implemented. Older checkpoint notes
that list them as missing are historical. Their coverage remains unknown;
registry readiness is not physical residency or completion proof. The
[current gap audit](contracts/native-capability-gap-audit.md) records exact
source-read evidence and the remaining positive issuer/guard work.

These address concrete lifecycle defects; they do not close the native-authority
workstream. Subsequent implementation must connect the producer/proof/guard and
operational paths, rather than interpreting additional component receipts as
whole-task completion.

Use [tasks](tasks.md) for checkbox ownership, [compatibility](compatibility.md)
for G2 and [validation](validation.md) for exact receipts, failures, revisions
and CI observations. No native installation/activation or production deployment
is established by this status page.
