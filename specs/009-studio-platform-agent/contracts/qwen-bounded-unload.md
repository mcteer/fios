# Retain the Qwen model while its reader cannot be joined

This source-only increment bounds the existing serving plugin's wait for its
page-cache reader. It depends on successful-construction publication from
[qwen-warm-publication](qwen-warm-publication.md). It changes no numerical code,
model selection, read regions or gather policy.

The source-SDK `plugin.unload` checks existing SDK uncertainty, then asks the
table to stop its reader before any record, slot, trunk, weights, configuration
or parent cleanup. One helper per retained table receives the original handle and
performs the real join. The original thread handle moves only after successful
helper publication. The helper's final table access publishes actual local join
completion with release ordering; the caller observes it with acquire ordering.
The detached helper performs no model/device work after that final access.

The caller waits with a two-second cooperative deadline and1ms sleeps. This is
not preemption of OS thread creation, clock or sleep syscalls. Creation failure,
clock reversal or timeout preserves the complete model and its stable table,
descriptor, pool, mapping, configuration and weights. Timeout marks the existing
SDK uncertainty and original descriptor's retirement as unknown. A later join
does not release that quarantine. Existing driver `tryUnbind` checks independent
cleanup evidence before/after the callback and retains its own binding on
refusal. No callback retry or uncertainty clearing is introduced.

After a successful join, a second fixed SDK-negative check runs before normal
cleanup. Preexisting or newly observed uncertainty refuses cleanup. Legacy
source-SDK-disabled behavior remains unchanged. The existing independent Qwen
negative latch also remains sticky: the normal source driver's aggregate check
can refuse before entering this callback. This component does not remove that
fence or qualify the complete model-unload path.

```sh
.venv/bin/python -I -B scripts/check-platform-qwen-bounded-unload.py --isolated --source /private/tmp/REVIEWED_NATIVE_SOURCE --zig /private/tmp/PINNED_ZIG
```

The checker renders the actual warm fields/methods, join helper/preflight and
complete plugin unload callback, with real host custody, selected SDK, real
threads and actual private-file pread/close. Other model resources and inactive
pool/embedded ports are explicit cleanup counters. A join-spawn wrapper provides
the designated creation-error case; other cases create real helpers.

Debug/ReleaseSafe test the original unload callback's held-read failure, normal
cleanup, a held read with no cleanup at the deadline, independent uncertainty
before/during join, helper creation failure, disabled warming and restored normal
behavior. The held-read cases assert a1.9–2.5s observed wait; a3s fixture release
prevents the original callback from hanging the test. Roots and uncertainty
remain after the late real read/join. Fixture cleanup after retirement is
separate from production callback execution and never clears native uncertainty.

This bounds this reader wait, not subsequent pool/map/GPU/model cleanup, every
direct SDK consumer, physical residency or all-client native completion. Tests
load no model and activate no service/admission/installed profile. Full enclosing
build and empty-catalog checks are recorded separately in validation. T019/T021/
T027 and whole-task completion remain open.
