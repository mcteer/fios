# Temporary sandbox contract v1

## Enforced defaults and maxima

| Resource | Default | Maximum / rule |
| --- | --- | --- |
| Active sandboxes |1 requested |2 per host, including creating/reconciling reservations |
| CPU |1 core-equivalent |2/job,4 aggregate; reject if host CPU>80% or observation unavailable |
| Container memory |512MiB |2GiB/job,4GiB aggregate; swap disabled; tmpfs charged inside this cap |
| Workspace |128MiB tmpfs |256MiB; `/tmp`64MiB; readonly root; no host/named-volume writable workspaces |
| Processes |64 |64/job, nonroot UID, no privilege/namespace escalation |
| Owner lease |30s |Renew every10s; expiry/revocation irreversible |
| Absolute task lifetime |900s |1800s; renewals cannot extend it |
| Admission queue |0 |Reject immediately when no safe capacity; no hidden wait/retry/failover |
| Input bundle |4MiB |Generated filenames only, no symlink/archive extraction or host paths |
| Task output/export |16MiB/job |Explicit bounded byte stream; no arbitrary filesystem traversal |
| Images |Approved cached arm64 digest |No runtime pull/build, mutable tag or unapproved entrypoint |

Memory admission requires fresh normal pressure and known thermal state below serious, verified VM remaining capacity and system available memory sufficient for `max(16GiB,20% physical RAM)` native headroom **plus all full outstanding sandbox and512MiB/model-worker reservations plus the new reservation**. Treat this conservative double-counting as deliberate: do not reclaim a reservation merely because a sampled usage figure includes it. Missing critical measurements or unknown preparing work reject; GPU may be unsupported with an explicit reason and is never an idle proxy. Disk requires≥10GiB free after bounded retained export commitments. The trusted resource snapshot keeps raw `diskFree` separate from `diskCommitted`: all full retained export bytes (including ready/failed/pending records) plus queued publication declarations are charged before admission and preserved across VM refresh. Ready bytes remain conservatively charged until proven retention cleanup because a recent filesystem sample can predate publication; already allocated ready bytes may therefore be double-counted deliberately. Publication also performs its own fresh free-space check. Never derive these commitments from task-supplied measurements. Preserve existing VM limits; do not raise them.

The native resource envelope must be established at enrollment; external/unmanaged allocation cannot be globally controlled by this manager. Document remaining host-wide pressure risk, reserve margin and enforce sandbox caps; do not promise immunity to arbitrary unrelated allocations. If memory pressure warns/criticals, thermal reaches serious, VM capacity is exhausted or critical telemetry is lost, stop new admissions and revoke/stop newest owned sandbox first until policy is safe; never unload or kill native inference to reclaim resources. Pressure/cap-loss is observed on the2s cycle and starts revocation within the next cycle. Model-only jobs are separately capped at2/host and native worker memory is reserved/reaped under the model-access contract; the2-sandbox limit is not an exemption for unlimited platform tasks.

## Isolation and mediated model channel

Docker create configuration is fixed-policy: `network=none`, no ports, host networking/IPC/PID/devices/mounts/socket, nonroot, readonly root, capabilities dropped, no-new-privileges, process/memory/CPU/tmpfs limits and bounded logging disabled for raw task output. No external DNS or Internet access, including package installation. Only pre-provisioned immutable image dependencies. Host CLI uses explicit local OrbStack Unix socket and sanitized environment; caller cannot supply Docker flags.

A fixed image runner communicates using manager-attached stdin/stdout frames under the control-plane begin/chunk/end contract (≤64KiB frame,≤32KiB decoded chunk,10s input transfer/30s artifact transfer deadlines). It can emit bounded status/output/export/model-request frames. The channel's runtime/job identity is fixed by creation, never chosen by a frame. Treat the runner and all frames as untrusted; malformed/oversized/unknown/parallel management requests revoke the job. Model frames enter the separately scoped Pydantic worker; no network bridge/proxy/Docker socket is mounted into the sandbox. Ordinary task stdout/stderr cannot be mistaken for trusted control messages; frame origin remains the untrusted job capability and gains no extra privilege.

## Creation, idempotency and cleanup

1. Authenticate owner, validate immutable profile/input/budgets and fresh observations. In one transaction reserve capacity and persist UUID/input hash/creation nonce/absolute deadline before any runtime action.
2. Check deterministic owned container name, image and nonce. Same UUID/same request returns existing status; conflicting UUID rejects. Uncertain prior create is reconciled, never replayed on another host or with another image.
3. Create hardened container, persist runtime ID, attach bounded channel, then start only once. If creation/start result is lost, inspect by stored identity/name/nonce. Never infer non-creation from client timeout alone.
4. Completion/cancel/lease expiry/restart/pressure revokes channel/model grants immediately, persists cleanup obligation and stops the owned process. Grace10s then kill; target≤60s total removal with available runtime. Native model computation may outlive sandbox cancellation and retains separate ownership.
5. Prove container stopped/absent and delete only owned ephemeral resources before releasing reservations. Runtime unavailable → cleanup pending and reservation retained. On recovery enumerate only exact owned names/IDs/nonces/images and reconcile before new admission. Conflicting identity, forged label or unknown container ownership requires operator review, never global prune.
6. Export only explicitly requested bounded artifacts before final job completion; use generated host-side private paths and opaque download IDs, never sandbox paths as host paths. Retain exports up to24h/256 jobs/4GiB; deletion of sandbox does not delete unexpired exported artifacts.

## Bounds on control work

Runtime probe timeout2s; lifecycle command timeout10s; kill/reap local CLI child≤2s after timeout. At most2 lifecycle subprocesses/host; reconciliation batch≤32 objects/cycle and≤2s per inspection, overall cleanup budget60s for the at-most2 owned active sandboxes. Slow/unavailable runtime reports pending, never masks timeout as success. Runtime CLI subprocess termination is not proof that the Docker operation did not occur. Image inventory/admission never executes tasks or inference.

Tests use isolated runtime resources and a deliberately unrelated sentinel container/volume to prove no adoption/deletion. Normal CI never touches existing Fios containers, personal files, native settings or production SQLite.
