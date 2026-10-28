# Feature Specification: Studio Platform Management Agent

**Feature Branch**: `009-studio-platform-agent`
**Created**: 2026-10-26
**Status**: Implementation in progress:30/55 tasks complete,25 incomplete. Current work is source/build development;009 is not deployed and operational acceptance remains pending.
**Input**: A platform management agent per Studio that starts on boot with a watchdog, tracks/manages MLX-Serve and OrbStack, tracks active model requests and hardware utilization, dispatches only temporary agent-sandbox containers with complete lifecycle cleanup, and uses local MLX models for authorized tasks and sandbox interactions. Administrative SSH access is available as `mcteer@<Studio>`; ask the user to perform any required privileged commands.

## Offline RAM-planning convenience

`studioctl plan-memory --ram-gib N` reports the supplied physical RAM and the existing native reserve of at least16GiB or20%, rounded upward. It works without a state directory, running manager or hardware sampling. Output includes exact byte counts plus supplied physical GiB and approximate headroom GiB for readability. Output must identify itself as planning-only and not measured; it must not claim current available RAM, model fit or shard placement, and performs no runtime actions.

## Clarifications

### Session 2026-10-26

- Q: Does boot readiness apply to the supervisor or the entire managed stack? → A: A. The supervisor starts before login; MLX-Serve and OrbStack wait for their supported macOS/session prerequisites. No automatic login or disk-encryption bypass.
- Q: Which model requests must authoritative activity cover? → A: A. Every request served by the Studio's MLX-Serve, including clients bypassing this manager. Agent-only bookkeeping is insufficient.
- Q: What network access may sandboxes have? → A: A. No external network, with only scoped mediated local-model access. Dependencies come from approved immutable images; no public-internet or per-job arbitrary egress grants.

## User Scenarios & Testing

### User Story 1 — Recover the Studio management service (Priority: P1)

As the operator, I can reboot either Studio and have its management agent start automatically, remain supervised, and report whether its managed services are running without manually launching a terminal.

**Why this priority**: The manager must remain available when OrbStack or MLX-Serve is down; it cannot depend on the service it is responsible for restoring.

**Independent Test**: On a separately authorized host or faithful lifecycle fixture, exercise boot/session transitions, process crash, hang and repeated failed starts; verify one manager instance, bounded recovery and an explicit degraded state.

**Acceptance Scenarios**:

1. **Given** macOS can run the supervisor after any required disk unlock, **when** the Studio boots before user login, **then** exactly one supervised manager starts without an operator terminal; MLX-Serve and OrbStack may remain waiting for their supported session prerequisites.
2. **Given** the manager exits or stops making progress, **when** its watchdog detects failure, **then** it restarts within the recovery bound while restart budget remains, or reports budget-exhausted degradation; neither path creates duplicate managers or replays interrupted jobs.
3. **Given** starts repeatedly fail, **when** the restart budget is exhausted, **then** the service reports degraded status and stops the restart storm rather than consuming unbounded resources.
4. **Given** encrypted storage or a required user session is unavailable, **when** boot occurs, **then** the manager reports the unmet prerequisite when it can run; it does not bypass disk encryption, enable automatic login or claim dependent services are ready.

---

### User Story 2 — Protect active models and expose reliable routing state (Priority: P1)

As a Fios routing consumer, I can distinguish a resident model from a model serving requests, prefer an eligible idle Studio, and avoid switching models while a response is in flight. Additional requests for the same loaded model remain allowed.

**Why this priority**: This is the information and admission boundary that parked008 lacks; process liveness or GPU utilization alone cannot establish request activity.

**Independent Test**: Exercise idle, queued, running, streaming, cancellation, failed/disconnected and overlapping same-model requests, including requests from clients that bypass the manager; race a model-switch request with inference admission and verify active work is not displaced.

**Acceptance Scenarios**:

1. **Given** a loaded model has no queued, loading or active inference work under authoritative coverage of all native clients, **when** activity is read, **then** the consumer receives fresh host/model-bound idle evidence rather than an inference from residency.
2. **Given** a model is serving a response, **when** another request targets the same exact loaded model, **then** native concurrency/capacity policy may admit or queue it; activity alone is not an exclusive host lock.
3. **Given** active work targets model A, **when** a request would switch that host to model B, **then** the conflicting switch is rejected or deferred without unloading A mid-response. A stale idle observation cannot override admission protection.
4. **Given** several same-model requests exist, **when** one completes, **then** only its own activity is released; all others continue to prevent a conflicting switch.
5. **Given** a client disconnects or the manager restarts, **when** native completion is uncertain, **then** uncertainty survives until authoritative reconciliation; socket closure, loaded state and elapsed time alone do not prove idle.
6. **Given** a consumer receives stale, mismatched, incomplete or uncovered observations, **when** it makes a routing decision, **then** it sees unknown/unverified state and cannot treat the host as verified idle.
7. **Given** a bypass client starts a native request, **when** activity is observed, **then** its queued/active work is included; loss of that coverage yields unknown and fails acceptance rather than redefining coverage as managed-only.
8. **Given** an eligible idle Studio and a busy same-model alternative, **when** a routing consumer evaluates the exported activity, **then** it has enough evidence to prefer idle capacity without009 silently choosing or substituting the answering model.008 remains responsible for its eventual Gemma routing policy.

---

### User Story 3 — Manage native services without disrupting unrelated work (Priority: P1)

As the operator, I can inspect MLX-Serve and OrbStack state, request bounded lifecycle actions, and recover an unexpectedly stopped service without a management loop fighting deliberate maintenance or killing healthy workloads.

**Why this priority**: Both services are critical host dependencies, and restarting OrbStack can affect containers outside the manager's sandboxes.

**Independent Test**: Use lifecycle fixtures to exercise missing/crashed/hung services, operator stop, version change and active work; verify identity checks, graceful drain, escalation limits and unrelated-workload protection.

**Acceptance Scenarios**:

1. **Given** a managed service is unexpectedly absent and its desired state is running, **when** recovery is allowed, **then** the manager starts the approved installed service once and verifies readiness without test inference.
2. **Given** the operator enters maintenance or deliberately stops a service through the manager, **when** supervision runs, **then** it respects that desired state instead of immediately undoing it.
3. **Given** MLX-Serve has active requests or OrbStack has active/unmanaged workloads, **when** a disruptive restart/stop is requested, **then** the manager drains its owned work or refuses; forced disruption requires explicit operator authorization and lists the affected scope.
4. **Given** PID reuse, a changed executable identity or an uncertain service owner, **when** management is attempted, **then** it fails closed rather than signalling an unrelated process.
5. **Given** OrbStack is unavailable, **when** management continues, **then** the native supervisor remains alive and reports sandbox cleanup as pending, not successfully completed.

---

### User Story 4 — Admit temporary sandboxes within available resources (Priority: P1)

As an authorized agent client, I can request a temporary isolated sandbox on an eligible Studio, have it admitted against current hardware usage and outstanding reservations, and rely on the manager to stop and remove it when its lease ends.

**Why this priority**: Sandboxes must not exhaust the unified memory or resources needed by native inference, nor accumulate as permanent containers.

**Independent Test**: Use an isolated container runtime and synthetic resource readings to exercise concurrent admission, resource pressure, completion, cancellation, expiry, client loss and manager/runtime restart; verify no over-admission or unrelated deletion.

**Acceptance Scenarios**:

1. **Given** fresh utilization and sufficient headroom, **when** an authorized bounded sandbox request arrives, **then** the manager reserves capacity atomically and starts exactly one approved sandbox with enforced limits.
2. **Given** simultaneous requests compete for the same headroom or observations are stale, **when** admission occurs, **then** reservations prevent oversubscription and unsafe requests receive a bounded rejection or documented bounded wait, never speculative launch on both Studios.
3. **Given** a sandbox finishes, is cancelled, loses its owner or reaches its lease deadline, **when** cleanup runs, **then** it stops and its manager-owned container, ephemeral storage and related resources are removed; approved exported artifacts are retained separately.
4. **Given** the manager or runtime restarts during launch/cleanup, **when** reconciliation runs, **then** it identifies owned resources, resumes bounded cleanup and prevents duplicate job execution. Unknown ownership never authorizes deletion.
5. **Given** resource pressure rises after admission, **when** limits are reached, **then** the manager refuses new jobs and applies the documented sandbox throttling/termination policy before threatening active native responses; it does not unload an active model to make sandbox capacity.
6. **Given** a request asks for a persistent service, privileged container, host credentials, unrestricted host mount or runtime control socket, **when** admission is evaluated, **then** it is rejected regardless of model-generated instructions.
7. **Given** a sandbox attempts public-internet, DNS, host/private-network or sibling access, **when** it executes, **then** those paths are blocked; only its scoped local-model mediation is available, and dependencies must already be in its approved image.

---

### User Story 5 — Use local models from bounded tasks and sandboxes (Priority: P2)

As an authorized platform task or sandbox, I can request local inference through the manager's controlled capability without receiving host-management privileges or long-lived MLX credentials.

**Why this priority**: Local model access makes agent sandboxes useful while keeping inference, request accounting and privileged host operations separate.

**Independent Test**: Mock local models and sandbox identities; verify exact-model dispatch, request accounting, lease/usage limits, credential isolation, cancellation and malformed-output behavior. Real inference remains a separate opt-in.

**Acceptance Scenarios**:

1. **Given** an active sandbox lease permits a particular local inference operation, **when** it requests that operation, **then** the exact approved model is invoked through the controlled native-serving boundary and the request is included in activity/accounting.
2. **Given** an expired lease or a request outside allowed model, context, output, time or concurrency limits, **when** inference is attempted, **then** it is denied before dispatch without silently switching model/host or retrying.
3. **Given** model output or sandbox content asks to restart services, change limits, open network access or launch another sandbox, **when** the output is processed, **then** it has no authority to perform those operations. Privileged lifecycle/admission policy is deterministic and separately authorized.
4. **Given** a sandbox is removed during inference, **when** cancellation propagates, **then** no follow-up request or late result is delivered to the expired sandbox; native work stays accounted for until verified completion.

### Edge Cases

- FileVault unlock versus macOS boot versus user login; headless restart, sleep/wake and clocks moving backwards.
- OrbStack session requirements, runtime startup loops, missing binaries, upgrades, changed process identities and deliberate maintenance stops.
- MLX loaded-but-idle versus queued/prefill/streaming activity; same-model overlap, external clients, partial responses, lost connections and activity collectors lagging or failing.
- Consumer/model/host identity mismatch, manager restart epoch, stale or replayed activity/admission grants and network partitions between Studios and Fios.
- Shared unified-memory pressure from native inference and the container VM; missing sensors, thermal/power throttling, disk exhaustion and unknown capacity.
- Concurrent sandbox launches, image acquisition failures, startup timeout, runtime outage during deletion, orphaned resources, exported artifacts and duplicate job submissions.
- Hostile code/model output, forged sandbox identity, image supply-chain changes, network exfiltration, sibling-sandbox access and attempts to obtain management credentials.
- Existing persistent Fios containers or unrelated user containers on a managed runtime: neither may be adopted/deleted merely because the manager can see them.

## Requirements

### Functional Requirements

- **FR-001**: Provide one independently identifiable management agent per designated Studio. Initially assume the two existing Edge Studios; confirm their canonical host identities during planning. The manager MUST survive OrbStack unavailability and MUST NOT depend on a container it manages for its own recovery.
- **FR-002**: Start the manager automatically under supervised host lifecycle control, with single-instance ownership, watchdog detection of exit/hang, bounded backoff/restart budget and an observable degraded state. The supervisor MUST start before user login once macOS can execute it; MLX-Serve and OrbStack may wait for their supported session prerequisites, reported explicitly. No automatic login or disk-encryption bypass is permitted.
- **FR-003**: Track desired/observed state, installed identity, readiness and maintenance status for MLX-Serve and OrbStack. Permit only explicit lifecycle operations on verified managed instances. Gracefully drain or refuse disruptive actions while work exists; forced interruption requires an explicit affected-scope operator action. No automatic software updates, downloads or server/RDMA policy changes are implied.
- **FR-004**: Export host/model-bound activity that distinguishes resident, preparing, queued, running/streaming, idle and unknown, with timestamps, freshness/coverage and restart identity. Authoritative coverage MUST include all requests served by the Studio's MLX-Serve, including clients bypassing the manager. Agent-only bookkeeping, process/GPU sampling or residency are insufficient. Loss of all-client observation yields unknown and blocks verified-idle claims; it does not reduce the acceptance scope.
- **FR-005**: Activity tracking and admission MUST prevent a different-model request from displacing active work, while allowing additional requests for the same loaded exact model within native limits. Track overlapping requests independently; cancellation/restart cannot silently release uncertain work. Snapshot freshness alone MUST NOT be represented as an atomic native reservation.
- **FR-006**: Provide an authenticated, least-privilege observation/admission capability usable by future008. Include freshness, model/host binding, coverage and failures sufficient to distinguish verified idle from unknown. Inference clients cannot forge activity or manage host services.009 MUST NOT resume, merge or deploy parked008 as a side effect.
- **FR-007**: Track CPU, physical/unified memory pressure and headroom, GPU utilization when reliably available, disk availability and relevant thermal/power state, with availability/age per signal. Missing/unsupported/stale measurements MUST remain explicit, not substituted with zero utilization. Model use, container VM use and reservations share the same host resource envelope.
- **FR-008**: Dispatch only temporary, authenticated agent-sandbox workloads from approved immutable images and bounded task/lease requests. No persistent application/service scheduling, privileged containers, host process execution from sandbox input, unrestricted host mounts, host networking, control sockets or credentials inside sandboxes. Sandbox code execution is isolated from the trusted management process.
- **FR-009**: Admit sandboxes against fresh utilization, explicit native-inference headroom and outstanding resource reservations atomically. Define finite per-job/per-host CPU, memory, disk, process, lifetime, queue and concurrency limits in the plan; reject requests that cannot be bounded. Native GPU inference stays outside Linux containers. Placement never authorizes an unsolicited second-host attempt or duplicate job execution.
- **FR-010**: Own the full sandbox lifecycle: reserve, create, start, observe, revoke, stop, remove and reconcile, including manager/runtime restart and uncertain creation/deletion. Every sandbox has an owner, expiry and cleanup obligation; expired/lost owners cannot renew themselves. Delete only provably manager-owned resources, never unrelated containers, images, volumes or user files. Record cleanup failures honestly and retry only idempotent bounded cleanup, not the job/inference itself.
- **FR-011**: Separate approved artifact export from ephemeral sandbox data. Bound exported size/retention and validate ownership/path handling. Default sandbox storage is disposable; cleanup does not delete exported user artifacts or grant ongoing access after the lease ends.
- **FR-012**: Constrain sandbox networking and local model access separately from management access. Sandboxes MUST have no external network access; only authenticated job-scoped local-model mediation is permitted. Dependencies MUST be provided by approved immutable images, not runtime internet installation. Deny public-internet/DNS, direct private/LAN/host access, public listeners, management-plane access and sibling access; do not introduce per-job arbitrary egress grants.
- **FR-013**: Support bounded platform-task and sandbox inference via native MLX-Serve, exact approved catalog identities and short-lived job-scoped authorization. Account each request in activity/resource ownership. Do not download/substitute models, silently fail over/replay inference, expose long-lived MLX credentials to a sandbox or use cloud inference. Define finite context/output/request/time/concurrency budgets before implementation; health/watchdog/telemetry checks never invoke a model.
- **FR-014**: Keep privileged process/runtime lifecycle and admission decisions deterministic, least-privilege and independent of model-generated instructions. An LLM may assist a bounded task but cannot acquire new management/network privileges, recursively spawn sandboxes or change safety policy. The sandbox capability is not an arbitrary host shell endpoint.
- **FR-015**: Establish authenticated operator, observation-consumer, task-client and sandbox identities with separate permissions. No unauthenticated management exposure, embedded passwords, shared sandbox/operator keys or secrets in logs. Any private remote control surface requires a reviewed authentication/encryption/network policy; the frontend and sandboxes receive no Docker/OrbStack socket or general SSH authority.
- **FR-016**: Provide redacted operational events and status for service recovery, telemetry quality, activity coverage, job admission, resource usage and cleanup. Do not record prompts, raw code, model reasoning, tool arguments, page bodies, secrets or filesystem contents as routine diagnostics. Audit identities/actions/outcomes without leaking workloads.
- **FR-017**: Installation, privilege separation, service ownership, rollback and uninstall MUST be explicitly planned and reviewed per Studio. Use available `mcteer@<Studio>` SSH for bounded authorized administration, not as a runtime sandbox capability. Ask the user to run any required privileged commands, explaining effects and rollback first. No reboot, service disruption, privilege escalation, native policy/network/RDMA change or live workload is authorized merely by creating this spec.
- **FR-018**: Verify control policy, isolation, request accounting, admission races and lifecycle recovery with isolated fixtures before host tests. Separately authorize and record real boot/watchdog, service recovery, telemetry, sandbox cleanup and model-use checks; passing mocks or resident-state discovery MUST NOT be called demonstrated idle detection or full009 acceptance. Preserve dedicated reviewed PR/exact-head CI and independently green merged-main requirements; native Studio rollout requires its own explicit gate, not the existing app-only controller.

### Key Entities

- **Studio identity**: approved machine identity, serving/runtime bindings and management permissions.
- **Manager lifecycle**: desired state, boot/session prerequisites, instance/restart identity, watchdog progress, maintenance and degraded status.
- **Managed service**: installed identity, desired/observed state, readiness, ownership and safe lifecycle operations.
- **Host resource observation/reservation**: measurements, freshness/confidence, available headroom and outstanding sandbox/inference commitments.
- **Model request activity**: exact model/host, admitted/queued/active/terminal/uncertain state, owner and observation coverage; independent of model residency.
- **Sandbox lease/job**: authenticated owner, immutable image, task identity, resource/network/model grants, expiry, lifecycle and cleanup obligations.
- **Exported artifact**: explicitly retained bounded output with owner and retention, separate from disposable sandbox storage.
- **Scoped inference capability**: allowed exact identities/operations, job-bound lifetime, request/size/concurrency budgets and revocation.
- **Operator action/event**: authorized lifecycle or policy action, affected scope, redacted result and recovery evidence.

## Success Criteria

### Measurable Outcomes

- **SC-001**: In authorized boot tests on both Studios, one supervisor becomes observable within 60 seconds after macOS can execute it following any disk unlock, without waiting for user login. Missing service-session prerequisites are reported separately, not used to delay the supervisor's readiness bound. Exit/hang tests recover within 30 seconds of watchdog detection while restart budget remains; exhausted-budget cases report degraded status without another launch, with zero duplicate managers. Timing is a proposed acceptance target, not observed evidence.
- **SC-002**: In the controlled activity matrix, all active/queued requests, including bypass clients, are represented in healthy operation; loss of authoritative coverage is explicitly unknown and never counted as an idle-detection pass; observations older than5 seconds are never used as verified idle. Same-model overlap is admitted when capacity permits; zero active different-model displacements occur, including admission races and cancellation/restart cases.
- **SC-003**: Authorized service lifecycle tests recover stopped services without health-check inference, respect maintenance, and cause zero unapproved interruption of active model requests or unrelated containers. Every failed recovery produces a bounded degraded outcome.
- **SC-004**: Every admitted sandbox has enforceable limits/reservations and an expiring owner-bound lease. Simultaneous admission tests produce zero resource-policy oversubscriptions or duplicate jobs; stale/unsupported critical measurements never authorize unsafe admission.
- **SC-005**: Completed/cancelled/expired/orphaned sandbox fixtures leave zero manager-owned running containers or ephemeral resources within60 seconds when the runtime is available. After runtime recovery the same bounded cleanup resumes; unavailable-runtime cleanup is reported pending, not successful. Unrelated resources and approved exported artifacts remain intact.
- **SC-006**: Sandbox security tests obtain zero host/control sockets, operator/MLX secrets, prohibited mounts, sibling access or external network/DNS, direct host/private-network access or unauthorized model/management operations. Expired/revoked capabilities cannot dispatch new inference or workloads.
- **SC-007**: Local model task tests preserve the exact approved model and finite budget, record overlapping request ownership correctly and dispatch zero automatic replays after failure/cancellation. Separately authorized real tests show one platform task and one sandbox-mediated inference completing with cleanup; mocks are reported separately.
- **SC-008**: Before declaring009 able to unblock008, publish tested all-client observation coverage (including bypass clients), freshness and non-preemptive admission evidence for both Studios plus a consumer contract. Leave008 parked until explicitly resumed; no broad idle-awareness claim from Fios-only bookkeeping.

## Assumptions

- Initial target Studios are the existing `fios-edge-a.lab` and `fios-edge-b.lab` with user `mcteer`; the phrase “both” is treated as two designated machines, not permission to enroll other hosts. Confirm mapping before SSH or rollout.
- A minimal host-native management/supervision component is required to recover OrbStack when OrbStack is unavailable. This is a new009 authority boundary, not restoration of the rejected005 native readiness/deployer jobs or blanket permission for other native helpers. The existing006 support-services rule requires an explicit scoped update before implementation/deployment.
- Controlled sandbox code execution is requested, but the constitution's arbitrary-code-execution prohibition and existing daemon-authority rules need a reviewed narrow amendment/ADR before enabling it. No constitutional protection is silently removed by this draft. Docker/OrbStack authority is daemon-wide and stays only in the trusted platform control boundary, never the app, model worker, observer or sandbox.
- “Container workloads limited to temporary sandboxes” applies to workloads dispatched by009. Existing persistent Fios Compose services and unrelated containers are not removed, converted or placed under sandbox ownership. Managing OrbStack must respect their presence.
- No automatic native service/model installation or upgrade, distributed inference/RDMA redesign, public endpoint, cloud inference, arbitrary operator shell API or full general-purpose cluster scheduler is included. Read-only telemetry is not permission to bypass currently denied MLX admin routes.
- Fios UI inference remains inside its existing private Pydantic harness.009's platform/sandbox task capability is separately scoped, authenticated and budgeted; it does not create a direct browser inference fallback or grant the current007 web-search worker host tools.
- Default policy is inference-protective: reserve host headroom, reject unsafe new sandboxes, cap runtime/restarts, expose uncertainty and preserve active model work. Concrete limits, observation mechanisms and failure/escalation behavior are planning work, not guessed live capabilities.
- 009 branches from merged main `c5566040dc4008bab375d4a747c312fd1164bab9`, not from parked008.008's local checkpoint remains `3936da2` on its own branch; do not include its unfinished implementation in009's PR. No009 capability is implemented or live-tested by this specification.
