# Data Model

- Observation volume `fios_fios-readiness`: existing v1 peers.json schema, endpoint hashes and per-host checkedAt; max age five seconds/future tolerance one second. Observer writes atomically; app reads only. No credentials/prompts.
- Deployment volume `fios_fios-deployment`: private git objects, immutable release archives, empty Compose env file, kernel lock file, heartbeat and state.json. State contains SHA/image/time/backup/safe error only; credentials remain container environment, not git archives or state files.
- Release: exact 40-hex main SHA, required successful push workflow and all six completed/success checks. States waiting→building→rechecked→stopped/backed-up→verified→published; failure→prior compatible image verified or explicit rollback failure. Successful publish tags immutable image as fios:current. Failed SHA is not automatically retried.
- Native artifacts: removed LaunchAgents/plists/programs/observations; retain historical sanitized rollout evidence and stopped-data backups. No live database is opened by controller itself.
