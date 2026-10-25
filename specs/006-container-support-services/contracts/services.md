# Supporting-service contract

`readiness`: Linux container entry point `node scripts/observe-hosts.mjs`, environment MLX_BASE_URL/MLX_API_KEY/MLX_PEER_URLS, output /app/data/peers.json. No listener, inference, host .env or Docker socket. Shared volume root owned by app UID 1000. Host CLI persistent execution is rejected.

`deployer`: fixed Compose container name fios-deployer, Linux-only entry point, singleton flock in /state. Explicit daemon-wide socket at /var/run/docker.sock plus private state volume; no host source/config mounts or public ports. App configuration arrives through Compose environment. Public GitHub API uses bounded nonredirecting HTTPS, no personal token. Only exact checked merged main is built; supporting images stay stable during app transactions. Source checkouts on macOS cannot affect running code.

`install-deployment.mjs`: always exits nonzero with container instructions; never writes native jobs.

No browser/API/IPC schema change. Existing independent readiness gates and privacy/authentication limits apply.
