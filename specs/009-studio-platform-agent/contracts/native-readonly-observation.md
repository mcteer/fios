# Read-only native observation composition

`NativeReadOnlyClient` narrows an existing trusted code-only native client to
observation, partial primary activity and independent backend flags. Its
underlying client is private; the narrowed value exposes no pause, resume,
owner-barrier, handoff, preparation or lineage mutation operation. It is not an
enrollment issuer and cannot be decoded from a task/operator document.

`AsyncNativeControl(observer:)` refuses every management operation, and scoped
or sequenced observation commands, before reserving a worker or opening a
socket. The ordinary maintenance initializer retains its existing behavior.
Both paths use the existing bounded authenticated transport and one retained
background slot; neither retries a failed operation.

The internal manager composition accepts one maintenance client or one
read-only client. Conflicting inputs refuse before opening state. Migration
holds disable either. The read-only path never begins reconciliation of stored
or newly requested service intent. It publishes observations with
`native_control_mode: observation_only`, leaves native admissions unknown and
keeps durable desired state separate from native actuation. It supplies no
lineage/preparation issuer, native idle/terminal proof or model permission.

The public entry point still supplies neither client. A root-reviewed installed
observer factory, supported native profile and installed acceptance remain
unfinished. This source interface does not activate an installed observer or
relax any policy/coverage gate.

The actual private native/manager fixture starts with maintenance intent already
saved, observes without closing ingress, accepts later desired-state changes
without applying them, and verifies the final durable running intent after the
manager exits. The ordinary maintenance composition separately still pauses
and resumes native ingress. Both remain model-free with coverage unknown.

The optional slow-ingress fixture holds all but one byte of a4096-byte GET body.
Two advancing native and primary observations retain its single original owner
before routing. Disconnect and normal body/response completion each release the
local connection owner while native activity remains unknown. The completed
response is the embedded page, not inference. A first slow-response attempt was
not repeatable because TCP buffering can complete the server write without a
reader; that attempt is not accepted as a response-retention proof. Slow
model-response/device and full modality acceptance remain open.
