# Transient Availability Model

No database migration.

Production observation transport: native `scripts/observe-hosts.mjs` emits `{v:1, peers:[...]}` into an atomic metadata file. Each record has configured name, SHA-256 `endpointHash`, status/reason, `checkedAt` and bounded local model metadata. No URL, API key, prompt or content enters this file. A read-only directory bind gives the container access; clients reject records older than 5 seconds, over 1 second in the future, or not matching the configured endpoint. Missing/invalid/special/symlink files fail closed. The collector must run natively because actual container-to-Studio direct probes timed out. No new listener or routing change is used.

Host: `name` (`gateway` or configured peer), `status` (`available`, `unavailable`, `unknown`), `reason` (fixed safe code), `checkedAt` (epoch milliseconds), `modelCount` (local catalog count). No URLs, credentials, raw upstream errors or machine inventories are exposed.

Model: existing `id`, `loaded`, `capabilities`, `peer`; add `state` (upstream loaded state or derived ready/unloaded), `availability` (same enum), `reason` and `host`. Only `available` enables send. Unloaded state is not a readiness failure.

Catalog: `models`, `hosts`, `checkedAt`. Previously observed absent rows may be retained by Express only with unavailable status and a safe reason. New successful observations replace old status. An outage never leaves stale ready rows. Host recovery does not silently change the selected model.

Configuration: `MLX_PEER_URLS` is a JSON object with up to 16 peer-name → absolute http(s) v1-base entries; reject embedded credentials, query, fragment, control characters and invalid ports. Only configured endpoints are ever fetched; gateway credentials apply only to the gateway.
