# Reviewed native serving launch inputs

`NativeServingLaunchDocument` decodes bounded configuration metadata only. No
public manager entry point loads it, and no loader, credential reader, native
reservation or process actuator is issued by successful decoding.

Version1 has exactly these fields:

| Field | Meaning |
| --- | --- |
| `version`, `purpose` | `1`, `reviewed_native_serving_launch` |
| `host`, `uid` | Approved Studio name and nonroot service account |
| `review_sha256` | Separately reviewed configuration evidence identity |
| `manager_sha256` | Exact manager executable identity |
| `server_sha256`, `application_sha256` | Separate native server and GUI executable identities |
| `revision` | Canonical UUID configuration revision |
| `working_directory` | Explicit absolute normalized cwd, including `/` |
| `arguments` | Ordered preserved server arguments, at most128 entries |
| `environment` | Preserved bounded noncredential framework/home/locale inputs |
| `credential_channel` | `argument` or `environment` |

The complete document is at most32KiB. Unknown/duplicate keys, coercions,
unsupported versions/hosts, malformed identities and unbounded inputs refuse.
Only `PATH`, `HOME`, `LANG`, `LC_ALL`, `DYLD_LIBRARY_PATH` and `MLX_METAL_PATH`
are environment keys. PATH and locale retain the fixed runtime values; HOME
must satisfy the existing sanitized command environment. No model, path,
listener, authentication policy or framework value is inferred from defaults.

Argument mode stores exactly one `<fios-serving-credential>` placeholder after
`--api-key`, never the key itself. Environment mode preserves
`--api-key-env FIOS_MLX_SERVING_API_KEY` and stores no credential environment
entry. Code-only in-memory resolution supplies a nonempty bounded credential
and returns launch data; it neither persists nor logs the value. This preserves
the selected channel rather than silently converting argument authentication to
environment authentication. The constructor refuses literal argument credentials,
missing/empty resolution, conflicting channels and unsupported equals forms.

A future protected-profile loader must independently bind installed host/UID,
manager identity, configuration review and immutable dependency provenance.
Exclusive GUI-to-agent handover, native namespace/start reservations and retained
native drain authority remain required. A decoded document, credential value or
configuration fingerprint supplies none of those permissions. This contract
changes no interface login or network binding and authorizes no installation.
