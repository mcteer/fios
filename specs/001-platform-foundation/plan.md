# Implementation plan for Spec 1

## Summary

Deliver the three-host inventory and read-only local operator view on the Mini, then prove a developer can reproduce them from the documented checkout. Scope is F1–F3 in the [specification](spec.md). The sections following Local architecture retain the longer-term platform design.

## Technical context and project structure

The native macOS sampler and Python standard-library HTTP service share the observation contract in `src/backend/`. A single OrbStack container serves the dashboard assets and rendering code from `src/frontend/`. `src/agent/` holds future AI harness configuration. The developer toolchain uses pinned Spec Kit 1.4.5 and CPython 3.15 on Apple Silicon. Foundation validation uses `tests/test_foundation.py`, Make and the Compose configuration.

## Constitution check

| Principle | Design and acceptance gate |
| --- | --- |
| Distinguish inventory from observations and reservations | Show all three configured hosts, label measurement age, count only fresh observations. This slice exposes no dispatch operation. |
| Enforce authority in the control plane | Check the local principal before inventory reads. Reject foreign authority, credentials and write requests. Verify denial bodies and unchanged observation data in isolated tests. |
| Keep bootstrap local | Bind to loopback on the trusted Mini and use a read-only observation mount. Studio enrollment and Internet ingress have separate milestones. |

The design satisfies all three gates without an exception. Acceptance evidence is tracked separately in [tasks](tasks.md).

## Design and verification sequence

1. Use the existing [research](research.md) to select native sampling, local file exchange and the pinned development workflow.
2. Freeze the [data model](data-model.md) and [local inventory contract](contracts/inventory.md). Implement the sampler and read-only HTTP access boundary before offering the UI.
3. Verify each story with isolated fixtures and the [quickstart](quickstart.md). Include rendered status labels and counts, denied-response contents, and a clean-checkout launch. Preserve the running preview when validating lifecycle behavior.


## Local architecture

| Component | Location | Responsibility |
| --- | --- | --- |
| Browser and fios-core | UI and read-only core API in an OrbStack container on the 24 GB M4 Pro Mini | Render configured inventory and observed samples. During bootstrap, bind IPv4 loopback in the OrbStack host network and validate the HTTP authority and browser origin. This intentionally assumes trusted local processes, including workloads on the Mini. |
| Host agent | A native unprivileged process on each Mac | Collect the node's own measurements. The foundation writes a bounded, versioned snapshot by atomic replacement. Only the core observation directory is mounted read-only in the UI. A sample on a Studio stays there until an authenticated transport exists. |
| Model runtime | Native macOS process using Metal, supervised by the local agent in a future slice | Use a fixed local runtime endpoint and an approved catalog. Keep native MLX, weight caches and the TB5 data path outside the Linux container. |
| Job and Project store | Single writer on fios-core, future SQLite database and private artifact directory | Own queue, leases, reservations, projects, usage and audit. Store content separately from operational telemetry. Back up the DB and artifacts as a consistent set. |
| Studio workers | Two 256 GB M3 Ultra hosts | Serve independent models by default. A distributed job leases both hosts as a unit. Image and sandbox reservations reduce available capacity for inference. |

Direct local file transfer makes the first observation verifiable without putting an unauthenticated agent listener on the LAN. The agent records only a fixed host ID, sample time, logical CPU count, one-minute load and physical memory. The dashboard does not infer available memory from physical capacity. A fresh observation is evidence of agent activity only. Bootstrap exposes inventory reads. No tool call, update, shell or workload execution is available in this slice.

## Data and control flow after the foundation

1. A browser session or API key resolves to a server-owned principal. The service checks role, Project ownership and action before writing a bounded job. The future local planner proposes typed actions through the same entry point. Agents authenticate the core and enforce their local capability allowlist. Job payloads cannot choose executables, arbitrary model URLs or mount paths.
2. A Studio uses an outbound mutually authenticated channel for heartbeat, lease acquisition and results. Enroll preapproved machine IDs with short-lived certificates and a rotatable local trust anchor. Separate agent identity from acting user, distinguish boot epoch from heartbeat sequence and fence results by lease generation. Use a management link for control messages and the private TB5 addresses for collectives.
3. Persist jobs with owner, Project, resource class, approved model revision, request limits, idempotency key, attempt and deadline. Use an atomic transaction for the queue transition, both node reservations when needed and the lease token. A worker acknowledges start. Renew while running. On timeout cancel and fence, reconcile actual worker state and only then re-admit memory. No blind replay of non-idempotent updates or completed billable work.
4. Admit by measured available unified memory minus OS/OrbStack reserve, resident model and estimated KV/activation/sandbox demand without double-counting shared weights. Start with one compute job per Studio. Bound queued work per owner and return retry guidance when saturated. Prefer a warm single host. Use monotonic idle timers and serialize unload against lease acquisition. Drain before maintenance and permit operator cancellation.
5. Record authoritative token counts from the serving runtime, distinguishing missing from zero and estimates from billed usage. Deduplicate by job/attempt. Display costs only with a configured unit, currency and price-version or metered energy tariff. Expose host pressure, model/lease state, queue age, TTFT, prefill/decode tokens/s, memory peaks, RDMA transport and service errors. Aggregate by low-cardinality labels. Keep user IDs, prompts and campaign content out of metrics.
6. Treat user-visible chat, image, search and sandbox results as owned artifacts. Store immutable revisions, checksums, provenance and publication state. UI and APIs query the same authorized service. A server crash before approval leaves a private draft. Paginate Project history and enforce context and disk budgets.

## Product slices

**Private chat and code.** Benchmark the Mini model for chat and for explaining read-only admin telemetry. Its output can suggest a typed operation. For Qwen, validate chat template, thinking output separation, quantization, stop/cancel behavior and usage reporting. Give code review its own fixture set of generated code, source locations, remediation and regression tests. See research.md for candidate models and official runtime documentation.

**Campaign workspace.** Schema includes Project, membership/owner, campaign canon with revision and source, NPCs/factions/places, sessions, messages, artifacts and audience. Begin with SQLite full-text retrieval filtered by Project and audience before ranking. Assemble bounded context from approved canon, latest session recap and relevant excerpts. User edits win over generated summaries. Preview proposed canon changes and keep revision history. Validate a backup/restore across a multi-session campaign. Keep narration and visual conventions versioned per Project.

**Live search.** Offer a search control inside chat and show the outbound query, provider, timestamp and cited URLs. A private SearXNG JSON provider is the initial candidate. Use a fixed provider endpoint, timeouts, max results, size and daily budgets. Send just the approved query, keep keys server-side and label stale/cache fallback. Treat snippets as untrusted quotations. Any later document fetch uses a separate egress proxy, HTTPS, public-IP validation after DNS resolution and on redirects, and blocks private, loopback, link-local and metadata destinations.

**Sandbox.** A user requests a specific test profile and sees pending, running, timed out or complete with capped output. Manage the executor through a narrow native broker. Each job receives a pinned image, ephemeral scratch, read-only source copy, no credentials, no Docker socket, no host mounts, no devices and no network. Enforce CPU, memory, PIDs, output and wall-clock quotas outside the guest. Delete workspace after cancellation/crash. Docker containers on a shared kernel require containment qualification. Keep untrusted jobs disabled until a dedicated VM boundary or equivalent reviewed isolation is demonstrated.

**Content and art.** Version the policy independently of each model and profile. Enforce it before dispatch and on every generated result, including upload/edit and retrieval paths when introduced. No raw generation stream before moderation for sensitive content. Deny sexualized depictions of minors, youth-coded or uncertain-age subjects across realistic and stylized media. Require clearly adult subjects for nudity. Apply the same policy to admins. Maintain a versioned list of prohibited content and an incident procedure with restricted evidence access. Include other legally prohibited uses identified during operator review. Allow approved mature fiction and adult anatomy. Classifier error, ambiguity or missing coverage withholds the result. Isolate temporary output, restrict access, expire it promptly and retain only reason codes in logs. Recheck publication policy for previews, thumbnails, exports and shares. Test with safe descriptions and mock classifier outcomes, plus authorized age-appropriate evaluation material. No known-illegal material is needed.

**Software updates.** Separate runtime, agent, model and OS updates. Start with an inventory and approved version manifest. Verify release digest/signature and model provenance, check disk headroom, drain one host, stage a side-by-side version, probe health and run a fixed canary, then switch atomically. Keep a previous working artifact. A paired deployment rolls back as a unit on protocol mismatch. OS/RDMA changes remain operator-managed maintenance events. No arbitrary package, shell or self-update from chat.

## Evaluation before model admission

Use a versioned fixture set per workload, with a disjoint final holdout. Freeze model, quantization, runtime, prompt/preset revision and decoding parameters for comparisons. Run a simple baseline before changing narration or tool instructions. Keep results local and record individual failures as well as aggregate scores.

| Slice | Proposed first gate |
| --- | --- |
| General chat / coding | Measure Mini peak at the chosen cap. On two independent coding tasks, the generated changes must pass the supplied functional tests. Review a clean fixture and a seeded defensive defect for the expected location, mitigation and absence of spurious critical findings. |
| Administration / tool use | Every user-role attempt at an admin action must be denied through UI, API and proposed model calls. Missing identity, expired lease and replayed result must fail closed. |
| Campaign / search | Reopen a saved campaign after restart. Recover approved facts from an earlier session, preserve a manual correction and exclude every GM-only canary from the player export. Verify each cited fact against its source and date. A search timeout must be visible. |
| Art / publication | Meet every requested orientation and style on an approved adult-only set. Include ordinary mature fiction and nonsexual adult nudity as allowed cases. Every prohibited or uncertain case and every simulated classifier outage must withhold the artifact and derived previews. Record false denials and use separate holdouts for both classes. |
| Sandbox | Use harmless probes for network, host filesystem, privilege, PID, disk, output and deadline limits. Each denied capability stays denied after retry, cancellation or worker restart. |

These are release gates for later implementation. Passing a small fixture set cannot establish population-wide model safety. Retain incident handling, fail-closed publication and repeat testing after model/runtime changes.

## Threat review and rollout

| Boundary / failure | Control | Required evidence |
| --- | --- | --- |
| Browser → local admin | Loopback-only listener, exact authority/origin, no forwarded identity, GET-only fixed routes, CSP, no model endpoints or reverse proxy | Local successful response, denied hostile Host/Origin and HTTP writes. Recheck actual listener and LAN exposure whenever OrbStack changes. |
| Remote host → core | mTLS, inventory enrollment, bounded schema, clock/epoch checks, lease fencing | Unknown, revoked, stale and duplicate reports cannot allocate capacity or complete work. |
| Model/tool → admin or secrets | Deterministic role and ownership checks, typed capabilities, dedicated model-fetch process, fixed destinations | Tool text, headers and search results cannot grant admin or read credentials. |
| Project → other Project/player handout | Owner/audience filtering before retrieval and export, backup/access controls | Cross-owner denial and GM-only canary excluded after summarization/export. |
| Image worker → user | Private staging, input and output policy, positive publication decision for each artifact | Classifier outage, retry, direct URL and thumbnail paths fail closed. Mature allowed cases still pass. |
| Guest → host or cluster | Dedicated boundary, deny host integrations and egress, quotas and reaper | Harmless denied reads and network probes, bounded noisy job, cancellation and recovery. |
| Future identity → public ingress | Disable bootstrap at startup in public mode, TLS, Google OIDC with state/nonce/PKCE and token verification, revocable hashed/scoped keys, CSRF and rate limits | Negative tests for issuer/audience/expiry, revoked keys, missing scope, wrong owner and user→admin escalation. |

Bootstrap trusts the owner and processes with access to the Mini or its OrbStack host network. An untrusted local tenant or a reverse proxy changes that assumption. Retire bootstrap before admitting either. For a future public service, restrict admission to the intended adult audience independently of Google sign-in. Future user identities get stable internal IDs. Migrate the local operator's records explicitly after verified account linking. No automatic grant based on email or first login.

Roll out each future backend against a replayed fixture first, then one private host. Stop on policy failure, ownership leaks, unstable memory pressure, wrong placement or incomplete cancellation. Drain and restore the previous backend or leave its capability unavailable. Restore a tested snapshot before any incompatible schema migration. For this foundation, stopping the foreground processes or removing the Compose service rolls back the entire runtime.

## Decisions before enabling later slices

The operator selects the enrolled host identities and trust anchor, redistribution/license terms for approved models, acceptable real-world quality/latency from benchmark results, sandbox isolation boundary and any search provider with paid or external data processing. General chat, generated code review and art have independent release gates. A model's willingness to answer gives it no additional platform permissions.
