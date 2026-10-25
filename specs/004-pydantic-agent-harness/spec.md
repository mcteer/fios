# Feature Specification: Pydantic AI Agent Harness

**Feature Branch**: `004-pydantic-agent-harness`

**Created**: 2026-10-25

**Status**: Implemented and validated on the feature branch (unit/API/browser/isolated ARM64 container); awaiting PR review and approved production deployment. Real inference remains opt-in and untested for this feature.

**Input**: User description: "Add Pydantic AI (slim version) as our base agent harness. Going forward, all interactions with this interface should utilize the Pydantic harness to interact with the backend language models."

## Clarifications

### Session 2026-10-25

- User-confirmed constraints: use the slim Pydantic AI distribution, require the harness for all interface-originated model inference, and place agent code in `src/agent/`.
- Clarification review found no critical product ambiguities requiring another question. Non-inference actions remain outside agent runs; integration topology and provider compatibility are planning decisions, not new product scope. See [clarification review](clarification.md).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One consistent model interaction path (Priority: P1)

As a user, I can choose an advertised local or Studio chat model and receive a streamed response through the shared agent harness, rather than a separate direct model-call path.

**Why this priority**: A single mandatory harness is the core architectural requirement and the foundation for future agent capabilities.

**Independent Test**: Send a message to a mock local model and a mock peer-qualified model, verify each reaches the selected target through the harness, and verify disabling the harness produces an explicit error rather than a direct inference request.

**Acceptance Scenarios**:

1. **Given** an authenticated user and an advertised chat model, **When** the user sends a message, **Then** the harness performs inference using the exact selected model ID and the interface streams the response.
2. **Given** a Studio model with a peer-qualified ID, **When** the user selects it, **Then** the ID is preserved unchanged and the existing gateway routes the harness request to that model.
3. **Given** the harness is unavailable, **When** a message is submitted, **Then** the interface shows a recoverable error and does not bypass the harness.

### User Story 2 - Continue existing conversations without regression (Priority: P1)

As a user, I can continue saved conversations, supply supported attachments, stop responses, and reopen my work without losing the current chat experience during the migration.

**Why this priority**: Adopting a harness must not discard existing data or remove essential functionality.

**Independent Test**: Open a pre-migration conversation in an isolated database, continue it with a text attachment, exercise a vision-capable target with an image, stop a response, and reload the conversation to verify history and terminal state.

**Acceptance Scenarios**:

1. **Given** a saved conversation, **When** it is continued, **Then** prior messages and accepted attachments are included within existing context limits, without duplicated messages or changed roles.
2. **Given** supported text/source files, text-extractable PDFs, or images, **When** they are submitted, **Then** current validation limits and vision-capability requirements remain enforced and their supported content reaches the selected model through the harness.
3. **Given** an active response, **When** the user stops it, **Then** upstream generation is cancelled, received text is preserved, and the conversation leaves its generating state.
4. **Given** a timeout, upstream failure, or interrupted stream, **When** generation ends, **Then** partial output and a clear failure state are retained, without a silent retry or model substitution.
5. **Given** a completed or interrupted conversation, **When** the page is refreshed or the app is recreated, **Then** messages, attachments, and completion status remain available; existing deletion behavior still removes associated data.

### User Story 3 - A maintainable foundation for future interactions (Priority: P2)

As a maintainer, I can extend Fios knowing that every interface-originated language-model request uses the same harness and security boundaries.

**Why this priority**: A partial migration would leave inconsistent behavior and undermine future agent features.

**Independent Test**: Inspect model-call entry points and exercise mocked success, failure, and cancellation cases to prove there is one inference path and no fallback bypass; verify existing authentication and health checks still operate independently of inference.

**Acceptance Scenarios**:

1. **Given** the completed migration, **When** model-call entry points and automated coverage are reviewed, **Then** every interface-originated inference request uses the harness, and the old direct inference path is removed.
2. **Given** a health check, model-list refresh, or conversation-management action, **When** it is performed, **Then** it does not trigger inference or load a model.
3. **Given** an unauthenticated request, **When** it attempts generation, **Then** access is denied before any model request occurs.

### Edge Cases

- An advertised model disappears between selection and submission: return an explicit unavailable-model error; do not choose another model.
- The harness fails before the first token or after partial output: record an actionable failure and leave no stale active generation.
- Stop races with normal completion: produce one coherent terminal state without duplicate assistant messages.
- The app restarts during generation: retain existing stale-stream recovery behavior without replaying the request automatically.
- An image is attached to a non-vision model: reject it before inference.
- A model returns malformed streaming data or unexpected tool requests: fail clearly without executing tools or falling back to direct calls.
- Legacy conversations contain unsupported or oversized context: preserve stored data and apply existing context/attachment limits consistently.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Fios MUST adopt Pydantic AI's slim distribution (`pydantic-ai-slim`) as its base agent harness. Only provider dependencies needed for the existing MLX-Serve integration may be added; versions and reproducible installation must be documented in the implementation plan.
- **FR-002**: Every interface-originated language-model inference request MUST execute through this harness. Existing direct inference code MUST be removed; failure MUST NOT activate a bypass path.
- **FR-003**: The harness MUST use the existing MLX-Serve gateway and preserve exact advertised model IDs, including peer-qualified Studio IDs. It MUST NOT substitute models, automatically load heavyweight models for checks, or alter cluster routing or RDMA configuration.
- **FR-004**: Users MUST retain incremental response streaming, stop/cancellation, explicit error states, Markdown/code rendering, and existing copy controls. If the model supplies reasoning text, preserve its existing transient display separately from answer text; do not add reasoning to saved history or future context.
- **FR-005**: Existing conversations and attachments MUST remain readable and usable after migration without destructive reset. History roles, ordering, attachment semantics, context limits, persistence, and deletion behavior MUST be preserved.
- **FR-006**: Supported text/source, PDF, and image inputs MUST retain existing validation and capability checks; images MUST be supplied as image content to vision-capable models rather than silently converted to text or omitted.
- **FR-007**: Cancellation and failures MUST terminate the active run, preserve received output, and allow a later request. No automatic retry after an inference request has started is permitted in this feature.
- **FR-008**: Existing authentication, same-origin protections, localhost exposure, secret handling, and single-user operation MUST remain intact. Any new harness service boundary MUST reject unauthorized callers and MUST NOT expose a public or LAN listener.
- **FR-009**: Conversation management, model discovery, authentication, and health checks MUST remain available without invoking inference. They need not run through the agent harness; the mandatory harness boundary applies to model inference.
- **FR-010**: Automated tests MUST prove harness traversal, absence of fallback, exact model selection, history and attachment handling, streaming, cancellation, failures, persistence, and authentication using mock inference and isolated data.
- **FR-011**: New interface features that invoke language models MUST use the same harness. This migration MUST NOT introduce tool execution, remote sandboxes, browsing, multi-agent orchestration, or additional model-powered features.
- **FR-012**: Deployment and operational documentation MUST explain harness configuration, lifecycle, dependency installation, health versus inference checks, and troubleshooting without exposing secrets. Tests MUST NOT open the production database concurrently with the running app.
- **FR-013**: Agent implementation code MUST reside in `src/agent/`. The implementation plan MUST account for this location when defining packaging, deployment, tests, and the boundary with the existing frontend and backend.
- **FR-014**: Diagnostics MUST identify failed runs and their lifecycle stage without recording prompts, response/reasoning content, attachment contents, passwords, credentials, or complete environment settings. No external telemetry or cloud inference may be enabled by this migration.

### Key Entities

- **Agent run**: One user-initiated inference attempt, associated with a conversation, exact target model ID, bounded context, streamed output, and terminal state (completed, cancelled, or failed).
- **Conversation context**: Ordered user and assistant messages plus validated attachments made available to a run within existing limits.
- **Model target**: An exact gateway-advertised identifier and its capabilities; may identify a local or network-hosted model.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All model-generating user actions in the acceptance suite use the single mandated inference path; an unavailable harness produces zero bypass requests.
- **SC-002**: All existing chat acceptance flows pass after migration: model selection, incremental output, cancellation, supported attachments, history reload, deletion, authentication, and failure recovery.
- **SC-003**: A pre-migration conversation fixture retains 100% of its stored messages and attachments after upgrade and can be continued without duplicating prior messages.
- **SC-004**: In controlled streaming tests, response text is visible before generation completes, and a stop action ends the active run and upstream request within two seconds.
- **SC-005**: Controlled tests for failure before output, partial-stream failure, and harness unavailability each leave no active generation and allow the next valid message to complete.
- **SC-006**: Deployment health checks and model-list refreshes cause zero inference requests; automated validation requires no real model loading or cluster configuration changes.

## Assumptions

- This spec covers migration of current chat inference and establishes the mandatory path for future model-powered interactions; it does not add new agent tools or workflows.
- The existing React interface and local-first persistence remain the user-facing baseline. The implementation plan will decide the Python harness integration boundary and record architectural consequences in an ADR.
- Model discovery remains owned by the existing MLX-Serve gateway. Non-inference interface operations are not agent runs.
- Existing single-user and concurrency limits remain unchanged; the migration does not add background or parallel autonomous runs.
- `pydantic-ai-slim` is an explicit user-selected architectural constraint, not a recommendation to install the full default distribution.
- Provider compatibility, especially image inputs and cancellation, must be verified against maintained Pydantic AI documentation during planning. Mock tests are mandatory; real inference remains opt-in with an already-loaded or suitably small exact model ID.
