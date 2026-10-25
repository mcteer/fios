# ADR 0001: Replace Open WebUI with a purpose-built Fios frontend

Status: Accepted (retrospective record of the existing decision)

## Context

[Feature 001](../../specs/archive/001-open-webui/spec.md) originally deployed Open WebUI as a coding-oriented interface to the existing native MLX-Serve gateway. It established local authentication, persistent storage, container deployment, and gateway connectivity.

The user rejected Open WebUI's look and feel and requested a from-scratch frontend with a deliberate, professional chat experience. This decision was recorded in the [constitution's v2.0.0 amendment](../../.specify/memory/constitution.md), but had not previously been captured in an ADR.

## Decision

Retire the Open WebUI deployment and supersede feature 001 with [feature 002: Professional Fios chat](../../specs/002-custom-frontend/spec.md).

Build and maintain a purpose-built React/Vite frontend and Express/SQLite backend, packaged in an OrbStack Docker container. Implement the required chat, streaming, model selection, attachments, Markdown/code rendering, and conversation persistence directly rather than inheriting a prebuilt chat application's interface.

Keep inference native on macOS. The existing MLX-Serve gateway remains responsible for model discovery and routing; preserve exact model IDs and leave RDMA configuration unchanged. Retain localhost binding, authentication, persistent storage, and the prohibition on arbitrary execution and Docker socket access.

## Alternatives

- **Continue with Open WebUI or customize its interface:** would retain the existing deployment, but would not satisfy the user's explicit request for a from-scratch experience.
- **Adopt another prebuilt chat application:** would inherit another application's interaction model rather than establish the purpose-built UX required by the constitution.
- **Build a custom frontend and backend (selected):** provides control over the required experience and local-first architecture, at the cost of owning implementation and maintenance.

## Consequences

- Fios owns its UI, API, authentication, storage, attachment handling, and associated security and validation responsibilities.
- Feature 002 and its validation evidence describe the replacement; feature 001 remains archived as historical context, not an active deployment or current acceptance claim.
- The Open WebUI container and images were removed. The detached legacy `fios_webui-data` volume remains preserved and unused; deleting it requires approval.
- This decision does not authorize changes to the inference cluster, RDMA, public/LAN exposure, or remote execution.
- Acceptance of this architectural decision does not imply that all visual or browser acceptance criteria have been approved; consult current feature validation evidence.
