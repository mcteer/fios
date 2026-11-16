# Current activity export and private worker guard

The manager's readonly activity response contains a version2 observation, while
the private Python guard originally accepted only the old version1 observation.
The worker now strictly validates both formats. This changes decoding, not the
manager's source ceiling, admission authority or worker handoff protocol.
Production currently exports unknown coverage/activity and continues to refuse.

For current frames the envelope must identify all_clients and the same
idle/queued/active state as its inner observation. Unknown and preparing refuse.
The observation must use the exact current field set, original host/endpoint/
profile/manager/native identities and exact model mapping. Its native sequence,
not the independent manager export sequence, must meet the trusted parent's
minimum. Both source and export clocks retain the five-second age/one-second
future bounds; the reported source age must equal the two source timestamps.
Absent source metadata, uncertain/blocked local ownership, loading, transitions,
unknown reasons, duplicate model identities, multiple residents, conflicting
work, unattributed work and inconsistent/overflowing phase totals all refuse.
An idle resident may differ from the selected target; conflicting active work
cannot. The generic preparation path stays refused pending its separate original
reservation observation and atomic transport contract.

The private Unix query checks peer UID, private socket/parent ownership, bounded
framing and exact response correlation as before, then validates the current
inner observation against the request's trusted parent mapping. No retry,
inference, model substitution or management call is added. Legacy v1 remains
for the existing isolated protocol fixtures; malformed/current frames cannot
fall back to it. Metadata2/pipe1/handoff1 are unchanged.

Finite installed-Python tests cover native versus manager sequence, valid idle
replacement and same-model phases, conflicting busy work, source age/counter/
model/ownership failures and actual private Unix envelope mismatches. The
isolated cross-language checker compiles the actual current Swift exporter in
Debug and optimized modes and sends its exact frames to the installed Python
guard. Fixture coverage declarations are test inputs, not native authority.
CI executes this checker in the existing mock-only native lane.

Full positive coverage/proof/capacity, broker preparation mode and production
composition remain unfinished. No enrollment, installation, activation or
whole-task closure follows.
