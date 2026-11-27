# Validate Spec 1

Use a supported Apple Silicon development Mac with Python 3.15, Make, Codex and OrbStack in Docker mode. Run from the repository root. The initial tool install and container build need access to their published dependencies. The following checks use local observations and require no model token.

1. Run `make spec-tools` and `make check`. Expect a healthy Codex integration, a resolved foundation feature, passing application tests and a valid Compose configuration.
2. Run `make dashboard` on the Mini. In OrbStack the fios project should show a healthy fios-core-1 container. Open the [local dashboard](http://127.0.0.1:8741/) and select Refresh status. Expect three host cards. With only the Mini sampler active and no Studio samples, one host reports and two await samples.
3. Run `curl --noproxy '*' -fsS http://127.0.0.1:8741/api/v1/cluster`. Compare the Mini timestamp and measured values with the dashboard at the same sample. After the next sampling interval, refresh and confirm the timestamp advances.
4. Run `curl --noproxy '*' -i -H 'Origin: https://example.invalid' http://127.0.0.1:8741/api/v1/cluster`. Expect 403 with no inventory. Run `curl --noproxy '*' -i -X POST http://127.0.0.1:8741/api/v1/cluster` and expect 405.
5. Run `.specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks`. Confirm this feature directory and its task list. The full local development workflow is in the [repository guide](../../README.md).

Exercise the freshness boundary and invalid inputs against synthetic samples in a temporary directory. Keep the running operator preview available. At 30 seconds the single valid sample counts as one reporting host. At 31 seconds the count becomes zero and the timestamp and measurements remain visible. A malformed sample should show Invalid sample and no measurements.
