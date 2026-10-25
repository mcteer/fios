# Validation Guide

1. Install locked Node/Python dependencies using AGENTS.md; rebuild the noneditable Python package after source changes.
2. Run new readiness/parity tests, then full Node/Python, frontend, browser, audit, boundary and isolated ARM64 recovery checks. Hosted CI must pass on the latest PR head before merge.
3. Configure private `MLX_PEER_URLS` with exact MLX peer names and trusted v1 bases. Never print `.env`, credentials or resolved Compose settings. Check unknown peers are disabled, not treated as ready.
4. Run a feature app with a separate temporary database. Verify the exact local Gemma ID appears available but possibly unloaded. Stop only the authorized local native MLX process, confirm gateway/model unavailability and rejected sends with no persisted messages, then restore the original service and verify recovery. Do not start another app against production SQLite.
5. Merge only after all checks pass; wait for merged-main CI. Preserve the deployed image and stopped-data backup, deploy the exact approved revision with existing hardening, verify liveness and authenticated discovery without inference, and report the deployed revision. Roll back on failure. Do not change RDMA or remote services.

Observed outcomes and any blocked step belong in validation.md; a plan or mock result is not evidence of successful production deployment.
