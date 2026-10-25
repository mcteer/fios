# Research

## Gateway metadata versus host readiness

Decision: never treat `lan_peer` or `state:remote` alone as readiness. Rationale: observed installed MLX-Serve `/v1/models` includes `machine` and `lan_peers`; upstream `src/lan.zig` explicitly retains installed peers across failed resolves. Alternative: rely on gateway expiry, rejected because stale entries can remain usable-looking.

Sources inspected without inference: installed MLX-Serve bundled skill, public `ddalcu/mlx-serve` sources `src/lan.zig`, `src/server.zig`, app ServerManager, and live read-only health/catalogs. Research copies live under `/tmp/fios-mlx-readiness-research/`, not committed. Installed local service is the app's `mlx-serve` child, not a launchd service. Do not assume restarting launchd restores it.

## Peer trust

Decision: explicit `MLX_PEER_URLS` configuration, no automatic probes to gateway-advertised URLs. Rationale: prevent catalog-driven SSRF and key forwarding. Alternative: probe every `lan_peers.url`, rejected. Unconfigured or unauthorized peers must be unknown and blocked, not silently trusted.

## Loaded state

Decision: advertised local model on healthy host is available on demand even when unloaded. Rationale: installed bundled skill documents lazy load on generation; discovery must not load models. The observed exact Gemma ID is `mlx-community/gemma-4-e4b-it-4bit`, state `unloaded` at initial inspection.

## Observed container reachability refinement

Direct peer probes succeeded natively but timed out from the hardened ARM64 image. Changing native routing/RDMA, exposing a new host port or giving a CI runner host access is not authorized. Chosen alternative: a native fixed-endpoint observer atomically emits bounded, endpoint-bound health/catalog metadata to a directory mounted read-only into the container. Node/Python independently reject observations older than 5 seconds, mismatched endpoints, future timestamps and malformed/missing files. A single-shot observation deliberately expired while an image built and correctly became unknown; continuous native observation then verified all three hosts and all five chat models from the hardened image, without inference. No new listener, Docker socket or remote execution is introduced.

## Harness boundary

Decision: Node and Python independently validate against the same contract and parity fixtures. Rationale: model listing must remain operational if the Python worker cannot start; direct Python harness calls must not bypass readiness. No inference fallback, retries or substitution added.
