# Spec009 completion status

Updated2026-11-15. **39/55 whole tasks complete;16 open.**

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
| Native authority | T002, T018–T022 | Audited enabled-route/backend coverage; coherent normalized activity; original-request terminal/non-dispatch and process-epoch reconciliation; an atomic non-preemptive guard across native preparation and dispatch. Current negative-only and component paths are insufficient. |
| Operational integration | T008, T009, T027, T028, T030, T036, T045 | Complete enrolled resource/runtime composition; desired/observed service reconciliation; bounded drain/force and full lifecycle integration; sandbox and private-worker task wiring through the native boundary. |
| Protected installation | T049 | Actual reviewed artifact/configuration installation, switching, rollback and removal. Present tooling reviews and stages private data; it does not implement protected installation. |
| Acceptance and delivery | T051, T055 | Separately approved scenarios on both Studios, final functional review, approved PR merge, exact merged-main CI and observed automatic application deployment. App delivery and native acceptance are separate. |

Source engineering and isolated functional tests remain authorized. Work should
continue without another request for that scope. Current Studio installation,
activation and disruptive acceptance remain separately gated. Small-model Core
results do not satisfy Studio acceptance. The settled sandbox approval covers
the exact image only.

The current continuation repairs load-error reader publication and tests a
bounded reader-join preflight that retains the complete model on refusal.
These address concrete lifecycle defects; they do not close the native-authority
workstream. Subsequent implementation must connect the producer/proof/guard and
operational paths, rather than interpreting additional component receipts as
whole-task completion.

Use [tasks](tasks.md) for checkbox ownership, [compatibility](compatibility.md)
for G2 and [validation](validation.md) for exact receipts, failures, revisions
and CI observations. No native installation/activation or production deployment
is established by this status page.
