# Private preparation transport and exact serving consumer

This integrates the bounded CPU lease bridge with the existing authenticated
source-fixture Unix control socket and bound chat path. It does not enable the
native source guard, enroll all-client coverage, issue capacity/terminal proof
or configure the manager's production execution producer. T022 remains open.

`FIP9` version1 requests are exactly1104 bytes; `FIV9` replies are88 bytes.
The existing lineage reply also uses `FIP9`, but in the opposite direction with
its distinct112-byte schema. Direction, exact length, version and operation
remain mandatory; neither decoder nor transport falls back between schemas.

| Request bytes | Meaning |
| --- | --- |
| 0–7 | Magic/version, reserve1 or withdraw2, zero padding |
| 8–23 | Exact nonzero native source instance |
| 24–55 | Exact nonzero32-byte correlation |
| 56–63 | Full-width original root; zero for reserve |
| 64–79 | Model byte length, zero padding, bounded lifetime, zero padding |
| 80–1103 | Exact UTF-8 model bytes and zero trailing padding |

Reserve requires1–5000ms; withdrawal requires a nonzero root and zero lifetime.
Root IDs retain all64 bits. Only observation sequence/time fields use the
interoperable safe-integer bound. The native wrapper supplies boot monotonic
lease time; no caller timestamp can extend it. Successful replies bind operation,
instance, correlation, root, sample sequence/time and original lifetime. Failure
cannot undo a possibly created claim or become a cancellation/terminal receipt.

The existing private transport still requires source-fixture activation, the
fixture version suffix, nonroot matching UID, owned private directory/socket,
peer UID and a write-half-close. It reads at most1105 bytes, acts only on an exact
frame followed by EOF within its original two-second deadline, and keeps legacy
32/64-byte operations separate. The fixed server callbacks call only the real
registry reserve/withdraw methods. They do not load models or execute host code.
The source's unsupported primary guard continues to refuse reservations.

`X-Fios-Preparation-Root` is distinct from `X-Fios-Handoff-Root`. It requires the
bound POST chat route, exact native instance and correlation. Both root headers
in one request refuse; preparation metadata on administrative/other routes
refuses. Its decimal parser retains full-width roots and rejects duplicates,
zero, leading zeros and overflow. The request-owned decoded top-level model
bytes pass directly to the native atomic registry consumer before loading;
there is no default/alias resolution or generic post-consume bind. Existing
bound exact-advertised-ID checks remain. A failed consumption never falls back
to ordinary/identity-only dispatch or retries a consumed lease.

Current Core has strict typed acknowledgement codecs and authenticated client
methods. Mutation requests require protocol3 and a valid sequence checkpoint
before touching transport. Unknown source clock stays separate from acknowledged
identity. These types are not Codable, NativeSnapshot, a dispatch grant or a
native completion/non-dispatch proof. They do not populate production execution
ports or resolve independent native uncertainty.

The isolated transport checker verifies the exact five-file reverse/reapply
projection and actual tracker/control dependency closure. Genuine private Unix
connections exercise reserve/withdraw of UInt64.max, unsupported guards,
foreign/malformed/trailing/incomplete frames, required EOF and root-header
parsing. The explicit registry and positive primary guard are CPU fixtures, not
all-client/native device authority. Saved native frames are independently bound
and decoded by actual Core Debug/optimized binaries against both native compiler
modes. The full policy/mock suites remain separate from these focused checks.

```sh
.venv/bin/python -I scripts/check-platform-preparation-transport.py \
  --source /private/tmp/REVIEWED_SOURCE --zig /private/tmp/PINNED_ZIG
node scripts/check-platform-preparation-cross-frames.mjs --isolated \
  --receipt /private/tmp/REVIEWED_UNIX_RECEIPT --sha256 REVIEWED_SHA256
```

The empty-native `current-native-ingress.py --preparation` fixture additionally
checks unavailable reservation/withdrawal and HTTP identity, ambiguity, route
and exact-unregistered-target refusals. It uses only an empty registry and
unregistered fixture IDs. Rejected private HTTP POSTs are counted explicitly;
they are not real inference plans, model competence or Studio acceptance.
