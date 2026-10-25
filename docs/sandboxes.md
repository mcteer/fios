# Studio agent sandbox exploration

Feasible architecture: native macOS MLX-Serve handles inference while per-job Linux containers in Studio OrbStack run agent commands. This is CPU/Linux tooling isolation, not containerized MLX/Metal or RDMA. Models request tool calls; a separate authenticated agent orchestrator authorizes them, schedules jobs on a Studio, executes commands, and returns bounded results. An OpenAI-compatible chat endpoint alone does not establish sandbox support.

Before implementing:

1. Verify this MLX-Serve version's actual agent/tool/sandbox APIs and authentication; do not assume a Docker integration exists.
2. Specify a remote runner protocol with mTLS or equivalent authentication, authorization per user/repository, audit logs, cancellation, timeouts, concurrency, and resource quotas.
3. Run non-root, ephemeral containers with read-only root filesystems where practical, dropped capabilities, restricted egress, no privileged mode, no host directories/secrets, and no Docker socket exposed to the model or frontend. Treat source code and tool output as untrusted.
4. Keep inference RAM/CPU headroom on both Studios; benchmark sandbox concurrency without disrupting RDMA inference.
5. Test malicious repositories, credential exfiltration, runaway processes, deletion, network scanning, and complete cleanup. Containers share OrbStack's Linux VM kernel; hostile multi-tenant jobs may require stronger VM isolation.
6. Pilot an approved repository and narrowly scoped commands before connecting tools in the custom Fios frontend. Require human approval for privileged actions.

No remote Docker API, runner, or sandbox has been enabled by feature 001.
