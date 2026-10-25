# Validation evidence

Validated on the actual Mac Mini under OrbStack, 2026-10-23 local date.

## Passed

- `docker compose config --quiet`.
- `python3 -m unittest discover -s tests -v`: all six tests passed (auth/execution configuration, local binding, no host control mounts, persistent storage/version pin, private ignored secrets, idempotent setup).
- Upstream image `ghcr.io/open-webui/open-webui:v0.12.3-slim` is ARM64; observed repository digest `sha256:5adfb0355bbe4a5860c0ba9482cc0b40f573de3749a21a64cf4789391a14fffc`.
- `docker compose up -d --wait --wait-timeout 120`: healthy, including after configuration-driven container recreation.
- `GET http://localhost:3000/`: HTTP 200.
- `GET /health`: `{"status":true}`.
- Public `/api/config`: name `Fios (Open WebUI)`, version `0.12.3`, slim true, authentication true, signup false.
- Unauthenticated `/api/models`: HTTP 401.
- `scripts/check.py`: container reached `http://host.docker.internal:11234/v1/models`, returning nine entries including both Studio peers and chat-capable coding models.
- Explicit streaming request via `scripts/check.py --model 'ddalcu/Qwen3.8-Flash-Next-MLX-Serve-iQ-MLX-4.7bpw@fios-edge-b.lab'`: returned `Fios connected` with content chunks and terminal `[DONE]`. Repeated successfully after recreation.
- No cluster/model-serving configuration was changed. Smoke test used an already-loaded Studio model.

## Pending / limitations

- No administrator account was created on the user's behalf. User must perform local bootstrap, then confirm signup remains disabled.
- Authenticated browser → Open WebUI → MLX full chat flow, coding usability, and saved history remain manual acceptance checks. The streaming smoke test exercises the configured gateway from the application container, not an authenticated WebUI proxy request.
- Accounts/chats surviving recreation, backup restore, failover, multiple users, tool calling, and cold loading of other models were not tested.
- Gateway routing to a Studio was verified; distributed sharding/RDMA behavior itself was not independently measured.
- UI is deliberately localhost-only. LAN hostname, TLS, firewall policy and SSO are not configured.
- Sandbox feasibility is documented only; no remote runner or execution privilege is enabled.

## Operational note

Initial standard-image pull was replaced with the much smaller upstream slim image (about 197 MB compressed for ARM64) because this feature only needs remote inference. Background slim deployment completed successfully; no deployment job is required to remain running. Containers restart automatically under OrbStack's normal availability.
