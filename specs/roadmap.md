# Future work

The [original roadmap](001-platform-foundation/tasks.md#following-milestones) records the earlier milestones. New milestones are tracked here until their own Spec Kit work begins.

## Large MoE on the Studio pair

Schedule immediately after the comparable-model release of [Spec 005](005-paired-studio-inference/spec.md) passes hardware validation. Qualify a large MoE for private chat and coding. Start with GLM-5.3 mixed 3/6-bit, with Qwen3.5-397B-A17B 4-bit as the lower-memory alternative. The [candidate comparison](005-paired-studio-inference/research.md#large-moe-candidates-after-spec-005) records pinned packs, size estimates, runtime dependencies and the 4-bit GLM quality comparison.

Use the approved trial path. Check two-rank support for the exact pack, license, expected partition sizes, replicated allocations and available disk before staging. Start at one active generation and the 004 workload of 8,192 total tokens including up to 1,024 output. Proposed comfort target is at least 32 GiB of measured available headroom on **each** Studio throughout load, full-context prefill and decode, with normal memory pressure and no increase in swap use attributable to the trial. Stop on a floor violation or missing telemetry. Record peak memory per rank, time to first answer, decode rate and the tested context/concurrency. Qualify longer contexts separately.

Reuse the verified 005 paired path and its matched reference workload. For a pack too large for one Studio, record the capacity refusal without attempting that load. Judge the large profile on independent coding fixtures and a blinded campaign-writing rubric with thresholds fixed before the trial. Require correct publication, verified transport, cancellation, rank-loss recovery and clean release of both hosts. Promote only the exact passing configuration. Live web search and the research workflow retain their own milestone.

## Deep Research

Schedule after live search (T011) and Studio operations (T009), before public release (T014). Add an opt-in web UI mode for research that needs multiple steps and current sources. Qualify a dedicated thinking model on one Studio. If the selected profile requires both, use paired placement after the RDMA milestone (T008).

Reuse the live search provider. Let the model propose bounded searches and source reads through typed tools. Apply consent, egress restrictions, and time, token and request limits outside the model. Treat retrieved material as untrusted. Show progress, cancellation and explicit errors for unavailable search or Studio capacity.

Publish reports with claim-level sources, available publication dates, retrieval times, conflicting evidence and open questions. Use held-out fixtures to measure citation support, recency, coverage, latency and memory. Include search outages, cancellation and injected page instructions in qualification.

## Coding-harness access via API and MCP

Deliver under [T014](001-platform-foundation/tasks.md#following-milestones). Validate on private ingress once scoped credentials are available. Public exposure remains the final release step.

- **Inference API.** Provide an OpenAI-compatible endpoint for model discovery and streaming chat completions. Route approved model aliases through the existing scheduler and publication controls. Verify cancellation on disconnect, token usage reporting and errors for unavailable capacity or exceeded limits.
- **MCP server.** Expose an initial set of read-only, user-scoped tools and resources for retrieving authorized Project context once T010 is available and checking owned job status. Check role, credential scope and resource ownership on every request. Verify that MCP credentials cannot invoke administrative actions or access another user's data.
- **Client qualification.** Run a real coding session using fios inference from Pi, fx.sh and a named VS Code extension. Record the tested versions, setup and supported API and MCP capabilities for each client. Exercise model selection, streaming, cancellation and, where the client supports MCP, the authorized tools. Verify revocation, access denial and quotas on both surfaces before public release.
