# Reviewed native serving launch inputs

`NativeServingLaunchDocument` decodes bounded configuration metadata only. No
public manager entry point loads it. Successful decoding issues no credential
reader, native reservation or process actuator. A separate source-only protected
metadata loader is described below.

Version1 has exactly these fields:

| Field | Meaning |
| --- | --- |
| `version`, `purpose` | `1`, `reviewed_native_serving_launch` |
| `host`, `uid` | Approved Studio name and nonroot service account |
| `review_sha256` | Separately reviewed configuration evidence identity |
| `manager_sha256`, `supervisor_sha256` | Separate exact manager and supervisor executable identities |
| `server_sha256`, `application_sha256` | Separate native server and GUI executable identities |
| `revision`, `state_path` | Canonical UUID revision and exact private manager state directory |
| `working_directory` | Explicit absolute normalized cwd, including `/` |
| `arguments` | Ordered preserved server arguments, at most128 entries |
| `environment` | Preserved bounded noncredential framework/home/locale inputs |
| `credential_channel` | `argument` or `environment` |

The complete document is at most32KiB. Unknown/duplicate keys, coercions,
unsupported versions/hosts, malformed identities and unbounded inputs refuse.
The preserved argument list must contain exactly one two-token `--host <IP>`
and `--port <decimal>` pair. Addresses are explicit IPv4/IPv6 literals, not a
DNS lookup; ports are canonical decimal1..65535. Missing/duplicate/equals forms
refuse rather than inferring the native CLI's `0.0.0.0:11234` defaults. Explicit
wildcard values remain reviewable configuration; parsing one does not approve
new exposure. Installation must independently prove it preserves the existing
reviewed listener. Arguments remain byte-preserved, with no address substitution.

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

`NativeServingReviewedConfiguration.load` reads only the fixed installed
`/Library/Application Support/Fios/Studio/native-serving-launch.json`. Its code-only
role selects the fixed installed manager or supervisor image; a packet cannot
select that role. Development/wrong-role images return no configuration before
reading installed metadata. Root-protected file/tree checks, exact host/UID/state
binding, both manager/supervisor image pins and the caller's kernel/image identity
precede returning the document and fixed separate server/GUI process profile. It verifies the two
current executable pins without starting a service or reading credentials.

This is protected configuration metadata, not complete native enrollment.
Current root-protected files and image pins do not attest mapped code,
framework dependencies, immutable upgrade lifetime or exclusive handover. The
positive installed branch remains unexecuted; no root policy is created by
source fixtures. Native enrollment must independently bind configuration
review and immutable dependency provenance.
Exclusive GUI-to-agent handover, native namespace/start reservations and retained
native drain authority remain required. A decoded document, credential value or
configuration fingerprint supplies none of those permissions. This contract
changes no interface login or network binding and authorizes no installation.

The code-only native runtime constructor now takes only supervisor-role opaque
protected configuration, resolves its credential in memory and requires both start/stop
reservation validators. A bare process-profile constructor is private to the
same-file fixtures. Construction does not invoke a validator or start a child;
public startup still has no native configuration or authority producer.

Recovery correlation additionally includes the SHA256 of the exact credential-free
reviewed document bytes, under the version2 launch-input fingerprint domain.
Host/account/state/revision/review/image changes therefore cannot consume old
history even when argument values are unchanged. Credential rotation leaves
that fingerprint stable. Private helper fixtures retain the original unreviewed
version1 fingerprint domain; they supply no installed configuration proof.
Recovery file version3 is unchanged. Incompatible profile history refuses
unchanged and must not be deleted or dropped to permit an upgrade.

The manager role can derive the expected version2 control profile using a
synthetic credential slot, without reading the serving key. Its code-only
`makeCustodyClient` reads the fixed private descriptor under the reviewed state
directory, checks boot/profile/UID/canonical identity and independently verifies
the pinned supervisor kernel/image before returning a fixed transport. Missing
metadata returns no client; invalid metadata refuses. The descriptor is read
through a held directory descriptor with exact-file identity checks; unrelated
progress writes do not invalidate directory identity. This factory is still
unwired from public startup and grants no native reservation or capacity. Its
positive installed-manager/supervisor branches remain unexecuted.

Argument-channel credential values are consumed literally, including a leading
`--`, as in the pinned native parser. Fingerprint redaction consumes that value
once and never interprets it as another option. Rotation therefore cannot redact
a following configuration field or change the journal profile. This changes no
credential value, source, interface login or live server configuration.


Source launch parsing also retains the validated listener address and port as
nonsecret fields. A credential which equals --host remains a credential value;
it cannot retarget health observation. The reviewed document's health factory
uses only synthetic credential-slot validation, retaining no serving key in the
probe. Local IPv4/IPv6 family and exact port selection precede every metadata
request; no DNS, redirects, inference or remote endpoint fallback is added.
