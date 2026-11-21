# Native SDK CPU callback receiver

This source component extends the existing host-owned `sdk_request_ownership.zig` module. The SDK version1 observer can call its fixed `fios_native_host_request_event_observe` export. The borrowed context stays alive in the SDK throughout that call; the receiver copies original native tokens and never retains the pointer. It does not enter TLS, invoke SDK/model code or allocate.

The metadata mutex protects256 live event slots and a4096-ID reorder window. Origin records the exact immutable original token group; retirement must match the original event and group. Concurrent origin callbacks may arrive out of allocation order. Completed IDs cannot be replayed. The window advances only through consecutively retired IDs, never unseen or active ones. Sequential work reuses metadata slots without resetting source IDs. Excess live events, an unresolved gap outside the window, invalid transitions and wrong origins fail closed.

Uncertain events keep their original identity and fence the existing native tracker. Diagnostic uncertainty includes the independent cached native tracker fence, read outside the event mutex. A later callback, descriptor cleanup or zero local count cannot clear it. This is callback metadata, not an independent native lifetime owner or device-terminal proof. The SDK retains actual original custody through its callback/capture cleanup protocol.

The receiver is not registered by production startup in this component. Tests connect the actual SDK observer to the receiver in private processes. There is no new wire response, native proof issuer, positive all-client capability, atomic admission or installed activation. Production composition requires the separately reviewed matching SDK/native build and the remaining capability contract. Default and installed source behavior stay gated.

Validation distinguishes genuine four-value SDK CPU graph callbacks from direct metadata transition cases using real native contexts. Neither profile invokes a model, HTTP request or Metal shader. Direct metadata calls do not establish real device/worker coverage or independently retained descriptors for each simulated event. See validation.md for exact fixtures, failures, hashes and enclosing-build scope. Whole T020/T021 remain open.


The later [optional source startup bridge](sdk-host-event-bridge.md) connects this
receiver when the selected SDK exposes the version1 interface. Its private
image qualification does not change installed/public enrollment or native proof
and admission gates.
