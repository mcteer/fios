# Implementation Plan: Containerized Supporting Services

## Constitution check

Spec first; dedicated branch/PR; custom frontend and exact IDs unchanged. Native MLX/RDMA remain untouched. App has no management socket; a separately isolated, trusted controller retains the deployment authority previously held by the rejected native job. No public ports, host execution or native helper fallback. Persistent volumes, stopped backup, reproducible images and mock-only CI retained. No constitutional exception.

## Design

- Same pinned application image runs `readiness` with a container-only observer entry point and environment configuration (no host .env read or loopback rewrite). Named observation volume at `/app/data` for the observer, `/run/fios-readiness:ro` for app. Nonroot/read-only/cap-drop/no-new-privileges, bounded CPU/memory, no credentials except MLX gateway key.
- Dedicated `deployer` image uses SHA-pinned Node 24 Alpine and exact git/Docker CLI/Compose/flock package versions. No app dependencies, credentials or source mounts. Root is needed for the management socket; explicitly document its daemon-wide trust. Read-only filesystem, private state volume, no ports, separate network and dropped capabilities.
- Reuse tested `deployRelease` transaction. Replace macOS lock/gh CLI with Linux flock and bounded direct GitHub public GETs. Initialize a public git checkout inside the private state volume. Provision only required configuration from service environment; never print secrets. Poll every 180 seconds to stay below anonymous limits. One fixed controller container name plus process lock serializes delivery; controller does not replace itself mid-transaction.
- Immutable `fios:<sha>` releases, compatibility alias `fios:current` after successful verification. App-only `--no-deps` rollout avoids changing/restarting the observer/controller during SQLite-critical operations. Observer remains stable reviewed code; update support images explicitly after checked main when needed.
- Remove the host installer implementation; keep a failing explanation pointing to Compose. Preserve historical spec 005 evidence, add current migration evidence here. No automatic personal GitHub token export.

## Validation and rollout

Unit-test container-only entry points, environment-driven observer, public API gates/failure cases, locking and no-deps rollout. Existing API/Python/browser/security fixtures stay green. Build both images, validate Compose quietly, rehearse hardened app backup/upgrade/rollback on isolated resources and test observer stop/recovery with mock MLX and a disposable volume. Probe actual endpoints from hardened containers without inference. Merge only final-head green CI; wait for merged-main green. Build exact main, start readiness, use one-shot serialized administrative rollout with backup, then start the persistent container controller. Record actual image labels, backup, native removal, host/model counts and socket isolation.
