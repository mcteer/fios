# SDK background participant start exclusion

This source-only opt-in closes one race for a future reviewed exclusion mode:
a residency-refresh participant cannot start after its exclusion decision.
A sampled false gap flag alone does not provide that guarantee.

The separate cumulative c69303b SDK candidate adds a one-way seal under the
same registry mutex used by the existing refresh metadata hook. Sealing requires
enabled custody, no cleanup uncertainty and no prior refresh participant. A
repeated seal refuses. A refresh hook records its sticky coverage gap and, when
sealed, throws before returning to the constructor's thread-creation statement.
If the hook wins first, sealing refuses. The gap remains independent of cleanup
uncertainty; neither refusal nor an empty registry becomes native completion.

The native source increment selects this only with the explicit private C++
compile definition `FIOS_REQUIRE_BACKGROUND_PARTICIPANT_SEAL`. Missing SDK
support in that mode exits78 rather than silently downgrading. Ordinary builds
preserve existing behavior with both current and older reviewed SDK headers.
No installed/public profile selects this mode or changes a refresh setting.

That distinction is required: MLX-Serve's existing `src/mlx/ffi.zig` defaults
refresh to1000ms when unset. The first unconditional startup integration refused
that configuration and failed the empty-catalog startup check. The retained
failure is not acceptance. The corrected opt-in preserves ordinary startup;
an eligible production composition still requires a complete ownership contract
or a separately reviewed configuration scenario. This does not track the
refresh worker, cover initial residency-set operations or qualify other writers.

`check-platform-sdk-residency-refresh.mjs --participant-seal` selects only the
exact new cumulative patch and CPU metadata fixture. Eight Debug/optimized
cases cover pre-enrollment refusal, existing-participant refusal, sealed repeated
start refusal and the concurrent seal/start edge. `--sealed-metal-metadata`
adds two explicit Core-only, five-second device-metadata cases. The public SDK
`device_count` catches initialization errors and reports unavailable; the test
requires zero devices plus the retained gap and no cleanup-failure flag. That
zero is not idle/terminal proof. No model or array is evaluated.

`--native-bridge ABS_ORIGINAL_CPP` also verifies the pinned original constructor
and applies the separate source increment. Both modes exercise its previous-code
expected failure, explicit-mode success, unchanged default behavior, exact
prior-header compatibility and prior-header strict refusal. All20 combined cases
pass, with synthetic refusing native callbacks in the constructor fixture.
The matching C binding passes CPU compatibility and preserves620 exported names.

The combined native35/32/20 compiler graphs pass. Ordinary empty-catalog startup, correlation/activity/preparation refusal and
actual manager observation checks pass, including the independent retained SDK
background gap. Four successful checks are reused only after all eight artifact
records match exactly across the metadata re-enclosure. Source component success
is not whole-native, installed or model acceptance; all-client coverage and
native admission remain unsupported.
