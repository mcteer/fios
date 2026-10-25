# Validation / operations

From reviewed checked main: `docker compose config --quiet`, build pinned application and management images, and start `readiness` before the app migration. Preserve the old image and perform the existing stopped-volume backup/verified app transaction. Start `deployer` only after the initial exact-main migration is verified; seed sanitized deployed-SHA state to avoid repeating that migration. Do not export host gh tokens or mount a source checkout.

Validate `npm test`, build, Playwright, dependency audits and isolated `node scripts/check-agent-container.mjs`. The rehearsal must build/run management toolchain without mounting the socket into any PR test container. Test named-volume observer stop/expiry/restart with mock MLX, then actual authenticated discovery and direct Python readiness without inference. Confirm only deployer has socket access and no lab.fios LaunchAgents remain.

For failures inspect sanitized controller state/logs; do not print Compose resolved credentials. Stop the controller only while idle. Existing same-volume backups and rollback tags remain; do not delete production or legacy volumes. Container network failures require diagnosis/user-approved OS settings, never native proxy fallback.
