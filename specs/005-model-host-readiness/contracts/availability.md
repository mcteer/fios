# Availability Contract

Authenticated `GET /api/models` returns `{models, hosts, checkedAt}`. Gateway failure is represented by an unavailable gateway observation and no ready models, not an app-liveness failure. Express may retain former rows only as unavailable. Existing clients ignoring added fields remain compatible, but current UI must gate on `availability === "available"`.

Probe each configured base's `/models` and sibling `/health`, at most 2 seconds/read and 1 MiB per response; no redirects or inference. Health requires HTTP 200 and `status:ok`. Catalog requires HTTP 200 and a bounded well-formed array. Safe reasons include `ok`, `host_down`, `unauthorized`, `invalid_catalog`, `host_unverified`, `not_advertised`, `gateway_unavailable`.

Model identity: use `lan_peer` plus a matching exact `@peer` suffix; local entries have no suffix. Direct host catalog must contain the corresponding bare ID with no peer marker. Never alter the model ID sent to inference. A valid model with `loaded:false` is still available on demand.

Production peer observations may cross the container boundary only through `MLX_READINESS_FILE`, a read-only native-observer metadata file. Each record is validated against the explicit peer URL fingerprint, fixed schema, 5-second maximum age and 1-second future tolerance. Missing or invalid evidence produces unknown status and blocks inference, never a direct-network or stale-ready fallback. Gateway checks remain live. Native callers without this file probe peers directly. The observer must not follow catalog URLs, invoke inference or expose a listener.

Python harness adds terminal `error` code `model_unavailable` when its independent preflight rejects the target. This contains no upstream bodies, addresses or credentials. Express rejects unavailable selections with 503 before message persistence. Discovery and preflight cause zero inference requests and perform no model loading.
