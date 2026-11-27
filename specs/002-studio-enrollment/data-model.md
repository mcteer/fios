# Enrollment and heartbeat data model

The field names below are canonical. Times on the wire are integer UTC Unix seconds. Validate JSON types exactly, including the distinction between booleans and integers.

| Field | Invariant |
| --- | --- |
| `Binding.node` | One configured slot, either `studio-a` or `studio-b`. One durable row per enrolled slot. Absence means never enrolled. |
| `Binding.machine` | Operator-verified stable machine label, 1–64 lowercase ASCII letters, digits or hyphens, unique across slots. The initial expected labels are `edge-a` and `edge-b`, subject to the operator's verification. |
| `Binding.pin` | SHA-256 of the exact DER worker leaf, 64 lowercase hexadecimal characters. Unique across slots and disjoint from retired pins on every new approval. |
| `Binding.state` | Active or revoked. Rotation changes the pin atomically. Revocation or rotation permanently retires the old fingerprint in the same transaction. Re-enrollment requires explicit approval with a fresh pin. |
| `Session.id` | A fresh core-generated 128-bit random value encoded as 32 lowercase hex characters. One current session per active binding, tied to the verified leaf and slot. A replacement invalidates its predecessor. |
| `Session.highest` | Starts at zero. Advances only when a complete report is accepted, atomically with the observation. Gaps are legal. |
| `Heartbeat.version` | Exactly integer 1. |
| `Heartbeat.node` | Exactly the slot authorized for the TLS peer. |
| `Heartbeat.session` | Exactly the current session ID issued to this peer for the slot. |
| `Heartbeat.sequence` | Integer 1 through 2^63−1, strictly above the session high-water mark. |
| `Heartbeat.sampled_at` | Positive integer within [core receipt wall time − 30 s, core receipt wall time + 5 s], inclusive. Within the same session reject source times older than the last accepted source time. |
| `Heartbeat.memory_bytes` | Integer 1 through 2^60, inclusive. |
| `Heartbeat.logical_cpus` | Integer 1 through 65,536, inclusive. |
| `Heartbeat.load_1m` | Finite JSON number between 0 and 10^9, inclusive. |
| `Observation.deadline` | Core elapsed time at acceptance plus 30 seconds minus the nonnegative age of the sample on receipt. A future sample has zero age at receipt. Reporting includes the deadline, stale begins immediately afterward. Use a sleep-inclusive elapsed clock or invalidate sessions and freshness on wake. |

Use one serialization boundary across binding authorization, session validation, highest sequence and observation replacement. Never retain a new in-memory transition if the required durable commit fails. Validate signatures, lifetimes and purpose via TLS before any application payload. Compare the active pin during each request. A duplicate approve/rotate/revoke retry must produce the original postcondition or a conflict, and must never undo a later change. Serialize admin changes with expected prior state/pin.

| Event | Operator-visible result |
| --- | --- |
| Slot absent / active without an observation / withdrawn | Not enrolled / Awaiting sample / Revoked. Withdrawn records suppress observations immediately. |
| Valid report / deadline passed | Reporting / Stale sample. Stale retains its last good measurements. |
| Session opened or replaced / rejected report | Preserve prior sample and deadline. A new session alone never extends freshness. |
| Worker rotated | Clear the old session and sample for this slot. The next accepted report yields Reporting. |
| Native enrollment service restarts | Bindings and retired pins survive. All sessions and observations start empty. |
| Enrollment service unreadable | Both Studio rows show telemetry unavailable with zero reporting. The Mini still reads its own sample. |

The durable audit records operator action, slot, UTC time and outcome. Aggregate rejected requests by bounded reason codes. Omit keys, certificates, pins, session IDs, input bodies and raw parser errors from exported diagnostics.
