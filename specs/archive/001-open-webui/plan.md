# Implementation plan

## Architecture

Browser → localhost:3000 → Open WebUI (OrbStack ARM64 Linux) → host.docker.internal:11234/v1 → native Mini MLX-Serve gateway → existing Studio peers / RDMA cluster.

Use upstream Open WebUI v0.12.3-slim (latest release reported by GitHub during setup; slim avoids unnecessary local ML dependencies), a named data volume, generated secret, 4 GiB/4 CPU limits, and a lightweight `/health` probe. No additional proxy or model server is needed. Keep the cluster's exact model IDs, including `@fios-edge-*.lab` suffixes. Do not infer model sharding from a catalog entry alone.

## Research and decisions

- Local process inspection found MLX-Serve listening on 0.0.0.0:11234; `/v1/models` returned both Studio peers at 192.168.4.11 and 192.168.4.12.
- OpenAI-compatible connection settings are supplied server-side; the browser does not need MLX credentials.
- Disable persistent configuration so environment configuration remains authoritative. Admin changes to environment-backed settings must be made in `.env`.
- Signup stays off in committed defaults; bootstrap happens locally with a temporary override. No administrator password is generated or stored by this project.
- Open WebUI executes neither code nor agents in this phase.
- Spec Kit initialized with upstream CLI from commit `67e0f7294e6e728ab60bf7b4590deb470448bc2d`, generic integration, shell scripts. Installed scaffolding is tracked, not a hand-written substitute.

## Validation strategy

Validate Compose without printing resolved secrets. Validate private setup and idempotency. Wait for UI health, then run `scripts/check.py` within the service to exercise OrbStack host routing. Opt in to a short streaming request against the already-loaded Studio model. Leave browser/account, persistence, restore, and failover checks explicitly pending until performed.

## Future sandbox research

See `docs/sandboxes.md`; a separate spec and security review are required before exposing an execution tool to models.
