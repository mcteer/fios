# Fios Constitution

Version: 2.0.0
Ratified: 2026-10-23
Last amended: 2026-10-23

## Principles

1. **Specification first.** Each feature has a numbered directory in `specs/` with user stories, measurable acceptance criteria, a plan, and tracked tasks before implementation. Record deviations and test evidence there.
2. **Purpose-built frontend.** Build Fios from scratch around a deliberate, coding-focused user experience and the existing MLX-Serve APIs. Open WebUI is retired. Reuse maintained libraries where appropriate without inheriting a prebuilt chat application's interface. Specify the UX and architecture before selecting a framework; pin dependencies and review upgrades deliberately.
3. **Native inference, isolated workloads.** MLX-Serve and RDMA remain native macOS services. Linux containers do not provide Apple Metal acceleration or direct access to the existing RDMA fabric. No deployment may change cluster configuration without explicit approval.
4. **Secure by default.** Require authentication, bind to localhost initially, keep secrets out of Git, disable arbitrary code execution, never mount a Docker socket into the frontend. LAN exposure requires an administrator account and a documented TLS/network policy.
5. **Persistent and reproducible.** Compose plus documented environment settings define deployment; user data survives container recreation. Back up before upgrades. Health checks must not invoke inference.
6. **Verify honestly.** Validate configuration, container-to-gateway discovery, and opt-in streaming inference independently. Distinguish observed results from pending browser, recovery, and cluster-failover tests.

## Amendment history

- 2.0.0: User rejected Open WebUI's look and feel and requested a from-scratch frontend. Replaces the upstream-frontend mandate; feature 001 is retired. Native inference and security boundaries remain unchanged.

## Workflow and governance

Use the upstream GitHub Spec Kit workflows installed in `.agents/commands/` (generic agent integration). Follow constitution → specify → clarify → plan → tasks → analyze → implement. Agents without slash-command registration can read these prompts directly. Changes to these principles require a documented rationale, version bump, and review of affected specs. Operational documentation and acceptance evidence are part of every feature.
