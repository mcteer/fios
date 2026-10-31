# Research: Studio platform management agent

**Date**: 2026-10-26. Read-only repository/local-source/public-document research. No SSH, native API query, process operation, model request, container operation or privilege change performed for009. Decisions below are design choices, not installed capability attestations.

## 1. Supervision outside the managed runtime

**Decision**: Swift6.4 native package with an unprivileged boot supervisor, manager and narrowly scoped user-session adapter. launchd installs require operator approval; no root runtime daemon logic. Supervisor availability is independent of login; managed apps may wait for a supported session (clarification1A).

**Rationale**: A container cannot supervise its unavailable runtime. The local macOS `launchd.plist(5)` documents `UserName`, `KeepAlive`, `RunAtLoad`, `ThrottleInterval` and session restrictions. KeepAlive alone is not a hang detector or finite restart budget; a separate minimal watchdog and durable budget are required. The available local toolchain reports Swift6.4, arm64 macOS; this is development-host evidence, not either Studio's deployment compatibility.

**Alternatives considered**: Compose-only supervisor fails the outage requirement. Root manager unnecessarily broadens authority. Restoring005's rejected LaunchAgents conflates platform control with existing006 app support. Relying on user login for the supervisor contradicts1A. Full unattended application readiness was explicitly not selected.

**Evidence**: `/usr/share/man/man5/launchd.plist.5` (local OS reference); [Apple launchd programming guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html). Manual documents semantics, not a live reboot demonstration.

## 2. OrbStack runtime and resource envelope

**Decision**: Use existing OrbStack and its identity-checked Docker CLI against an explicit local Unix socket, never inherited Docker context or a TCP daemon. Use network-none already-cached images, bounded attached pipes, readonly root/tmpfs, no host mounts. Verify VM and host resource headroom; do not change VM configuration automatically.

**Rationale**: Official docs describe Docker compatibility, a dedicated `orbstack` context/socket, and a VM-wide memory/CPU cap shared by containers and machines. Host free memory alone does not prove VM capacity. A bounded tmpfs workspace avoids pretending an ordinary Docker volume has a portable enforceable disk quota. It is charged to the sandbox memory limit; artifacts are copied through a bounded explicit export stream.

**Alternatives considered**: Docker bridge + egress firewall is a larger, harder-to-audit boundary than network-none. Giving a sandbox the host socket enables daemon-wide control. A network model proxy requires additional reachability/firewall assumptions; pipe mediation avoids those. Global Docker prune risks unrelated data. Image pulls on job admission add uncontrolled network, storage and supply-chain work; require pre-provisioned approved digests instead.

**Sources read**: [Using Docker containers](https://docs.orbstack.dev/docker/) and [Settings](https://docs.orbstack.dev/settings), fetched2026-10-26 to `/tmp/fios-009-research/`. The pages were documentation only; no `orb`/Docker service command executed. Stable checked-in summaries here remain usable if temporary files disappear. Installed VM caps, socket and application ownership on each Studio still require a separately approved inventory.

## 3. All-client native activity: metrics are not yet sufficient

**Decision**: Define an authoritative native-local activity/admission contract and require a versioned compatibility gate before implementation activation. A supported local-only adapter is the candidate; no remote `/metrics` bypass, process-log parsing, port sniffing, instrumentation injection or Fios-only substitute. If installed native interfaces cannot satisfy the contract, stop and obtain a separately reviewed native integration change; do not silently expand009 into a server fork.

**Rationale / source findings**:

- The prior008 read-only source set aligns to MLX-Serve tag26.10.3, revision `046b647686419df06c6c7132fb1d15d76185c3e5`. Source is public evidence, not proof of installed binary/config identity. Its prior health/version observations are historical008 evidence, not new009 inspection.
- `src/lan.zig::routeClass` allows the shared inference routes but denies `/metrics` and `/metrics.json` for the ordinary shared LAN surface. Native-local observation is a different, explicitly scoped permission; publishing denied admin endpoints remotely is not the design.
- `src/server.zig::sampleGauges` (~13715–13720) reads scheduler `in_flight` and `pending.items.len` under `queue_mu`, then publishes separate gauge values. These are sampled aggregates, not a correlated request lifecycle/epoch or a guarantee that every handler has entered that scheduler.
- `src/scheduler.zig::ensureLoaded` (~2074 onward) takes a registry reference on the ready fast path and performs preloading/reservations on the cold path. Those phases and response flushing are not proven covered by the two sampled scheduler counters. Independently fetching catalog and metrics does not produce one coherent atomic snapshot.
- `src/model_registry.zig::pickLruEvictable` rejects referenced entries, and scheduler load planning waits for victim readers to drain. This supports a non-preemptive compatibility hypothesis. It does **not** prove all request modalities, external queued work, actual deployment caps or every enabled admission path meets009's contract. A resident-only guard was an unnecessary assistant-added constraint and has been removed; idle model replacement is allowed.

**Acceptance implication**: A fresh HTTP200 with running=0/waiting=0 is not sufficient to certify idle. Need all-client ingress/preparation/queue/compute/response ownership, exact model identity, source epoch/sequence and native protection for the observation→dispatch race. Source loss → unknown is safe operation but does not count as completion of SC-002/008. Native all-client evidence must cover direct, tunneled and manager clients and every enabled request modality, or mark the host unsupported.

**Alternatives considered**: Manager request ledger cannot see bypass clients (rejected by2A). GPU0%, process alive, loaded=true, repeated zero samples and wall-clock grace periods cannot prove quiescence. A mandatory proxy alone still fails if existing clients bypass it. Native version labels alone do not attest policy.

**Source links**: [server](https://github.com/ddalcu/mlx-serve/blob/046b647686419df06c6c7132fb1d15d76185c3e5/src/server.zig), [scheduler](https://github.com/ddalcu/mlx-serve/blob/046b647686419df06c6c7132fb1d15d76185c3e5/src/scheduler.zig), [registry](https://github.com/ddalcu/mlx-serve/blob/046b647686419df06c6c7132fb1d15d76185c3e5/src/model_registry.zig), [LAN policy](https://github.com/ddalcu/mlx-serve/blob/046b647686419df06c6c7132fb1d15d76185c3e5/src/lan.zig). Repository provenance checked against008's research at local checkpoint3936da2; local source files reside in `/tmp/fios-008-installed/`.

## 4. Model-assisted tasks without manager authority

**Decision**: Separate private installed Python entry point using the already locked Pydantic stack, one request at a time, zero tools/retries and finite job budgets. The native manager owns authorizations, durable request records and framing; Python remains a pipe child without a listener or SQLite. Sandbox model interaction goes over its fixed runner channel, not a network route or shared token.

**Rationale**: Satisfies local-model use without modifying007's web-search tool, IPCv2, budgets or authentication. No natural-language policy decision can authorize a native operation. Canonical exact identities and trusted local dispatch mappings are explicit enrollment data, not generated by model output.

**Alternatives considered**: Direct Swift/Express inference would bypass the required harness. A general-purpose model tool with Docker/SSH access violates the trusted-control boundary. Reusing008's unmerged routing code would couple separate features and revive parked work.

## 5. Remote consumption without opening a new service

**Decision**: Role-separated Unix IPC and CLI first. Specify an optional forced-command SSH read-only exporter for the future containerized observation consumer, using an independently approved restricted key and pinned server key. No new native TCP listener, no SSH command strings accepted from a caller, no use of the operator's general SSH key by app containers.

**Rationale**: Existing SSH administrative availability is not permission to expose a new LAN API. A fixed status export contains no workload content or management operations. Future008 can consume the contract independently;009 does not implement its automatic router.

**Alternatives considered**: Public/plain LAN HTTP is disallowed. A TLS management API is unnecessary initial scope. An unrestricted SSH client in the frontend/observer would expand remote-execution authority. Snapshot signatures would not by themselves solve replay/age or native admission races; authenticated channel + epoch/sequence/age and native safety are still required.

## 6. Governance is a separate gate, not a technical workaround

**Decision**: Keep the active constitution and AGENTS policy unchanged. Provide [a narrowly scoped proposal](governance-proposal.md), explicitly pending approval. Implementation tasks begin with that approval and native-compatibility gates.

**Rationale**: The requested platform requires two explicit exceptions: host-native management and authorized isolated sandbox execution. Generic automatic remediation does not silently authorize broad security-policy changes. The user authorized plan/tasks/analysis and supported document remediation, not installation or activation.

**Alternatives considered**: Rewording the blanket prohibition as though it already allowed this feature would be misleading. Failing safe forever and calling009 implemented would not meet user requirements. A concrete conditional design makes approval and native capability gaps reviewable without weakening acceptance.
