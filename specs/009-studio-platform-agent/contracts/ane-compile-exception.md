# ANE constructor-helper exception boundary

This source increment covers `bridge_compile_load` in the existing C bridge.
An ordinary NSException from foreign model metadata or compilation bypasses its
reported-error path and leaves the negative fence clear. The exact original
helper reproduces the metadata case with a CPU NSObject before native compilation
or staging work. No engine, numerical behavior or model selection is added.

Source mode catches NSException, sets the existing constructor/compile uncertainty
bits, returns false with a fixed message and retains original graph/staging
reservations. It makes no retry, cleanup or rollback attempt. Legacy behavior is
unchanged. A clarified source comment distinguishes legacy staging removal from
source-mode uncertain retention; it adds no filesystem policy.

The80-stage checker compiles the full actual bridge and uses CPU NSObject stand-ins
for model identifier, compiler and loader methods. It exercises exceptions before
staging and during the fake compile call, normal return, reported compile error,
independent uncertainty and prior uncertainty. Parent/candidate and legacy/source
controls run in debug/optimized modes. Eight parent failures reproduce missing
fences and lost original-root quarantine.

All constructor/cache logic is real source, but `NSTemporaryDirectory` is an
explicit fixture location substitute. Foundation ignored TMPDIR on the development
OS; the first two fixtures refused before calling the constructor because their
private-path guard failed. Those failures are retained. The final substitute
returns only the runner's private directory, and cache paths are separately pinned
there. Thus legacy cleanup cannot scan/reap unrelated system temporary resources.
Fake program, weights and compiled-artifact bytes remain inside that private tree.
No native compiler, framework-loading entry point, ANE model or device is invoked.

Actual tracker/SDK-context tests explicitly capture an original request around
the same helper call and verify the genuine C negative fence quarantines that
reference after caller release. This is fixture-supplied origin capture, not an
implicit capture claim for the C helper. No return, local cleanup or retained file
is a native terminal/admission proof. Whole tasks remain39/55; full serving builds,
private integration, installed acceptance and activation are separate.
