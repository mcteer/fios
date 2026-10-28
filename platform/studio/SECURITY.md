# Studio platform security boundary and audit

Development implementation, not a claim of native activation or container escape resistance against a compromised kernel/runtime. Read the feature contracts and validation record alongside this document.

## Authority

- Native management originates only in trusted host/operator code. A model response, task source, sandbox frame or tool-looking JSON does not confer a role. Separate accepting sockets fix role; peer UID is verified. Owner secrets authorize only their own job/artifact data, never management or endpoint selection.
- Socket roles are protocol separation, **not a security boundary against a fully compromised same-user host**. Such a process already has native user/runtime authority. A compromised root, kernel, OrbStack daemon or privileged installer is outside the sandbox containment claim. Production release/enrollment protections remain required.
- Task payloads cannot select a shell, argv, native URL, credentials, host, runtime socket, image tag or model alias. An approved canonical model/image/resource grant comes from trusted policy. Bootstrap policy remains unenrolled/closed.
- Sandboxes have no host control sockets. The internal model channel binds job, exact runtime ID and canonical request UUID, rejects replay/concurrency/fifth requests and does not accept task-selected policy/model/role/endpoint.

## Data and credentials

- Canonical random256-bit owner credentials remain in trusted client memory/stdin; only a UID/domain-separated SHA256 digest is durable. No automatic propagation to task code, model context, argv, environment, audit or routine errors.
- Model prompts/code/results/reasoning are not journal fields. Explicit exported artifact bodies are private workload data and are delivered only through owner/hash/length-verified generated IDs. No caller filenames or paths enter the artifact API.
- Journal/audit metadata and generic errors use safe IDs/enums/counts. Package staging copies an exact finite allowlist, not repository/environment trees. Neither packaging nor review resolves Compose credentials or reads .env.
- Trusted host access to files remains a host privilege, not cryptographic isolation from that host. Deliberate user inclusion of a secret in their own prompt/export is not something owner-token hashing can prevent.

## Execution and transport

- Python workers execute only the fixed installed module under pinned interpreter/metadata/policy checks and a minimal environment. No model tools, nested agents, retries or failover. Guard/actual-POST accounting and output budgets are independent of generated language instructions.
- Arbitrary task code executes only inside a temporary immutable-image, nonroot, read-only, network-none container: dropped capabilities, no-new-privileges, no host mounts/namespaces/devices/runtime sockets/credentials, bounded CPU/memory/PIDs and finite leases/output.
- Runner control descriptors are sealed with verified nondumpability before untrusted same-UID task code runs. The actual container fixture checks /proc/1/fd/0 access refusal. This closes a demonstrated descriptor exposure; it is **not** a general proof against future container/runtime/kernel escapes.
- Direct Docker attach uses a fixed owned full-ID path over a private authenticated Unix socket. Strict upgrade, multiplex and application framing; no subprocess transport, TCP listener, archive extraction or host shell.
- Optional direct VM metadata transport has only owned-ID inspect and fixed `/bin/cat` procfs create/start/completion routes under65533:65533, distinct from task UID65532. Exact parent isolation/resource limits and actual exec/container/exit are rechecked. Bounded strict headers/chunks/upgrades reject framing ambiguity, stderr and uncertain completion; an error fences repeats until parent absence. No arbitrary API method/path/argv or fallback.
- Shared-kernel coverage is a separate non-Codable reviewed profile/boot/architecture authority, never inferred from task data or fabricated empty inventory. No production issuer exists. Original cap/kernel times govern5s freshness; caching cannot re-date a source. Only fresh matching global-kernel proof allows the fixed config query without a redundant status process. Changed boot/clock permanently fences; failed queries cannot reuse old authority. Neither cgroup sums nor host RSS nor GPU readings establish whole-VM free capacity or inference idle.
- Finite IPC clients/frames/deadlines, mailbox queues, artifact operations/downloads and worker pipes prevent unbounded routine buffering. Backpressure revokes rather than replaying lost output.

- Fixed `studioctl export` contacts only the observation socket and emits the bounded raw frame with original generations/timestamp. Alternate remote commands/PTY context refuse before connection. This does not attest native coverage or establish effective SSH restrictions; no key, sshd configuration or SSH listener is installed/tested. Dedicated-key/environment/forwarding/host-key enrollment remains mandatory.
- Service force policy now consumes an operator-only confirmation bound to verified process identity, manager/native epochs, trusted affected-source digests and exact owned/unresolved IDs. Timestamps do not define the semantic scope. Unknown coverage, changed scope/identity, task role, replay, stale scope or either30s wall/monotonic expiry refuses. Caller-supplied scope digests are never trusted source authority.
- Drain policy requires persisted maintenance at its future integration seam, returns only owned-job revocation decisions, and refuses external/unknown/unmanaged disruption. It has dual60s deadlines, irreversible refusal/rollback/identity fencing, fresh readiness revalidation and no revocation of newly scoped jobs. Ready is not a native stop/quiescence permission; no lifecycle/source wiring is enabled by these pure policies.

## Recovery and incomplete safety gates

Local exit/removal/reboot/age/cancellation does not prove native inference completion. Durable pre-spawn intents and request-specific claims are independent of local cleanup. Unknown same-boot PID intents stay reserved unless a separately reviewed, complete historical parent/interpreter image census proves local absence. Census is startup-only and opt-in (not configured by default), UID-scoped metadata only, bounded and nonce/boot-bound; no guessed-PID termination. Missing visibility, live same-image foreign processes, changed images or stale proof retain the reservation. Local absence never clears native inference uncertainty. Future schemas fail closed without journal mutation. Verified offline journal/export bundles preserve native uncertainty and explicit owner exports under a supervisor-then-manager stopped-writer fence, preventing watchdog respawn during the snapshot. Fresh-directory restoration does not overwrite live state or start anything. This does not replace complete protected-release/enrollment/launchd rollback.

Readonly observation consumers bind both manager and native generations from separate trusted enrollment, not the frame being checked. A changed generation permanently fences that validator; a new timestamp, health response, reconnect or return of the old generation cannot revive it. Transport/generation attestation itself remains unenrolled.

Fresh sampled activity/private child guards are not atomic all-client native admission. G2 remains unsatisfied; installed native source/config/binary coverage and busy-conflict races are unproven. No native lifecycle or new managed work is enabled by the current manager. Complete interpreter/release/image enrollment and authorized native acceptance are still outstanding.

## Executed audit coverage

- `SecurityTests.swift`, `ProtocolTests.swift`, shared contracts: full role matrix, authority-field injection, duplicate/escaped keys, unknown/boolean versions, hostile binary/oversize frames.
- `TaskOwnerTests.swift`, `TaskCommandTests.swift`: malformed/foreign owner, no output/download consumption by foreign owner, exact fully valid management JSON delivered as opaque stdout without changing desired state, irreversible output loss and no replay.
- `SandboxModelTests.swift`, `ModelProtocolTests.swift`, Python worker/guard tests: job/runtime/request binding, exact routes/origin, finite budgets, generated output never control, fixed errors, no tools/retries.
- Artifact/release tests: generated paths, hash/owner verification, symlink/hardlink/traversal refusal, finite retention/transfers, immutable receipt checks and no unreviewed extra files.
- Actual isolated sandbox/runner/attach checks: caps, filesystem/network/credential isolation, control-FD refusal, foreign sentinel survival, private mock-model path and explicit export/download.

These are local mock/disposable-runtime results. They do not establish real-model non-preemption, production runtime enrollment, native boot behavior, remote CI or deployment acceptance.
