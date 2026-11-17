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
