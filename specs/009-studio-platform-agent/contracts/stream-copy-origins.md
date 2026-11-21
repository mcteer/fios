# Queued streamed-expert CPU copy ownership

This source component covers the existing `StreamOf.Stream.Copier` promotion queue in
`src/sdk/weights/streamed/sdk_ext/expert/stream.zig`. It changes attribution and
lifetime accounting, preserving the existing copy algorithm, bytes and model IDs.
It does not implement another inference engine or grant native admission.

The GLM streamed-expert forward path can fail before its ordinary copy flush.
`prepareRelease` still stops/joins the copier before releasing pools; the reproduced
failure is lost request attribution after the submitting root leaves, rather than
a demonstrated use-after-free.

Before publishing an asynchronous batch, capture its original native request
context through the existing host C ABI. Transfer that reference only after queue
append succeeds. Allocation, thread-start and append failure preserve the existing
synchronous copy fallback and release any captured reference after copying.
Missing context fences native ownership and uses the synchronous fallback instead
of publishing anonymous asynchronous work.

The worker enters the captured context before the unchanged CPU copy algorithm,
frees copied descriptors, restores its prior scope and releases the original
context before publishing `done`. The copy algorithm's helper threads execute only
CPU memcpy and are joined before it returns. Failed entry/restoration fences native
ownership; copies still finish, and native uncertain references stay quarantined.
Neither queue completion nor a local thread join clears independent native
inference uncertainty. Compile-time disabled origins retain legacy behavior and
prune the optional host interface.

The isolated checker projects actual declarations and methods, renaming only the
copy algorithm entry point to insert a finite scheduling pause before executing
that unchanged algorithm. Minimal surrounding policy metadata is fixture supplied.
Actual native ownership/SDK metadata units and real threads exercise normal early
root departure, missing origin and independent uncertainty. Both Debug and
ReleaseSafe compare the exact parent with the patch, enabled and legacy controls:
eight compiler stages plus sixteen runtime stages. Six parent runtime failures are
expected regressions; candidate and legacy cases pass. Every worker is stopped and
joined before assertions, including failing baseline cases.

This fixture has no model, inference, Metal shader, remote host or installed
service operation. Selected source qualification is not whole-native provenance,
all-client coverage, terminal proof, installed acceptance or activation authority.
T002/T018–T022 remain open pending their full acceptance requirements.
