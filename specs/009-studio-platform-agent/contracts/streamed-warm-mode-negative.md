# Negative fence for the current streamed GPU warmer

The current `sdk/weights/streamed/mimo/gpu_warm.zig` constructs an existing
private Metal queue through `mimo_warm_create`. Its worker commits warm chunks
on that queue outside the reviewed SDK command encoder. Current GLM streamed
experts install this warmer. The older26.10.3 warmer ownership receipts do not
qualify this relocated current source; the current request-origin/retirement
port remains incomplete.

The source increment marks a process-lifetime negative latch before the real
Metal constructor's C boundary, including construction failure. The HTTP fixed
negative getter independently composes this latch. It uses the existing Shared
utility so host/plugin compilation units refer to one process slot. No worker,
kernel, numerical operation, event value, model setting or lifecycle algorithm
is replaced. Construction marks unproven participation; it does not cancel the
warmer or prove the outcome of native work.

No construction leaves this new latch false. Destroy, local joins, newer
tracker epochs and subsequent success cannot clear it. A true latch reaches
the existing source uncertainty/refusal path. Actual serving primary guard
remains false; there is no new wire, all-client coverage, native reservation,
terminal/not-sent proof, lease refund or journal resolution. The seven named
backend flags remain independent: all seven false is not complete negative
source coverage and must not hide this separate warm-path uncertainty.

The strict checker projects exactly the constructor file, server file and new
utility, reverses/reapplies the patch, checks exact parent hashes and full-file
AST, and executes the actual constructor/deinit/getter bodies. The C constructor
and destroy are CPU substitutes; no Metal allocation or warm kernel is run.
Original-constructor and original-getter variants receive only the new utility
to isolate the two missing edges. They are not pristine whole-native baselines.

Cases cover before-C ordering, substituted construction failure, late refusal,
metadata destroy/new epochs, concurrent latch writes, absent construction,
independent existing ANE refusal and the unsupported actual serving guard.
Full native enclosure and validation results are recorded separately. None of
these component cases completes the warmer's request ownership port or G2.

Final evidence passes the48-case strict matrix, separate unit/host object link
in both modes, actual default162/162 native tests, enabled35/35 semantic32/32
link,4 empty-model runtime checks and post-run byte review. Initial direct
utility imports failed native module ownership and are retained as failures;
the corrected constructor uses the existing host-owned Shared bridge. This
still exercises no real warm kernel and supplies no native completion/admission
authority. See the exact validation receipts and their source/provenance limits.

The follow-up owner-registration overlay exposes the existing storage type to
`shared_all.zig` and lists it explicitly in the host's export registry, as the
upstream unit-build contract requires. Runtime latch behavior and its C symbol
are unchanged; this adds no wire/reset operation. Enabled semantic/link,
`units-check -Dunits=true` and4 empty-model checks pass. It does not qualify the
warmer ownership port or change source coverage/admission.
