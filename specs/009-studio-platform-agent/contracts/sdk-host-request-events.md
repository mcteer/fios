# SDK CPU callback event attribution

This T020/T021 source component adds an optional version1 observer for existing SDK CPU callbacks. The existing seven-pointer ownership-hook table and legacy behavior remain. Registration requires that table and enabled source custody, with no earlier stream/host/Metal activity; wrong version/size/missing callback, duplicate and late registration refuse.

Each callback gets one nonreused UInt64 ID and its borrowed original native context before enqueue. After its function and captured objects retire under the original context, and that TLS scope restores, the SDK reports retired or uncertain. Abandoned reservations, observer refusal, sequence exhaustion and callback errors fence SDK/native custody before descriptor release. Callbacks run outside SDK metadata locks. Observer tables must remain immutable for the process lifetime; observer code must not throw, call MLX or retain the borrowed context pointer. It may copy bound origin metadata through trusted native code.

When this observer is enabled, host shared-event waits check irreversible SDK uncertainty between finite native waits and throw on failure. They never signal an event, stop native work or establish completion. Legacy observer-off waits remain unchanged.

This is CPU callback evidence only. It is not Metal/device completion, whole-request terminality, all-client coverage, model capacity, a no-start reservation or admission authority. Original uncertainty is never cleared by callback retirement. There is no native event ledger, new wire response, native proof issuer, public manager composition or installed activation here.

The four-file patch layers on the selected c69303b SDK with its four prior overlays. Genuine four-value CPU graph tests use the actual native ownership module; the observer enters the real borrowed context to compare its token with the original native root. Legacy mode, registration errors, refused origin/retirement and abandoned reservations are separate cases. Normal callback evidence is genuine, while the receiver is a bounded test observer rather than a production native producer. No model, HTTP request or Metal shader dispatch runs.

Selected SDK component qualification passes:14 canonical stages (four compiler stages and10 runtime scenarios), plus20 controlled delayed-refusal repetitions. A clean218.548s C++ SDK rebuild preserves991 source files,333 dependency files and its CMake input snapshot. MLX-C and a complete native serving image are not rebuilt by this component. Both Studio acceptance and all-client native proof/admission remain open;39/55 whole tasks complete.

The subsequent functional native integration in
[request-sdk-observations.md](request-sdk-observations.md) associates these
existing callbacks with original request roots and provides a separate private
observation query. It does not change this SDK ABI or create completion proof.
