# 001 — Fios inference frontend

Status: Deployed; backend connectivity verified; administrator/browser acceptance pending

## Context

Fios (Gaelic: knowledge/information) serves coding-oriented access to an existing MLX-Serve deployment. The frontend host is an M4 Pro Mac Mini with 24 GB RAM; two M3 Ultra Studios with 256 GB each run the larger models and are already clustered over RDMA/Thunderbolt 5. OrbStack provides Docker on all hosts.

## User stories and acceptance

### US1 — Access shared models (P1)
As a developer, I can sign in to Open WebUI, select an advertised chat model, and receive a streamed coding response from the existing gateway.
- AC1: ARM64 Open WebUI runs under OrbStack and serves a healthy HTTP UI on port 3000.
- AC2: The container can query the Mini gateway's `/v1/models`, including peer-qualified Studio IDs without rewriting them.
- AC3: An explicitly selected, already-loaded Studio model produces a valid SSE response ending in `[DONE]`.
- AC4: Browser model selection, streaming, and saved chat history are verified by an administrator after account creation.

### US2 — Safe administration (P1)
As the operator, I can create the first administrator locally, disable subsequent signup, and retain accounts/chats through container recreation.
- AC5: Localhost binding and authentication are default; signup defaults off; secrets are private and ignored by Git.
- AC6: Persistent named volume and stable generated secret survive ordinary stop/start and recreation.
- AC7: No Docker socket, privileged mode, or code execution is enabled. Health checks do not load models.
- AC8: Backup, restore, upgrade, rollback, and LAN exposure instructions are documented.

### US3 — Evolve with specifications (P2)
As a maintainer, I can add features through actual upstream Spec Kit templates, scripts, and prompts.
- AC9: Constitution, feature spec, plan, tasks, and validation evidence are tracked alongside upstream scaffolding.

## Requirements and boundaries

The gateway is configurable, defaults to `http://host.docker.internal:11234/v1`, and owns routing/model discovery. API credentials are configurable. Configuration changes take effect on container recreation rather than being silently overridden by stored UI settings. Do not download/load heavyweight models automatically or change RDMA topology. Non-chat entries may be advertised by MLX but image/audio/video workflows are not acceptance targets. Do not enable public access, SSO, RAG, editor integrations, or remote sandboxes in this feature.

## Failure cases

If MLX is down, UI health may remain green; the separate connectivity check must fail. Discovery success alone does not prove inference or distributed execution. Studio failure and request retry behavior are owned by MLX and require a future resilience spec. Cold-model requests may need long startup times and should be tested deliberately.
