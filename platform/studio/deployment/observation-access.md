# Read-only observation handoff (development, not enrolled)

`studioctl --state FIXED_ABSOLUTE_PRIVATE_STATE export` emits only the version2
observation object, at most64KiB, through the observation socket. It does not
accept stdin, roles, endpoints, original remote commands, task requests or
management operations. The original manager/native epochs and source timestamp
are retained. Present coverage is `unsupported`, not idle. Export does not
attest its own generation: a consumer must separately enroll host, endpoint,
profile and both generations, validate age/sequence/coverage, and permanently
fence a changed generation.008 remains parked; no consumer is imported here.

## Proposed restricted-key boundary — requires separate review/enrollment

This is an illustrative **noninstalled** authorized-key entry, not a ready key:

```text
restrict,command="/PROTECTED_REVIEWED_RELEASE/bin/studioctl --state /FIXED_PRIVATE_PLATFORM_STATE export" ssh-ed25519 SEPARATELY_REVIEWED_PUBLIC_KEY
```

Use exact protected artifact/state paths without caller substitution. A dedicated
export-only key must never be the operator's general SSH key, be passed to a
model/sandbox, or authorize a task/control socket. `restrict` and the reviewed effective server policy must disable PTY,
user RC and agent/X11/local/remote/Unix forwarding. The fixed forced command
and CLI rejection must prevent alternate session/subsystem commands. The CLI additionally rejects any nonempty `SSH_ORIGINAL_COMMAND` and
any `SSH_TTY`, before contacting the manager. Invoke no remote command: an
attempt to request a shell command or SFTP must fail, not be interpreted.

Key restrictions alone **do not** establish the host SSH configuration. The
review must also establish `PermitUserEnvironment no`, no accepted client
environment patterns (especially loader/PATH/runtime settings), no environment
key options, expected account/UID, protected authorized-keys ownership, host-key
pinning and all effective forwarding/session restrictions. Do not use an
unreviewed `Match` block or assume the local SSH defaults prove remote policy.
Changing host sshd configuration, accounts, enrolled keys or host networking is not part of the fixture. The isolated fixture uses only a disposable loopback listener, generated private keys/configuration and generated manager state; it never edits host SSH files or enrolled keys. Actual host enrollment must separately review the account's controlled login shell/startup environment as well as effective sshd policy.

A future enrolled client should use a fixed trusted host/account/key/known-hosts
mapping, no user SSH config (`-F /dev/null`), strict host-key checking, identities
only, batch mode, no PTY/forwarding and no remote command. Close stdin, impose
connection/read/total deadlines, bound stdout to64KiB, reject nonzero exit,
truncation and extra output, then apply the independently enrolled observation
validator. Reconnection and newer health are not generation enrollment.

## Future consumer contract (no008 activation)

The SSH transport must establish the fixed independently enrolled host/account/key mapping and exit successfully **without a signal, timeout or truncation** before handing stdout (only) to `ObservationValidator`. A nonzero exit, even with apparently valid stdout, is failure. Bound connection/session/output deadlines and decoded stdout to64KiB; never merge stderr, unwrap an arbitrary control envelope, normalize diagnostic JSON or enroll generations from returned data. Reconnection retains the existing expected host/endpoint/profile/manager/native identity tuple. A change permanently fences that validator, including a later return to its old tuple; only separate trusted enrollment constructs a new validator. `unsupported|unknown` always maps to unknown, and even genuine idle cannot clear independently retained managed inference uncertainty.

`Tests/StudioCoreTests/ConsumerTests.swift` exercises raw-only shape/size, unsupported/unknown coverage, contaminating banners/trailing objects, duplicate keys, native diagnostic rejection, persistent identity/generation fences and independent uncertainty. Enrollment is synthetic and no008 code is imported.

## Executed evidence and explicit gaps

```sh
node scripts/check-platform-ssh.mjs --isolated
```

This real unprivileged OpenSSH fixture builds a disposable local manager/CLI, generates two temporary Ed25519 keys and a private authorized-key file using `restrict` plus the fixed exporter command, verifies `sshd -T -C` effective policy, and starts only a loopback sshd with that private configuration. `StrictModes` requires a private temporary directory under the current user's home (not world-writable `/tmp` ancestors); no `.ssh` path is used or modified. The client ignores user/system SSH configuration and agents, requires the exact generated host key and uses only the generated export identity.

Passed: actual authenticated bounded raw export with unchanged manager/native epochs and unsupported coverage; alternate-command/SFTP/PTY rejection; wrong host-key/client-key refusal; direct TCP, reverse TCP and reverse Unix forwarding refusal with zero connections to a private witness target; stdin management-shaped JSON remains inert and manager desired state stays running. Forwarding/negative checks require an actual positive nonzero exit: timeout/killed transport is explicitly **not** refusal evidence. Effective policy separately proves no accepted caller environment, user RC, agent/X11/tunnel/PTY or forwarding, and public-key-only authentication. All fixture children are stopped/reaped and generated keys/configuration/databases removed. Logs `/tmp/fios-009-ssh-fixture-strict.log`, failing-first `/tmp/fios-009-ssh-fixture-red.log`.

The existing `check-platform-process.mjs --isolated` additionally exercises CLI command/PTY environment guards and manager responsiveness, while role security tests deny management on observation IPC. This completes the isolated future-consumer/forced-command fixture requirement (T024), **not** effective configuration review, host-key/account/generation enrollment or export from either actual Studio SSH server. No native installation, native inference or deployed transport is implied.

Version2 carries separate manager/native sequence/time, bounded per-model phases and local ownership blocking. `ObservationValidator` independently checks both sample ages/sequences plus resource summary age; unknown gaps retain native replay tracking. The CLI can relay exact legacy version1 unknown/unsupported diagnostics for older development artifacts, but rejects legacy all-client claims. See the [activity contract](../../../specs/009-studio-platform-agent/contracts/activity.md) for the exact fields and fixed reasons. No production all-client source or008 routing is activated by this wire change.
