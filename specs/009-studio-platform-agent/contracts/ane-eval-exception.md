# ANE C evaluation exception boundary

This source increment contains ordinary `NSException` failures from the existing
model and request evaluation entry points. It adds no engine, numerical path,
model ID, native listener, lifecycle operation or activation.

The original `msv_ane_model_eval` and `msv_ane_request_eval` mark their local active
state before sending the foreign evaluation message. A thrown Objective-C
exception bypasses their reported-error handling and leaves the negative fence
clear. Both exact original functions reproduce that gap with a CPU-only NSObject
stand-in; no private ANE framework/model/device operation is invoked.

With `FIOS_ANE_SOURCE`, the existing evaluation autorelease pool is inside an
Objective-C exception boundary. A caught NSException sets the one-way evaluation
uncertainty bit and returns the existing integer failure result with a fixed
message. It does not expose exception reason/prose. It retains the original
object and any active reservation, and makes no teardown/retry/replay attempt.
The existing uncertainty rules refuse subsequent evaluation and checked release.
Independent uncertainty is never cleared. The disabled legacy path is unchanged.

The canonical checker reverses/reapplies the one-file patch against its declared
parent, compiles the entire actual bridge with Foundation/IOSurface, and supplies
only fake CPU metadata objects to its real evaluation functions. Debug/optimized,
source-enabled/legacy and parent/candidate cases cover normal return, reported
failure, exception, independently raised uncertainty and prior uncertainty. It
runs no native ANE constructor or framework-loading path. Each runtime denies
network and has an eight-second bound.

Separate actual native Zig tracker/SDK-context tests retain an original request
before the same C evaluation call. They verify that the caught error's real C
fence reaches the actual negative probe, and that leaving/releasing the original
context quarantines its root rather than clearing native uncertainty. This
capture is explicitly fixture-supplied, not a claim that the raw C function
implicitly captures an origin. The first root fixture omitted this retained
reference and incorrectly expected a bare root to remain owned after leave; its
failure is preserved as setup evidence. No production behavior was changed to
satisfy that wrong expectation.

There are88 stages:16 compiler stages,64 C runtimes and8 native-root runtimes.
Eight parent failures reproduce the missing fence; candidate and legacy controls
pass. These are CPU metadata and original-reference tests, not successful ANE
inference, hardware-error acceptance, native terminal proof, all-client coverage
or admission. Whole tasks remain39/55. Enclosing native builds and private
empty-model checks are separate; no installed action or model plan follows.
