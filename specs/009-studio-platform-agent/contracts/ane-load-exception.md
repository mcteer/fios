# ANE load/unload helper exception boundaries

This source increment covers `bridge_load` and `bridge_unload` in the existing
ANE C bridge. It adds no inference engine, model policy or numerical path, and
performs no installed/native load or unload.

Both exact original helpers let an ordinary NSException bypass their negative
fence. CPU-only NSObject stand-ins reproduce that behavior. The load helper
already reserves its original graph before the foreign call, and the unload
helper already changes resident metadata only after acceptance in source mode.
Those existing properties remain.

In `FIOS_ANE_SOURCE`, caught NSExceptions set the corresponding one-way load or
unload uncertainty bit and return `NO`. No exception prose, cleanup, retry or
reservation release is added. The load graph stays quarantined; an unaccepted
unload retains resident metadata. Existing independent uncertainty remains set
and subsequent helper calls refuse before foreign work. A normal foreign return
still has its original local accepted meaning; independent uncertainty remains
separate, and no accepted result/residency grants native terminality. The disabled
legacy path and its bounded retry behavior remain unchanged.

The canonical checker compiles the entire actual bridge with Foundation/IOSurface
and invokes only fake CPU metadata methods. Parent/candidate, enabled/legacy and
debug/optimized controls cover normal success, reported error, NSException,
independently raised uncertainty and prior uncertainty for each helper. Each
runtime denies network and has an eight-second deadline. It calls no native ANE
framework-loading, constructor, model or device entry point.

Actual native tracker/SDK-context tests explicitly retain an original request
before the same helper call, then observe the actual C negative fence. Leaving
and releasing that original context quarantines its root. This capture is
fixture supplied; the C helper is not claimed to capture an origin implicitly.
There are88 expected stages, including eight parent failures. The initial
compiler fixture used the wrong name for the existing resident getter; its
setup failure is retained and corrected without changing production API names.

These are CPU error/ownership controls, not native lifecycle execution, successful
ANE inference, all-client coverage, physical completion/admission, whole-native
provenance or installed acceptance. Whole tasks remain39/55. Enclosing build and
empty-model integration checks qualify the serving source composition separately.
