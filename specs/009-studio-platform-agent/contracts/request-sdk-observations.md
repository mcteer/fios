# SDK observations for original native requests

The functional overlay `mlx-serve-request-event-roots.patch` adds per-original-
request callback observations to the existing native SDK bridge. It layers on
five exact parent files declared in `request_event_roots_parents.json` and adds
`request_event_roots.zig`; no SDK library or inference engine changes are made.

An existing retained SDK context supplies distinct original root sequences.
For a managed handoff this is the registered request root, rather than the later
incoming connection token. Accepted callback origins cache those roots; callback
retirement updates the same cached roots. Existing global callback counters and
ownership behavior remain. Bounded completed history may roll over; absence is
represented as absent data, and incomplete history is explicitly identified.

The private source-fixture control connection accepts a64-byte `FIO9` query
(version1, instance/correlation/root layout matching request retirement) and
returns a160-byte `FIV9` response. Bytes8–63 echo the request identity. Bytes
64–79 hold capture sequence and timestamp. Each40-byte host/Metal section holds
presence/history/uncertainty flags, sequence, originated, retired and pending
counts. Unavailable SDK data has absent sections. A request identity must already
be known through live or locally retired request metadata.

`NativeControlClient.requestEvents` reads this response through the existing
private connection. The Swift observation types are separate from native proof
and admission types. This query is not added to installed read-only enrollment.
The full native server passes its existing SDK observer only when source SDK
support is built in; no runtime activation or installed policy is changed.

Normal checks cover overlapping roots, completed-history rollover, genuine SDK
CPU callback attribution including managed handoff, captured frame decoding,
and actual private Unix transport into the Swift client in debug and optimized
builds. The genuine SDK fixture performs only a four-value CPU graph; it does
not demonstrate a Metal kernel, model request, physical residency, whole-request
completion, all-client coverage or Studio resource acceptance. Counts never
release an independent unresolved inference claim.

Run `node scripts/check-platform-native-request-event-frames.mjs --isolated`
for captured-frame checks. For genuine native component checks, use
`python scripts/check-platform-native-request-events.py --isolated --source
/absolute/private/candidate --zig /absolute/pinned/zig --sdk-source
/absolute/matched/sdk-source --sdk-library /absolute/matched/libmlx.dylib`.
The checker verifies reverse/reapply of the selected patch in a separate private
projection and records component receipts. Whole-native builds remain separate.

A separate normal GPU fixture uses the same original-root overlay and unchanged
SDK with a four-value add graph. It uses a64MiB allocator guideline, zero cache,
a finite child deadline and the existing private background-refresh exclusion.
That guideline is not a hard GPU quota. GPU callback records need not include
CPU host callback records. `check-platform-native-request-events-gpu.py` checks
Metal counts for both original roots and the distinct managed incoming token;
its private native/Swift fixture reads the same160-byte observation response.
It does not run a model or qualify physical residency or whole-request completion.

The existing off-loop `NativeLineagePoller` can now collect these observations
when its code-only client explicitly sets `observeRequestEvents:true` (default
false). It uses the live original root or the journal's previously observed
root after local retirement. The same single result slot holds both metadata
responses; no second polling worker is introduced. A manager-thread getter
returns only the current original request's fresh sample. Unavailable or expired
samples are absent, completed jobs are omitted, and cache contents are not
persisted or restored on restart. Callback retirement never resolves an
inference reservation. Installed read-only configuration does not gain this flag.

Normal mock polling tests cover pending→retired observations without completing
the journal request, ordinary unavailability, expiry, a fresh poller with no
cached observation, and default-off collection. Existing lineage polling tests
remain covered. An explicit local GPU/native/journal fixture registers a real
native handoff for a generated journal request, executes the four-value graph,
and reads its Metal observations through the actual off-loop poller. This
fixture issues no model request or native admission authority.

The normal live queue fixture additionally uses the actual existing native
request Book and actor entry before the four-value GPU graph. Its queue-aware
lineage shows queued/active operations on the same original root, then
responding after Book/actor cleanup and callback retirement. The fixture loads
no model; this does not qualify all model adapters or infer native completion.
