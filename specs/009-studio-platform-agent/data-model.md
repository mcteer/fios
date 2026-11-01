# Data model: Studio platform agent

Required data model; implementation remains partial. The separate development journal is FIS9/schema9. Schema8 introduced native dispatch scope/outcome metadata; schema9 adds `native_lineages`, keyed by `(job,attempt)`, retaining scope hash, exact native instance/request/root identity, peer PID/start/path/hash, last accepted sequence/time, consumer clock and sticky refusal state. Full-width native tokens are canonical decimal strings. A checkpoint is correlation metadata, never native terminal/admission proof or a restored live observation. Unresolved records remain independent of worker slots and never expire. Completed correlation metadata is pruned only with its eligible job tombstone after no unresolved inference or unreaped worker remains.

One manager exclusively owns the separate per-Studio SQLite journal; Fios SQLite is never opened. Existing schema9 is validated in a bounded private snapshot before any original recovery write. Ordinary startup refuses schema7/8 unchanged. Explicit `migrate-state-seven` and `migrate-state-eight` accept reviewed same-host/UID stopped backups and convert only new private copies to schema9, preserving original scope/history/uncertainty and publishing with a durable execution/native-control hold. Unknown old lineage is never fabricated. Backup format3 preserves the hold. Rollback uses the matching retained old artifact and original stopped backup, preserving the evolved copy. Production enrollment, complete native reconciliation and installed acceptance remain unfinished.

## Shared validation rules

- Control/private-task protocol versions remain `1`; readonly activity observations use version `2`, with exact legacy version1 accepted only as unknown/unsupported diagnostics. Unknown fields/versions and duplicate JSON keys reject. Identifiers are canonical UUID strings, except enrolled `host` (ASCII1..128), `model` (exact UTF-8 1..1024 bytes), SHA256 (64 lowercase hex), and safe fixed enum values.
- UTC timestamps are integer milliseconds0..9007199254740991; monotonic durations govern live deadlines. On restart/sleep/clock discontinuity, leases and observations become invalid/uncertain until revalidated; elapsed wall time never proves native completion.
- Control JSON≤64KiB/frame, native raw observation≤1MiB, no prompts/results in state or audit. Identity/model metadata is bounded; no arbitrary executable paths, endpoint URLs or shell strings in job commands.
- State cardinalities:2 enrolled hosts initially,2 managed services/host,2 active sandbox slots/host plus2 model-only job slots/host (4 jobs total),2 live model workers/host with512MiB reserved each,32 unresolved manager-owned inference records/host,256 terminal job tombstones/host retained24h. Tombstone limit blocks new jobs until expiry/reconciliation, not premature duplicate-key reuse. Event journal≤10MiB/7days, whichever first; a bounded oldest-first rotation excludes unresolved ownership records.

## StudioProfile (immutable approved configuration)

`host`, serving endpoint SHA256, installed MLX/OrbStack executable/signature/artifact identities, native capability attestation hash, explicit OrbStack socket/CLI identity, nonroot service UID, role grants, approved image digests, exact model→local-native-ID mappings and resource envelope. Endpoint/address and paths are operator-installed policy, not caller/model input. No credentials in export or profile committed to Git. Failed/missing attestation leaves observation unsupported and admission disabled.

## ManagerEpoch / ManagedService

Manager UUID epoch and increasing sequence; monotonic startup/progress; watchdog starts within a10min window; desired state `running|maintenance|stopped`; observed state `starting|ready|waiting_session|waiting_credentials|stopped|degraded|unknown`. Service kind `mlx|orbstack`, process PID plus process-start identity and verified executable identity; PID alone never identifies a kill target. The kernel process-start token is opaque nonzeroUInt64, not UTCms and not constrained to JavaScript's safe-integer bound; internal service identities are non-Codable and any future wire token uses canonical decimal string form. Adjacent values above2^53 must retain distinct scope digests. Single-manager lock binds host/runtime. Manager restart invalidates old grants and marks outstanding native work uncertain.

Private metadata writer locks are distinct fixed `supervisor.lock`, `session.lock` and manager/SQLite locks. Supervisor/session share descriptor-pinned private0700 directory + same-UID single-link regular0600/no-follow/nonblocking/CLOEXEC lock validation, named-inode/directory checks and kernel flock; a link/FIFO/set-ID/permissive file cannot be treated as a singleton. Lock contents are not authority. Watchdog restart budget keeps its existing exact `boot`/`starts` JSON shape (no new format silently introduced), ≤4096 bytes, canonical boot UUID, ≤3 bounded integer strictly increasing monotonic start times. Validate histories even from another boot before reset; malformed/unknown/duplicate or unsafe file metadata refuses unchanged **before manager start**. File reads are bounded/no-follow/nonblocking with regular-file/UID/link/mode and identity-time brackets. A legitimate kernel boot change may reset only this restart policy; never native uncertainty or ownership.

The separate private `service-recovery.json` now writes version3 (≤4096 bytes).
It retains the existing exact profile/boot/clock fence and per-service restart
budget/pending UUID, plus optional `lastStarted` with exact keys `id`, `pid`,
`start` (canonical positive UInt64 decimal string), `sha256` and original `boot`.
The correlated started acknowledgement and pending-ID retirement share one
atomic durable write. Version1/2 state remains readable without fabricating a
receipt or stop operation; future writes use version3. Receipt identity is historical metadata,
not live process ownership, native completion or actuation authority. It is
retained across reboot and later not-sent operations. Stopped backups preserve
the entire file; incompatible downgrade must refuse rather than erase/drop it.

Version3 adds per-service bounded `stops` attempt timestamps and optional
`stopPending` with exact keys `id`, `receipt` (the original launch receipt) and
`desired` (`running|stopped`, never maintenance). Only MLX may hold this record;
launch-pending and stop-pending cannot coexist, and the stored receipt must
equal its historical last-started identity. Stop attempts are bounded to3/10min
with10s spacing, separately from start attempts. A code-issued one-use intent
and current durable desired state are required to reserve; no installed intent
issuer exists. Persistence precedes returning a dispatch request. After
reconstruction, only original-ID lookup or revocation is possible. Missing
actuator history stays unknown, and unresolved stop state blocks new launch
even after local process exit. A correlated not-sent/local-exit acknowledgement
retires only this service operation after durable write; native inference
claims and historical launch receipt remain unchanged.

## ResourceObservation / Reservation

Observation: host/epoch/sequence/sample time/age, physical bytes, conservative available bytes, memory-pressure `normal|warning|critical|unknown`, CPU load percentage, verified VM capacity/remaining headroom, disk free, thermal `nominal|fair|serious|critical|unknown`, optional GPU utilization and unsupported reason. No sensor value becomes zero merely because unavailable.

Reservation: job UUID, fixed CPU/memory/tmpfs/export allowances, lease expiry and state `reserved|committed|releasing|released`. Atomically compare observation freshness + active reservations and insert before launch. Model-worker reservation is512MiB before spawn and remains charged until the child is reaped; native request ownership remains separate if compute is uncertain. Full sandbox reservation remains charged until runtime absence is proven; a failed create with uncertain outcome does not release it. All sandbox temp data fits in its memory cap; no host disk quota is assumed for a normal volume.

## NativeObservation / OwnedInference

Native observation binds host + endpoint hash + native process epoch + manager epoch/sequence and coherent native source sequence/time. Coverage enum `all_clients|unknown|unsupported`; activity enum `idle|preparing|queued|active|unknown`; resident exact model nullable, per-model counts/ownership proof and transition flags. Missing data is not0. Multiple residents on the configured single-model host invalidate eligibility. Source authenticity, coherence, all-client scope and native non-preemptive policy are prerequisites to `idle`.

Owned inference: `(job_id,attempt)` with attempt0..3, exact model/host/endpoint, native correlation if provided, state `reserved|dispatched|uncertain|complete|not_sent`, timestamps and terminal proof. At most32 unresolved rows/host; full table returns `tracking_limit`, never fabricated native busy. Completion deletes/releases only its own ownership. Native all-client quiescence with matching process epoch and no pending ingress/queue can reconcile uncertainty; socket close, job deletion, timers and later successful requests cannot. Unknown external requests need not expose private client identifiers; native coverage/counts must still be authoritative.

## SandboxJob / Lease

Job UUID and authenticated owner, kind `sandbox|model_only`, immutable image SHA256 digest for sandbox jobs (null for model-only), approved fixed runner version, input hash (never raw code in journal), resource reservation, network policy fixed `none`, model grants, created/expiry times, owner lease, runtime container ID, birth-label nonce and state:

`reserved → creating → running → revoking → stopping → removing → removed`

Any uncertain create/stop/remove → `reconciling`, then verified next state; failure without proven absence retains cleanup obligation/reservation. Reject/complete status is separate from runtime cleanup. Lease30s, renewal every10s, total lifetime≤1800s; renewals cannot extend the absolute lifetime or an expired/revoked lease. Manager restart revokes grants and reconciles resources; it never resumes untrusted task execution automatically. Runtime outage reports cleanup pending; capabilities still expire. No job/inference replay on restart.

Model-only jobs use the same owner lease/absolute deadline, input/export and terminal retention bounds, but never enter container-creation states: `reserved→running→revoking→removed`. They consume a dedicated model-only job slot even when not currently dispatching inference; at most2 exist per host. No unbounded pool of idle jobs or Python children is permitted.

A deterministic container name includes host enrollment + job UUID; private creation nonce plus stored runtime ID, labels and approved image identify owned resources. Matching a label alone is insufficient. Explicit conflicting identity → operator reconciliation, not deletion. Duplicate job UUID with the same normalized request returns existing status; mismatch rejects. No automatic second-host retry.

## Artifact / OperationalEvent

Artifacts are opt-in exported byte streams,≤16MiB/job, up to256 retained jobs/24h (≤4GiB aggregate); no archives extracted or arbitrary paths accepted. Store under generated job-owned names in private export storage; content hash and owner metadata in DB. Downloads require the owner/operator; lease expiry removes sandbox access, not an approved export. No artifact body in diagnostics.

Events contain only safe time, host/job correlation, fixed action/state/error code and numeric counts. No prompts, code, reasoning, results, tool arguments, raw stdout/stderr, credentials or arbitrary native response body. Native diagnostics may be inspected only through a separate explicit private operator procedure, not routine logs.
