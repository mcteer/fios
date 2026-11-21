# HTTP completion and native ownership

A private worker's successful HTTP/Pydantic terminal event is output completion. It does not attest that the original native request's CPU, queue, response or device ownership has ended.

For a composed, scope-bound request, `PrivateWorker` now marks the inference claim uncertain when forwarding a successful text-completion event. Its ordinary cancellation and exact local reap retain that claim. The existing correlated zero-POST summary/terminal/reaped-worker non-dispatch path is unchanged, as is the separately documented live pre-spawn issuer. Unbound low-level protocol fixtures keep their explicit primitive completion semantics; composed broker launches always carry an inference scope.

A genuine native completion/quiescence producer must reconcile the exact stored scope independently. No such authority is inferred from a provider event, successful body, EOF, process exit, current health, zero sampled counters or a package receipt. The native issuer and its all-client contract remain T002/T020/T021 work.

A failing-first regression runs the installed private Pydantic worker against MockTransport, receives output completion and reaps the child. The old code clears its bound claim and fails `BOUND_HTTP_COMPLETION_RELEASED_NATIVE_OWNERSHIP`; the fix requires that claim and an older uncertain request to remain. The fixture then supplies an explicit synthetic native terminal reconciliation only for its own mock claim. The four-request broker-budget fixture similarly asserts retained uncertainty after each HTTP completion and supplies a separate mock native receipt between rounds. These fixture reconciliations do not establish a native producer or runtime authority.

The custom frontend's text-completion event and Pydantic inference route are preserved. No Python protocol, model ID, retry budget, model engine, installed service or native activation changes. Whole-task progress remains39/55.
