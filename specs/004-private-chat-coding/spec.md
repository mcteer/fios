# Feature specification · First private chat and coding

**Feature** `004-private-chat-coding` · **Created** 2026-11-27 · **Roadmap** [T007](../001-platform-foundation/tasks.md#following-milestones)

## User scenarios and testing

### US1 · Chat privately on the Mini (P1)

The local operator opens the web UI, selects general chat, asks a question and follows up. They can ask for an explanation of the current read-only inventory. This is the first independently usable slice.

1. With a qualified Mini model and both Studios offline, send two related turns. The second answer uses the first exchange, and the UI identifies the serving revision and usage.
2. Start generating, then use Stop while the UI is receiving output. The UI shows the terminal outcome, accepts no further answer text for that job and permits a new turn once capacity is safe.
3. Reopen the UI. The history lists the conversation under an automatically generated title that describes its subject. Select it to continue, then delete it and confirm that its title and turns disappear while another conversation remains.
4. Request a telemetry explanation. Fresh, stale and missing values retain their labels. Any suggested management action is inert text.

### US2 · Get coding help on one Studio (P2)

The operator selects coding and submits source text for explanation or a proposed change. They can inspect and copy the answer without granting access to local files or tools.

1. With one qualified, enrolled Studio, submit a coding question. Exactly one Studio serves it. Code displays as selectable literal text. The Mini remains available for general chat.
2. With no qualified Studio, show the reason coding is unavailable. If an admitted Studio disappears mid-answer, show interruption, reconcile its reservation and allow an explicit new submission after recovery.

### US3 · Decide which models may serve users (P2)

The admin can inspect isolated trials and explicitly enable or withdraw a pinned hardware/model/runtime combination for each alias. This story can be tested with an independent candidate and fixture runner.

1. A candidate which exceeds the Mini memory ceiling, fails a required fixture, or lacks evidence remains unavailable. An operator can see which gate failed. A first trial can start with a bounded budget and fresh headroom before a measured peak exists.
2. Changing the model or runtime invalidates the old qualification for the changed combination. Withdrawing an alias stops new work and safely settles outstanding work. Another qualified alias remains usable.

### Edge cases

Cover ambiguous retries after restore, cancellation racing final output, slow readers, overlong context, unavailable publication checks, missing usage, stale capacity, forged owner or origin, runtime crash, and interrupted cleanup. Keep the outcome of an interrupted turn visible separately from the last complete answer.

## Requirements

- **FR-001** Provide a private local text conversation, bounded multi-turn context, visible alias availability, keyboard-operable send/stop controls, and distinct waiting, generating, stopped, interrupted, denied and completed states.
- **FR-002** Route general chat to a qualified Mini and coding to exactly one eligible Studio. Fail closed on missing measurements, stale identity, unqualified revisions or insufficient headroom. Never silently switch models.
- **FR-003** Stream publishable answer text, handle backpressure, allow cancellation during queueing and generation, and fence stale work after disconnect, restart, expiry or withdrawal. An ambiguous retry cannot cause a second inference.
- **FR-004** Enforce local identity, role, owner, request and output publication checks on every applicable path. Withhold prohibited, uncertain and unreviewed output including partial prefixes. Render code and model suggestions as inert text. Apply the same publication policy to admins.
- **FR-005** Preserve private, owner-scoped turn provenance, publication status, revision and tagged input/output usage. Keep prompts, outputs, reasoning and credentials out of operational logs/events. Support clearing private conversation content.
- **FR-006** Qualify each alias against pinned artifacts, license and runtime, exact host class, template, context/output caps, memory, quality, latency, streaming, cancellation, and recovery. Run first-time trials with an exclusive memory budget, a host headroom floor, and automatic abort on unsafe conditions. Require an explicit admin promotion tied to evidence. Permit independent withdrawal and rollback to a still-qualified revision.
- **FR-007** Offer optional read-only inventory context for a Mini chat using data available to the current actor. Label observation times and freshness. All management changes require a separate authorized administrative operation.
- **FR-008** Verify the host agent and execution path on fios-core with two synthetic workers before Studio activity. Require live enrollment and operator-approved qualification before serving real Studio coding. Clean up trial resources and preserve the running preview.

- **FR-009** Keep conversations on the Mini across sessions and restarts until their owner chooses to delete them. Generate a subject-specific title automatically from approved conversation content, show it in history, and delete it with the conversation.

### Key entities

A **model profile** identifies an immutable serving combination. An **alias** maps a user-facing choice to a qualified profile. A **qualification record** records evidence and the operator decision. An owned **conversation** groups turns, each linked to a scheduled job, private content and a publication decision.

## Success criteria

- **SC-001** Complete a two-turn Mini conversation and explain a fixed three-host inventory correctly, including an absent and a stale measurement. With both Studios unavailable, Mini chat and the dashboard remain usable.
- **SC-002** At each admitted context size the peak incremental Mini workload stays below 6,000,000,000 bytes with normal memory pressure and a responsive preview. Record a cold trial and at least five warm trials at the selected cap for each model, reporting first visible answer latency and decode speed separately.
- **SC-003** On one enrolled Studio, generated solutions for two independent held-out programming tasks pass their predefined functional checks. Verify expected template behavior, answer/reasoning separation, streaming, and exact revision for each.
- **SC-004** In queue, running, disconnect, restart, expiry, retry and cancellation-race fixtures, observe at most one start per submission and one terminal settlement. No new answer is released after cancellation acknowledgment. An unconfirmed cleanup continues to hold capacity.
- **SC-005** All denied-origin, role, cross-owner, output-policy and telemetry-injection fixtures produce zero unauthorized disclosures or actions. Unknown counts stay unknown. Clearing removes readable content from the active store and preserves redacted job accounting. With room for only one additional turn, two simultaneous submissions to different conversations admit at most one. After settlement or deletion frees sufficient space, a new turn can use it.
- **SC-006** Rehearse a first trial with no measured peak, a refused start with insufficient headroom, automatic abort on a trial budget breach, promotion and withdrawal in isolation. Verify the failed candidate stays disabled and its slot remains held until cleanup is verified. Record qualification and rollback evidence separately for the Mini and the Studio. Verify the original preview is healthy and run-owned resources are accounted for after success and interruption.

- **SC-007** Across three distinct conversation topics, each title names its expected subject and distinguishes it from the other two. After a service restart all three reopen with their original turns. Deleting one during generation prevents further publication and removes only its title and content from active history.

## Assumptions and boundaries

The browser UI ships in its own OrbStack container. The native storage service exclusively owns the databases on the Mini. MLX runs natively on each Apple Silicon Mac to use Metal and unified memory. Worker processes, MLX runtimes, policy service, and databases have independent lifecycles. Each host gets its own management-agent container under roadmap T009, with a native supervisor for host measurements and OrbStack recovery. A UI upgrade or restart preserves native history and requires no database access or migration from the UI container.

The only live principal is the trusted, unauthenticated local admin on the Mini. The supported roles remain admin and user. Model downloads, hardware trials and installations are implementation and operator rollout activities. Distributed inference, Projects, live search, image generation, defensive review workflows, sandboxes, public accounts and automated dependency recovery retain their respective roadmap milestones.

## Clarifications · 2026-11-27

The existing roadmap resolves placement, model promotion, ownership and scope. Mini chat can qualify and ship independently. One approved Studio is sufficient to qualify coding. Inventory explanations are opt-in for each turn. Candidate model names express a trial preference, and promotion requires measurements on the intended host. The operator confirmed that conversations persist locally until their owner chooses deletion and that fios generates a title reflecting each conversation's content. Concurrent turns share one per-owner quota. Once the quota is committed, the owner can free space by deleting conversations or by waiting for an active turn to release unused space.
