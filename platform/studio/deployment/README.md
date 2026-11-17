# Native release / installation review

**Development-only; installation, rollback and uninstall execution are not implemented or authorized.** No launchd job has been installed. Native lifecycle and inference remain disabled. Templates are not runnable enrollment records.

## Build and verify

The current development template records the observed MLX-Serve26.11.2 server/GUI file pair and the current `uv.lock` digest. The validator also accepts the historical26.10.3 file pair so existing inactive packages remain reviewable; mixed version/file observations refuse. Those are on-disk inventory declarations, not running-image or source/native coverage proof. All approval/enrollment/activation gates stay closed. A lockfile change requires a matching reviewed template update; the packer refuses a stale digest before building.

On the pinned arm64 Swift6.4.2 (`swiftlang-6.4.2.1.9`)/SDK27.2/System SQLite3.54.0 toolchain:

```sh
node scripts/package-platform.mjs --output /ABSOLUTE/NEW_RELEASE_DIRECTORY
```

The packer uses clean scratch builds, fixed source/debug path maps, no UUID/debug metadata, fixed development ad-hoc identities and explicit source/artifact hashes (including the installer/state-plan review tooling in the source hash). It assembles and verifies the payload inside its own private build directory, then executes only the just-built CLI's data-only `stage-release` branch to publish it. The requested output must be new beneath an owned0700 private parent; retained directory descriptors/no-replace publication protect that destination. The packer never deletes the requested output after error and retains its private build directory on both success and failure for independent review. `build_directory` in its result identifies that data; staging diagnostics are retained there if publication refuses. No packaged program is executed from the input payload. It includes no credentials, environment files, interpreter tree or approved sandbox image. Nine artifacts and a canonical receipt are staged; package_complete remains false. The source-tree digest covers the declared packaging inputs, while `source_revision` records Git HEAD; neither field alone proves a clean whole-repository build or installed native provenance. Native inventory hashes are observations, not all-client coverage attestation. The Docker multicall binary hash is **not** an OrbStack lifecycle CLI authorization.

A finite local failure rehearsal uses the genuine pinned Swift-only development build. Historical Swift6.4 (`swiftlang-6.4.0.34.1`)/SDK27.0 receipts remain bound to that complete tuple; current Swift6.4.2/SDK27.2 artifacts carry their own source/build identities. Neither tuple attests separately built Metal backends or installed native provenance:

```sh
node scripts/check-platform-package-publication.mjs --isolated
```

It swaps only a generated private output parent with a generated sentinel parent at publication, then verifies failed publication preserves the sentinel bytes. The generated filesystem namespace and fixture build data are retained; no service, native model, production state or privileged operation is involved. This tests data publication, not root-protected installation or T049 completion.

A separate private runtime candidate can be produced with the pinned noneditable environment. The output must be new beneath an owned0700 parent:

```sh
.venv/bin/python -I -B scripts/package-platform-python.py --output /ABSOLUTE/PRIVATE_PARENT/NEW_RUNTIME
```

This finite development command copies actual CPython3.11.17 and installed distribution RECORD bytes, flattens contained interpreter file aliases, excludes console wrappers/caches, and refuses escaping links, special/multiply linked files, editable packages and source/package mismatches. It rechecks original identities and copied hashes/modes/tree around a30s network-denied import probe. Copy/review work has a120s cooperative deadline,10000-file/512MiB total and128MiB per-file limits; filesystem syscalls are not preempted. The copied interpreter must report its private prefix, load the installed worker/Pydantic extension from that tree and observe denied network access. Source/installed agent file sets and bytes must match before and after probing. Failures retain private data; there is no cleanup, installation, service or model action.

Read-only byte review requires the separately retained expected receipt digest:

```sh
.venv/bin/python -I -B scripts/check-platform-python-candidate.py --candidate /ABSOLUTE/PRIVATE_PARENT/RUNTIME --sha256 REVIEWED_CANDIDATE_SHA256
```

This command never executes candidate code. It verifies the pinned receipt, finite exact file/directory surface, regular single-link files, ownership/modes and every recorded size/hash, with rooted directory checks and a final receipt recheck. Duplicate JSON keys, extra paths and any claimed approval/enrollment/activation refuse. Results describe per-file observations, not an atomic installed-tree reservation or provenance approval.

Ordinary factory compatibility can then be checked separately:

```sh
node scripts/check-platform-worker-runtime.mjs --isolated --candidate /ABSOLUTE/PRIVATE_PARENT/RUNTIME --sha256 REVIEWED_CANDIDATE_SHA256
```

This compiles the actual Core worker factory, verifies the candidate bytes before and after, and executes its existing metadata-only worker check under network denial. It creates no model dispatch binding, job, native admission or installed service. Passing confirms factory/runtime metadata compatibility; it does not enroll the writable development tree or make the nine-artifact release complete.

`candidate.json` is sealed last and binds the actual byte inventory, producer, release template, lockfile and source hashes. This is installed-byte evidence, not publisher/build/whole-OS provenance. The destination remains writable development data; its receipt must be independently checked again after use. It does not expand the nine-artifact release surface, enroll an immutable interpreter, authorize installation or clear any native uncertainty. All approval/enrollment/activation flags remain false.

Read-only, single-host review (list all supported workflows with `node scripts/install-platform.mjs --help`):

```sh
node scripts/install-platform.mjs plan --release /ABSOLUTE/RELEASE_DIRECTORY --sha256 REVIEWED_MANIFEST_SHA256 --host fios-edge-a.lab
```

The expected digest must come from the reviewed build receipt, not an untrusted package's own claim. File review rejects special/set-ID files before reading, opens nonblocking/no-follow to cover a raced FIFO, and checks exact descriptor/named inode metadata and byte count after reading. These are per-file observations, not an atomic whole-tree reservation; future installation must stage and independently reverify protected destination bytes before activation. The reviewer verifies the finite tree, receipt and every byte/mode, rejects links/extra files, and emits explicit blockers. Current packages cannot produce privileged commands. No SSH, launchctl, app/runtime lifecycle, inference, RDMA/network change or deletion is performed. Unknown/apply/rollback/uninstall commands fail closed. This is a review scaffold, **not completion of T049**.

## Repeatable private package check

After producing and independently reviewing a development package, run:

```sh
node scripts/check-platform-release.mjs --isolated --release /private/tmp/PRIVATE_PARENT/RELEASE --sha256 REVIEWED_MANIFEST_SHA256
```

This requires the canonical owned0700 private release path. It verifies all
artifact bytes, stages and verifies both hosts' configuration proposals in new
private data, lints the four plists, and starts only the private packaged manager
with fresh state. Actual CLI status must report observation unconfigured,
native admission unsupported and sandbox admission disabled. The child stops
within finite deadlines; release bytes are rechecked and the private receipt is
retained. A wrong expected digest refuses before startup. No host is contacted,
program installed, service activated or model invoked. This command does not
verify installed root-policy behavior or whole-native provenance. Use the
separate old/new/old recovery rehearsal for stopped-state backup and rollback.

## Per-host configuration review

Render the actual two packaged launchd templates against an existing private state directory, without writing or installing them:

```sh
node scripts/install-platform.mjs plan-config --release /ABSOLUTE/REVIEWED_RELEASE --sha256 REVIEWED_MANIFEST_SHA --host fios-edge-a.lab --state /ABSOLUTE/PRIVATE_PLATFORM_STATE
```

The JSON includes the proposed supervisor/session plist content, content hashes, source-template hashes, root:wheel/0644 installation metadata and fixed destination paths. The existing approved `mcteer` service user and `/Library/Application Support/Fios/Studio` binary location remain explicit. State paths are XML-escaped. The supervisor runs as that user from the system domain; the session component requires that user's Aqua session. Review each Studio separately; selecting a host does not contact it or verify its identity.

To save the same proposal as a private bundle for independent plist review:

```sh
node scripts/install-platform.mjs stage-config --release /ABSOLUTE/REVIEWED_RELEASE --sha256 REVIEWED_MANIFEST_SHA --host fios-edge-a.lab --state /ABSOLUTE/PRIVATE_PLATFORM_STATE --to /ABSOLUTE/PRIVATE_PARENT/NEW_CONFIG_BUNDLE
```

The destination must be new under an existing owned0700 directory. It contains the two rendered plists and `review.json`, all private0600 files. The receipt binds the review bytes; the review binds each plist and its proposed installation destination/owner/mode. This writes only the private bundle. It executes no packaged program, changes no enrollment or launchd configuration, and keeps `installed:false`/`activation:false`. Preserve any partial output after an error; do not treat it as a completed bundle. `plan-config` remains read-only.

Verify a saved bundle later against the same chosen release and the independently retained review digest:

```sh
node scripts/install-platform.mjs verify-config --release /ABSOLUTE/REVIEWED_RELEASE --sha256 REVIEWED_MANIFEST_SHA --host fios-edge-a.lab --bundle /ABSOLUTE/PRIVATE_CONFIG_BUNDLE --bundle-sha256 REVIEWED_BUNDLE_SHA256
```

This checks the review bytes and both declared plists, including their source-template binding and expected rendered content. It opens neither a journal nor installation destinations, and does not require the old state directory to remain present; retained rollback proposals can therefore be checked after state is moved. It returns `review_required`, `installed:false`, `activation:false` and `changes_made:false`. This is byte/configuration consistency for those declared files, not verification of installed state, credentials, native enrollment or an atomic installation reservation.

The command leaves the state and system directories unchanged and emits no privileged commands. Current release/enrollment and installation-approval blockers remain. Generated content is proposal data, not an installed configuration, complete interpreter/native enrollment or service-start permission. Rollback steps retain current state/configuration, restore reviewed previous artifacts/configuration, restore the previous original backup into a fresh directory and verify status without inference. Actual switching/removal still requires the separately reviewed installation workflow; do not load these development proposals.

## Verified offline artifact copy

A newly reviewed CLI built from this source supports a data-only staging operation:

```sh
studioctl stage-release --from /ABSOLUTE/REVIEWED_DEVELOPMENT_RELEASE --sha256 REVIEWED_MANIFEST_SHA --to /ABSOLUTE/PRIVATE_PARENT/NEW_COPY
node scripts/install-platform.mjs plan --release /ABSOLUTE/PRIVATE_PARENT/NEW_COPY --sha256 REVIEWED_MANIFEST_SHA --host fios-edge-a.lab
```

The native copier checks the independent manifest digest, strict JSON, schema9/development/activation-disabled flags and the fixed nine-artifact path/mode/size/hash surface. It does not issue an enrollment or attest the remaining metadata; the Node reviewer independently validates the complete release schema/tree before and after copying. Use a separately reviewed current CLI; historical artifacts may not implement `stage-release`. No packaged program is executed by the copier.

Only an unprivileged account may copy into a fresh directory beneath its own0700 parent. Descriptor-relative no-follow/nonblocking operations reject links, special files, changed inodes, extra entries, nested source destinations and unsafe permissions/ACLs. Copies use bounded buffers, cooperative30s deadline checks (filesystem syscalls are not preempted),≤256MiB of artifacts plus a≤64KiB receipt and≥10GiB remaining disk headroom. Every artifact is rehashed from its destination descriptor. Final directory names must still resolve to the verified copied descriptors. Files/directories are fsynced before no-replace atomic publication; an existing destination, including one appearing during publication, is preserved. Failure before publication retains the generated `.fios-stage-UUID` copy for diagnosis. A durability failure after rename explicitly reports publication uncertainty: inspect/verify the requested destination before retrying, never infer absence or overwrite it.

The resulting files are private **development data**, not a root-protected immutable installation. Source and prior copies remain intact; no journal, credential, configuration, launchd, socket, runtime object or native model is accessed. Protecting/reverifying an installed destination, completing the release tree and reviewing activation remain T049 work.

Finite isolated validation against an independently reviewed development receipt:

```sh
node scripts/check-platform-staging.mjs --isolated --release /ABSOLUTE/REVIEWED_RELEASE --sha256 REVIEWED_MANIFEST_SHA
```

This runs Debug/optimized metadata fixtures, actual current-CLI copying and full Node verification, plus private source witnesses for corrupted copied bytes, a destination race, substituted copied-directory binding and post-publication uncertainty. The private helper/SwiftPM build runs with IP networking denied; no installed operation or native inference occurs. Expected corrupted/partial copies contain only known fixture artifact bytes and are discarded with the rehearsal namespace.

## Offline journal/export snapshot and fresh-directory restore

After separately authorized shutdown of **both supervisor and manager**, the native CLI supports:

```sh
studioctl --state /ABSOLUTE/PRIVATE_PLATFORM_STATE backup --to /ABSOLUTE/PRIVATE_PARENT/NEW_SNAPSHOT.sqlite
```

The utility verifies the FIS9 platform marker and schema9, holds exclusive supervisor-then-manager locks to prevent watchdog respawn, copies source bytes under the writer fence and recovers WAL only in a bounded private snapshot, uses a finite≤64MiB/10s SQLite backup, fsyncs and returns only schema/length/hash. It never overwrites a destination. Restoring the isolated test snapshot retains unresolved inference claims; startup marks them uncertain rather than replaying execution. Future ownership schemas are rejected before journal mutation.

The `backup` command above includes **only metadata**. For a consistent journal plus explicit-export bundle, hold the supervisor-and-manager stopped-writer fence across both snapshots:

```sh
studioctl --state /ABSOLUTE/PRIVATE_PLATFORM_STATE backup-state --to /ABSOLUTE/PRIVATE_PARENT/NEW_BUNDLE
studioctl --state /ABSOLUTE/PRIVATE_PARENT/NEW_BUNDLE verify-backup --sha256 REVIEWED_BACKUP_RECEIPT_SHA256
studioctl --state /ABSOLUTE/PRIVATE_PARENT/NEW_BUNDLE restore-state --sha256 REVIEWED_BACKUP_RECEIPT_SHA256 --to /ABSOLUTE/PRIVATE_PARENT/NEW_RESTORED_STATE
```

The read-only reviewer can also propose these **unprivileged offline data commands**, without running them:

```sh
node scripts/install-platform.mjs plan-backup --release /ABSOLUTE/RELEASE_DIRECTORY --sha256 REVIEWED_MANIFEST_SHA256 --host fios-edge-a.lab --state /ABSOLUTE/PRIVATE_PLATFORM_STATE --to /ABSOLUTE/PRIVATE_PARENT/NEW_BUNDLE
node scripts/install-platform.mjs plan-restore --release /ABSOLUTE/RELEASE_DIRECTORY --sha256 REVIEWED_MANIFEST_SHA256 --host fios-edge-a.lab --backup /ABSOLUTE/PRIVATE_PARENT/BUNDLE --backup-sha256 REVIEWED_BACKUP_RECEIPT_SHA256 --to /ABSOLUTE/PRIVATE_PARENT/NEW_RESTORED_STATE
```

Output contains fixed `studioctl` program/argv arrays and the verified artifact digest; no shell, credential resolution, Native CLI execution, SQLite open, service action or file creation occurs. Paths must be private owner directories, with a fresh nonnested destination. A restore proposal first lists `verify-backup`, then `restore-state`. Source identity, stopped-writer state and backup origin/receipt are explicitly **unverified at review**; the reviewed native CLI independently enforces them when the operator executes it on the originating host. A plan is not a backup, restored state, installation approval or full rollback rehearsal. Existing destinations, links, unsafe modes, invalid digests, extra/execute flags and unsupported actions are refused.

### Offline rollback proposal using the retained original backup

```sh
node scripts/install-platform.mjs plan-rollback --release /ABSOLUTE/CURRENT_RELEASE --sha256 REVIEWED_CURRENT_SHA --host fios-edge-a.lab --previous /ABSOLUTE/PREVIOUS_RELEASE --previous-sha256 REVIEWED_PREVIOUS_SHA --backup /ABSOLUTE/ORIGINAL_PREVIOUS_BACKUP --backup-sha256 REVIEWED_BACKUP_SHA --to /ABSOLUTE/PRIVATE_PARENT/NEW_ROLLBACK_STATE
```

Both release trees and independent expected receipts are checked; the current and previous receipts/paths must differ. The proposal uses the **previous** reviewed `studioctl` to verify and restore its own original stopped backup into a fresh private directory. For a retained schema7 previous artifact, the explicitly named `plan-rollback-seven` operation accepts schema7 only on that previous-artifact branch. Ordinary current-release, installation and `plan-rollback` validation still refuse schema7. Neither operation downgrades or mutates the new journal, switches an installed program, processes credentials, starts/stops a service or executes commands. Backup origin/receipt, stopped writers and the installed configuration remain unverified by planning; the previous CLI checks the backup again when the operator executes each data command. Keep the new state and both artifacts/backups for diagnosis. Never restore the evolved database with an older program.

The isolated `check-platform-upgrade.mjs --migrate-seven` rehearsal now obtains these exact proposal commands from the current installer and executes only their two unprivileged data operations against disposable stopped state. Old7→held8→old7 recovery passes with unchanged native uncertainty/exports/budgets. This proves the offline data proposal, not complete installed binary/configuration/credential rollback or T049 completion. Privileged installation/uninstall and installed acceptance remain separately gated and unfinished.

The export store is independently locked; no source expiry/recovery/deletion runs during copying. Generated blobs stream through bounded buffers with≤16MiB/file/4GiB aggregate,30s copy deadline and≥10GiB remaining disk headroom. Ready blobs must match their recorded length/hash. Pending/failed metadata and present bytes remain preserved rather than guessed complete. Empty stores are supported. Every copied blob, index and journal is hash-bound in the finite backup receipt; links, extra files, modified bytes and unknown versions fail closed.

Restore verifies the source, copies into an exclusive private staging directory, verifies the copied tree and executable journal compatibility, fsyncs files/directories and publishes with no-replace atomic rename. Existing state cannot be overwritten. Compatibility runs the current journal decoder/recovery only on bounded disposable private copies; it never adopts or modifies the sealed backup or the working destination. It starts no application, enrolls no authority, replays no work and deletes neither the original archive nor a live source. An error after publication is not proof of absence: inspect/verify the destination, never overwrite it blindly. The isolated restore test confirms unresolved native inference remains uncertain and the owner's explicit export is readable.

Current `verify-backup` also performs that executable compatibility check and returns `journal_compatible:true` only after rechecking the original sealed bytes. A journal schema number and valid hash alone are insufficient: decision checkpoint versions can evolve within schema9. Unsupported decision formats remain preservable byte-verified backups, but cannot pass compatibility or publish restored state. Earlier artifacts may provide byte-only verification; use them only with their retained original compatible backup, never treat their successful hash check as permission to adopt newer state. This check does not establish native terminality, installation permission or runtime readiness. Explicit schema7/8 migration paths retain their separate maintenance-hold behavior.

These bundles do **not** include enrollment/configuration, credential storage, an installed release or launchd state. They are not yet the complete upgrade/rollback workflow. Do not point any utility at Fios's database. Protected installed old/new/old recovery, complete enrollment/credential preservation, maintenance handling and uninstall preservation remain outstanding before rollout; the development-only artifact rehearsal below is not that acceptance.

## Disposable old/new/old development artifact rehearsal

```sh
node scripts/check-platform-upgrade.mjs --isolated --old /ABSOLUTE/REVIEWED_OLD_RELEASE --old-sha256 REVIEWED_OLD_RECEIPT_SHA256 --new /ABSOLUTE/REVIEWED_NEW_RELEASE --new-sha256 REVIEWED_NEW_RECEIPT_SHA256
```

Requires two distinct independently reviewed development receipts and strict finite artifact verification; active/complete production manifests are not accepted. Builds a local fixture helper, creates only generated private temporary state and starts each artifact's observation-only manager sequentially. It verifies old→new→old startup with one unresolved native claim and an explicit owner export retained, refusal of live-manager snapshots, stopped old backup→new verification/fresh restore→new/old startup, and future schema9 rejection without database-byte mutation. Every owned manager is terminated/reaped before another instance opens that SQLite file; no installed supervisor, launchd/native application, SSH, runtime object, model call, production state or native enrollment is selected. Failed/unreaped children retain private state rather than deleting a live writer's directory.

Actual rehearsal passes against the historical `f59bc3a…` and current `59b7d8de…` development packages; both use schema7. The current CLI's raw observation export also works against both manager versions. This is **same-schema cross-artifact recovery**, not a schema migration, installed rollback, interpreter/configuration recovery or T050 completion. No native installation/rollback/uninstall is performed or authorized by this command.

## Source-only runtime enrollment construction

The fixed installed-manager runtime factory and strict version2 policy schema are described in [runtime-enrollment.md](../../../specs/009-studio-platform-agent/contracts/runtime-enrollment.md). It binds root-reviewed manager/Docker/native CLI/daemon bytes and the account home, refuses development images and caller socket/path/environment overrides, and performs no CLI or daemon operation during construction. It is not wired into the public execution path. The Docker multicall alias cannot be followed as an immutable executable: a separately reviewed installer must stage the fixed root-owned `bin/docker` artifact with its full provenance/dependencies. The current development package does not contain that installation artifact or mint runtime policy. No root policy/app ownership/CLI copy/daemon/native admission or installation was changed by its tests.

## Operational gate

A runnable supervisor is not native acceptance. Privileged operations require user execution and distinct scoped approval, one host at a time. Keep services/data intact until identity, backup, rollback and uncertainty preservation have been reviewed. Never remove unrelated containers or the detached legacy volume. Do not infer idle/completion from reboot, age, local child absence or cancellation.

Current source packages use schema9 and retain native dispatch scope/outcome and native lineage correlation metadata. Historical schema7 receipts above remain historical, not compatible inputs for the current development manifest verifier or evidence of migration. Ordinary startup and backup verification refuse schema7 unchanged; use the reviewed schema7 CLI for its stopped backup and the explicit copy-only migration below. Native quiescence reconciliation, complete installed rollback/uninstall and installed acceptance remain open.

### Explicit schema7/8→9 recovery staging

Use the reviewed schema7 CLI to make a stopped full `backup-state` bundle, then review its SHA256 and retain that artifact, original state and bundle. The new CLI accepts only that same-host/UID verified input:

```sh
studioctl --state /ABSOLUTE/REVIEWED_SCHEMA7_BACKUP migrate-state-seven --sha256 REVIEWED_BACKUP_SHA --to /ABSOLUTE/NEW_PRIVATE_STATE
```

This verifies the source/copy hashes and exact legacy SQL/ownership before converting only the unpublished copy, preserves unresolved ownership and request history, and publishes with an opaque `migration-hold.json`. The manager suppresses even code-supplied task, session and native-control ports while that marker exists; there is no IPC operation to clear it. Unknown old native scope stays unknown. No controller/app/runtime/model is started. The original schema7 backup remains usable by its reviewed schema7 CLI; an old controller must refuse the evolved schema9 file rather than downgrade it. Native installation/admission approval and hold release remain separate work.

Backup format3 preserves the opaque hold plus optional service-recovery bytes. Restore verifies the sealed copy before publishing a working directory with fresh empty writer/store lock identities. The returned input receipt identifies the sealed backup, not a working namespace after initialization; use `backup-state` to seal and verify a fresh bundle from restored state. A cold restore can be backed up before controller/store startup. SQLite WAL recovery occurs only in a bounded private snapshot under the stopped-writer fences, never in a writable connection to the original journal. Existing backup formats1/2/3 remain readable for current schema9. Schema7/8 are accepted only through their explicit stopped-copy migration commands. For schema8 use `migrate-state-eight` with its reviewed original backup; `plan-rollback-eight` reviews only the matching old artifact and backup.

An isolated old7/new9/old7 rehearsal uses `check-platform-upgrade.mjs --migrate-seven`; old8/new9/old8 uses `--migrate-eight`. Default release validation remains schema9-only. Legacy manifest acceptance is an explicit readonly rehearsal option, never an installation/profile authority. These development artifacts do not establish whole-repository/native provenance or installed acceptance.

The cross-schema rehearsal passes with old manifest `dfbb3fc17527de288f10af4f687af6a14f7e7f4273536862afc6f833da31252b` from source `45b3e3e` and new manifest `40fabeffa425acc266219867bc322eb56a4af37638ee720ffde30980f60f03b8` from implementation `28d80fa`. It verifies old7 backup production, held8 migration/rebackup/restore and old7 rollback from the retained original; incompatible/future startup does not rewrite the database. See the feature validation record for exact declared-input hashes and fixture limits. Both are incomplete, inactive development artifacts; this is T050 source recovery evidence, not installed rollout or native acceptance.


## Uninstall workflow review

```sh
node scripts/install-platform.mjs plan-uninstall --release /ABSOLUTE/RELEASE_DIRECTORY --sha256 REVIEWED_MANIFEST_SHA256 --host fios-edge-a.lab --state /ABSOLUTE/PRIVATE_PLATFORM_STATE --to /ABSOLUTE/PRIVATE_PARENT/NEW_BACKUP
```

This read-only plan orders current status review, an operator stop of supervisor/manager, a stopped-state backup, enrollment-removal review and retention of state/exports/credentials/release artifacts. Its two proposed CLI commands are `status` and `backup-state`; execute them at their numbered steps, with the manual stop between them. Planning executes neither command and creates no backup. The existing backup CLI checks stopped writers when actually run.

The result remains `blocked`: installed enrollment removal is not implemented, no privileged command is issued, and no uninstall or data deletion occurs. This makes the data-preservation workflow reviewable without claiming T049’s installation/uninstall execution is complete.

Stopped-state backup now holds the fixed supervisor → serving-custody → manager
writer locks for its entire journal/export snapshot. A retained custody module
refuses backup even when the manager is stopped; no controller/custodian may
open while that fence is held. Restore creates fresh empty custody/other writer
locks and does not copy `serving-custody.json`, which is volatile peer metadata,
not a portable capability. These fences do not prove native inference/device
terminality, adopt an orphan, authorize installed updates or clear uncertainty.
Retain independent native reconciliation and reviewed installation/rollback gates.


The source-only reviewed native launch document now supports a separate fixed
agent-owned artifact path through schema2:
`/Library/Application Support/Fios/Studio/native/bin/mlx-serve`. Schema1 retains
the historical vendor-bundle server identity. The GUI stays separately pinned at
its existing bundle, providing the reviewed settings source rather than server
ownership. See [native launch inputs](../../../specs/009-studio-platform-agent/contracts/native-serving-launch-inputs.md)
for the exact metadata schemas and census scopes. This does not add native files
to the current development package, create root metadata, install/activate a
server or approve GUI handover. Complete immutable native dependencies, native
admission/reservations and separately reviewed installation are still required;
public native actuation factories and install plans remain gated.


Installed manager startup now has a read-only metadata/health path. A single
retained worker loads only the protected reviewed configuration; developer images
return unconfigured before installed policy access. It does not read serving
credentials/Preferences, issue native control or enable lifecycle/recovery/jobs.
Status reports native_health_source and, for fresh present observations, health
separately from credential readiness. See the launch-input contract above.
Positive installed behavior remains unexecuted and requires reviewed installation.


The source-only protected Python policy/factory composition is described in [python-runtime-enrollment.md](../../../specs/009-studio-platform-agent/contracts/python-runtime-enrollment.md). It binds the actual fixed installed manager and root-reviewed interpreter/manifest/context at fixed paths. Metadata decoding/private candidate receipts cannot construct that opaque policy. Complete byte review precedes a separate off-loop fixed metadata factory; public startup wiring and positive installed acceptance remain gated. No policy, interpreter tree, service or native admission has been installed/enabled by this source code.

The source-only [sandbox image/runtime factory](../../../specs/009-studio-platform-agent/contracts/sandbox-enrollment.md) binds a fixed protected image policy to the installed runtime and resource policies before constructing the existing executor. No policy writer, public execution startup, image import/pull, installation or native admission is enabled. The operator approved exact development image `sha256:0406a8451a382eef038d8ac37035ccfb4e2a1e4e7b22c4a349fd9c4648a77c0b` only; see the [decision and readonly verification](../../../specs/009-studio-platform-agent/sandbox-image-approval.md). Protected enrollment, activation and installed positive acceptance remain pending; the production approved-image list is still empty.


Stopped-state backups may optionally include the six fixed policy/enrollment
filenames using `studioctl --state STATE backup-state --configuration CONFIG
--to NEW_BUNDLE`. Version4 bundles preserve opaque bytes, original owner/mode and
explicit absence, with64KiB per-file bounds. Verification binds the private
configuration subtree to the reviewed backup digest. Restoration copies it to
`NEW_STATE/configuration/` as user-owned mode600 data; it never writes installed
root policy or Keychain data. Missing/empty/invalid enrollment bytes remain
missing/empty/invalid. Programs and credential recovery must be retained
separately. Failed backup/restore copies are retained privately for diagnosis;
only a verified complete bundle is a recovery point. This does not complete the
protected installation/rollback/uninstall or native acceptance requirements.

The installer can now propose the configuration-preserving backup explicitly:

```sh
node scripts/install-platform.mjs plan-backup-config --release /ABSOLUTE/REVIEWED_RELEASE --sha256 REVIEWED_MANIFEST_SHA --host fios-edge-a.lab --state /ABSOLUTE/PRIVATE_STATE --configuration /ABSOLUTE/CONFIGURATION_DIRECTORY --to /ABSOLUTE/PRIVATE_PARENT/NEW_BACKUP
```

`plan-uninstall-config` accepts the same arguments and puts that exact backup
command after the manual stopped-writer step. Both commands only review paths
and emit fixed program/argv proposals; they read no enrollment contents and
create no backup. The selected packaged CLI checks and captures the six fixed
documents when the operator executes the proposal. Configuration bytes remain
opaque and independently unverified during planning. These options do not
capture credentials, installed programs or launchd state, remove enrollment or
authorize installation. The original `plan-backup`/`plan-uninstall` workflows
continue to preserve state/exports without configuration.


Development platform/runtime composition can be copied into one new private
review directory without executing either candidate:

```sh
.venv/bin/python -I -B scripts/compose-platform-candidate.py --platform /ABS/PLATFORM_RELEASE --platform-sha256 PLATFORM_SHA --runtime /ABS/PYTHON_RUNTIME --runtime-sha256 RUNTIME_SHA --output /private/tmp/PRIVATE_PARENT/NEW_CANDIDATE
.venv/bin/python -I -B scripts/check-platform-composition.py --candidate /private/tmp/PRIVATE_PARENT/NEW_CANDIDATE --sha256 COMPOSITION_SHA
node scripts/install-platform.mjs plan-composition --candidate /private/tmp/PRIVATE_PARENT/NEW_CANDIDATE --sha256 COMPOSITION_SHA --host fios-edge-a.lab
```

Use canonical absolute private temporary paths. Composition requires matching
raw release-template and lock hashes, bounds copying to 11,000 files/1 GiB,
requires 10 GiB free headroom and retains incomplete copies. Independent review
checks the exact file/directory surface and measured component bytes. It does
not execute candidate programs or establish atomic installed custody. The host
plan remains blocked, emits no privileged commands and performs no writes.
Development approval, enrollment, installation, activation and native authority
remain false. Credentials and protected installation are not implemented by
this composition. Packaging now declares all four transitive Python review
helpers among its 190 source inputs; historical 186-input packages retain their
original provenance scope.

The development release checker accepts `--source /ABS/CLEAN_CHECKOUT` after
its existing `--isolated --release ... --sha256 ...` arguments for current
190-input packages. It checks the exact Git revision, clean checkout and shared
declared source projection before running any packaged program, then rechecks
that source after the private startup rehearsal. Its receipt reports this
selected-input scope explicitly; it does not attest whole-native build inputs
or installed custody. Without `--source`, existing artifact-only review behavior
and historical package checks remain unchanged.


`propose-first-install` accepts the same candidate/hash/host arguments as
`plan-composition`. It emits a blocked review proposal containing fixed
`/bin/mkdir` and `/usr/bin/install` argv, exact source/destination paths,
SHA256, byte count and mode for every proposed copy. The destination is a new
`/Library/Application Support/Fios/Studio` prefix, with Python at
`python/runtime`; review-only template data is excluded. Directories are
ordered parent first and created without `-p`, so an existing prefix must not
be reused. The protected parent must already be separately reviewed.

These command records are proposals for later operator execution, not an
executor or installation authorization. Current development components remain
blocked; no approval is inferred from their hashes or the sandbox image
approval. Separate release/host/operator review, a protected parent, absent
prefix, stopped writers/unregistered jobs, serialization and complete before/
after hash verification are mandatory. Failure means stop and retain partial
new data for diagnosis. The tool does not inspect a remote destination or
claim these preconditions were met. It writes no protected paths, policies,
credentials or state and proposes no launchd registration, process operation,
SSH, reboot or inference. Upgrade/switch/removal and credential installation
remain unfinished; this proposal does not complete T049.


`propose-artifact-uninstall` also accepts candidate/hash/host arguments. Its
blocked proposal lists only exact reviewed artifact paths with required
installed owner/mode/size/hash checks, followed by deepest-first nonrecursive
`rmdir` commands. It never proposes recursive removal, globbing, pruning or
removal of state, exports, credentials, enrollment or unrelated files. Missing,
changed or nonempty paths require stopping and retaining data for review.

The operator must separately approve removal, verify stopped-state/configuration/
program backups, reconcile native child custody, stop writers, remove or
persistently disable the reviewed launchd registrations and serialize the
transaction. The tool neither checks a remote installed tree nor performs any
of these actions. Registration and enrollment removal remain separate,
unimplemented steps; this artifact-only proposal does not claim full uninstall
or T049 completion. A private fixture redirects only the data operations into
a disposable user-owned tree and verifies that unknown/enrollment/state bytes
survive; it supplies no root ownership or native-terminal evidence.


`propose-python-enrollment` accepts candidate/hash/host plus `--uid SERVICE_UID
--state ABS_STATE --review-sha256 REVIEW_IDENTITY`. It derives the existing
strict version1 Python policy fields from the checked manager/runtime/template/
lock/policy bytes. The supplied review identity is correlation metadata, never
approval. The result contains exact serialized candidate bytes and their hash;
it writes no installed policy, state or credentials and remains blocked.

`stage-python-enrollment` adds `--to ABS_NEW_PRIVATE_BUNDLE`. The destination
must be a new directory under a canonical private temporary parent, outside
the input composition. It writes `python-enrollment.json`, the original
`review.json` proposal and a final `stage-receipt.json`; source component bytes
are rechecked before success. Existing destinations refuse; failed/partial
copies remain for diagnosis. These user-owned files cannot construct an opaque
installed policy. Protected installation, native admission and activation
retain their separate gates.

The optional `--enrollment-proposal ABS_REVIEW --proposal-sha256 SHA` arguments
to `scripts/check-platform-worker-runtime.mjs` exercise the actual Swift policy
decoder against the genuine copied runtime and manager identities. The check
also confirms private-image policy-load refusal and malformed account/host/
authority-field rejection. It runs metadata only, with network denied and zero
model POSTs; it does not test root protection or installed positive behavior.


`propose-python-policy-install` accepts candidate/hash/host plus `--bundle
ABS_PRIVATE_BUNDLE --bundle-sha256 REVIEWED_STAGE_RECEIPT_SHA`. It independently
checks all three staged files, their exact surface/owner/modes/hashes, the typed
boolean receipt fields, the selected Studio and a freshly derived policy for
the current components. Stale, changed, mixed-host or malformed bundles refuse.

The blocked result proposes exactly one fixed root-owned mode0644 copy to
`/Library/Application Support/Fios/Studio/python-enrollment.json`. It performs
no copy and authorizes no command. Separate runtime-enrollment approval, a
reviewed merged release, the actual protected manager/runtime/context, stopped
writers and backups, an absent destination and source/destination verification
remain operator prerequisites. This does not inspect a remote installation,
register a service, activate inference or complete protected acceptance.

`propose-python-policy-removal` uses the same candidate, host and pinned staged
bundle arguments. It revalidates that bundle and proposes removal of exactly
the fixed Python enrollment file, conditional on matching installed bytes,
root ownership, mode and file type. It never removes parent directories,
credentials, state or exports. Separate operator removal approval, verified
stopped backups and stopped writers remain required; independent native
inference uncertainty must survive removal. The command only prints a blocked
proposal and performs no protected operation.

`propose-config-install` takes the same release/hash/host and pinned
`--bundle`/`--bundle-sha256` arguments as `verify-config`. After verifying the
review and both rendered plists it proposes two fixed root-owned0644 copies
to the declared LaunchDaemons/LaunchAgents destinations. It performs no copy,
registration or activation. Approval, exact installed context, stopped backups,
protected parents, absent destinations and source/destination rechecks remain
operator prerequisites. Preserve partial failures and independent uncertainty.

`propose-config-removal` uses the same pinned bundle to name exactly those two
installed plist files and their required hashes, owners and modes. Its blocked
proposal requires separately reviewed registration removal or persistent
disablement before file removal. It never invokes launchctl, removes a parent
directory or changes credentials/state/exports/native uncertainty. A stopped
verified backup and explicit operator execution remain required.

`propose-registration-activation` and `propose-registration-removal` accept
release/hash/host, the pinned configuration bundle and `--uid` with the explicitly
reviewed service-account UID. They verify the bundle and derive only the two
fixed Studio labels. Configuration-array ordering never selects a launchd domain.

Activation proposes enable then bootstrap for the system supervisor and selected
Aqua-session adapter. It requires separate native installation/activation approval,
a complete reviewed release, exact account/session context, verified stopped
backups, absent registrations and protected installed plist bytes. Removal
proposes disable then bootout for those exact labels. Admission must already be
closed, and owned native children must be absent or in separately reviewed
retained custody; reconciliation never clears independent inference uncertainty.
Verify all platform writers are absent and take the stopped configuration/state
backup before removing any files. No blanket enable is a rollback: preserve and
restore only the recorded previous registration/disabled states after review.

Both commands print blocked, unauthorized proposals and invoke no launchctl,
change no durable desired service state and write no registration, credentials
or state. Partial failure stops the transaction with backups/uncertainty retained.

`propose-enrollment-removal` reviews the composed candidate/hash/host plus
`--configuration ABS_PRIVATE_CONFIGURATION_BACKUP --configuration-sha256
REVIEWED_MANIFEST_SHA`. This is the `configuration` directory from the existing
opaque configuration snapshot format, not a claim that a full stopped backup
has been verified. It checks the fixed six-name manifest, private file metadata,
exact bytes/hashes, presence/absence and source stability. Document contents
remain opaque and are never printed or treated as enrollment authority.

The blocked proposal names only present fixed enrollment files with required
installed root ownership, original mode, size and hash. No parent directory,
credential, state/export or unrelated file is removed. Separate removal approval,
exact installed context, disabled/removed registrations, stopped writers,
retained native custody/absence and independently verified complete stopped
backup remain prerequisites. The tool executes no removal and cannot establish
those installed prerequisites from the snapshot.

`propose-enrollment-restore` reviews the same fixed six-document opaque snapshot
and emits root-owned file-copy proposals for present originals only. It requires
root original ownership and preserves the recorded mode/size/hash; absent entries
must remain absent. Every destination must be absent: no overwrite or cleanup is
proposed. It executes no install, registration, credential or native operation.
Version1 snapshots record no group; version2 snapshots preserve the observed
original GID and require the fixed protected group0 for a restoration proposal.
Both versions leave authenticated origin host unverified. Independently review
the originating host/previous release and, for version1, previous group `wheel`
before execution. New readers retain version1 support; keep the original prior
release backup for rollback rather than assuming an old binary reads version2. Preserve failed configuration/state/credentials for diagnosis, keep
writers stopped and require separate rollback approval. This is partial T049
review tooling, not implemented or accepted installed rollback.
