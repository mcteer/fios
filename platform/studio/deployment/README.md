# Native release / installation review

**Development-only; installation, rollback and uninstall execution are not implemented or authorized.** No launchd job has been installed. Native lifecycle and inference remain disabled. Templates are not runnable enrollment records.

## Build and verify

On the pinned arm64 Swift6.4 build/SDK27.0/System SQLite3.54.0 toolchain:

```sh
node scripts/package-platform.mjs --output /ABSOLUTE/NEW_RELEASE_DIRECTORY
```

The packer uses clean scratch builds, fixed source/debug path maps, no UUID/debug metadata, fixed development ad-hoc identities and explicit source/artifact hashes (including the installer/state-plan review tooling in the source hash). It includes no credentials, environment files, interpreter tree or approved sandbox image. Nine artifacts and a canonical receipt are staged; package_complete remains false. Native inventory hashes are observations, not all-client coverage attestation. The Docker multicall binary hash is **not** an OrbStack lifecycle CLI authorization.

Read-only, single-host review:

```sh
node scripts/install-platform.mjs plan --release /ABSOLUTE/RELEASE_DIRECTORY --sha256 REVIEWED_MANIFEST_SHA256 --host fios-edge-a.lab
```

The expected digest must come from the reviewed build receipt, not an untrusted package's own claim. The reviewer verifies the finite tree, receipt and every byte/mode, rejects links/extra files, and emits explicit blockers. Current packages cannot produce privileged commands. No SSH, launchctl, app/runtime lifecycle, inference, RDMA/network change or deletion is performed. Unknown/apply/rollback/uninstall commands fail closed. This is a review scaffold, **not completion of T049**.

## Offline journal/export snapshot and fresh-directory restore

After separately authorized shutdown of **both supervisor and manager**, the native CLI supports:

```sh
studioctl --state /ABSOLUTE/PRIVATE_PLATFORM_STATE backup --to /ABSOLUTE/PRIVATE_PARENT/NEW_SNAPSHOT.sqlite
```

The utility verifies the FIS9 platform marker and schema8, holds exclusive supervisor-then-manager locks to prevent watchdog respawn, copies source bytes under the writer fence and recovers WAL only in a bounded private snapshot, uses a finite≤64MiB/10s SQLite backup, fsyncs and returns only schema/length/hash. It never overwrites a destination. Restoring the isolated test snapshot retains unresolved inference claims; startup marks them uncertain rather than replaying execution. Future ownership schemas are rejected before journal mutation.

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

The export store is independently locked; no source expiry/recovery/deletion runs during copying. Generated blobs stream through bounded buffers with≤16MiB/file/4GiB aggregate,30s copy deadline and≥10GiB remaining disk headroom. Ready blobs must match their recorded length/hash. Pending/failed metadata and present bytes remain preserved rather than guessed complete. Empty stores are supported. Every copied blob, index and journal is hash-bound in the finite backup receipt; links, extra files, modified bytes and unknown versions fail closed.

Restore verifies the source, copies into an exclusive private staging directory, verifies the copied tree, fsyncs files/directories and publishes with no-replace atomic rename. Existing state cannot be overwritten. It does not open the restored database, start an application, enroll authority, replay work, delete the original archive or remove any live source. An error after publication is not proof of absence: inspect/verify the destination, never overwrite it blindly. The isolated restore test confirms unresolved native inference remains uncertain and the owner's explicit export is readable.

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

Current source packages use schema8 and retain native dispatch scope/outcome metadata. Historical schema7 receipts above remain historical, not compatible inputs for the current development manifest verifier or evidence of migration. Ordinary startup and backup verification refuse schema7 unchanged; use the reviewed schema7 CLI for its stopped backup and the explicit copy-only migration below. Native quiescence reconciliation, complete installed rollback/uninstall and installed acceptance remain open.

### Explicit schema7→8 recovery staging

Use the reviewed schema7 CLI to make a stopped full `backup-state` bundle, then review its SHA256 and retain that artifact, original state and bundle. The new CLI accepts only that same-host/UID verified input:

```sh
studioctl --state /ABSOLUTE/REVIEWED_SCHEMA7_BACKUP migrate-state-seven --sha256 REVIEWED_BACKUP_SHA --to /ABSOLUTE/NEW_PRIVATE_STATE
```

This verifies the source/copy hashes and exact legacy SQL/ownership before converting only the unpublished copy, preserves unresolved ownership and request history, and publishes with an opaque `migration-hold.json`. The manager suppresses even code-supplied task, session and native-control ports while that marker exists; there is no IPC operation to clear it. Unknown old native scope stays unknown. No controller/app/runtime/model is started. The original schema7 backup remains usable by its reviewed schema7 CLI; an old controller must refuse the evolved schema8 file rather than downgrade it. Native installation/admission approval and hold release remain separate work.

Backup format3 preserves the opaque hold plus optional service-recovery bytes. Restore verifies the sealed copy before publishing a working directory with fresh empty writer/store lock identities. The returned input receipt identifies the sealed backup, not a working namespace after initialization; use `backup-state` to seal and verify a fresh bundle from restored state. A cold restore can be backed up before controller/store startup. SQLite WAL recovery occurs only in a bounded private snapshot under the stopped-writer fences, never in a writable connection to the original journal. Existing backup formats1/2 remain readable for schema8; schema7 is accepted only by explicit migration.

An isolated old7/new8/old7 rehearsal uses `check-platform-upgrade.mjs` with `--migrate-seven`; default release validation remains schema8-only. Legacy manifest acceptance is an explicit readonly rehearsal option, never an installation/profile authority. These development artifacts do not establish whole-repository/native provenance or installed acceptance.

The cross-schema rehearsal passes with old manifest `dfbb3fc17527de288f10af4f687af6a14f7e7f4273536862afc6f833da31252b` from source `45b3e3e` and new manifest `40fabeffa425acc266219867bc322eb56a4af37638ee720ffde30980f60f03b8` from implementation `28d80fa`. It verifies old7 backup production, held8 migration/rebackup/restore and old7 rollback from the retained original; incompatible/future startup does not rewrite the database. See the feature validation record for exact declared-input hashes and fixture limits. Both are incomplete, inactive development artifacts; this is T050 source recovery evidence, not installed rollout or native acceptance.
