# Local inventory interface

The sampler publishes one JSON object to `.fios/observations/<configured-id>.json` on the host. The dashboard mounts that directory read-only. The accepted fields, types and state transitions are defined in the [data model](../data-model.md).

| Request on the Mini | Successful result |
| --- | --- |
| GET / | HTML overview of all three hosts, status text, reporting count and refresh control |
| GET /style.css | Dashboard stylesheet |
| GET /healthz | Plain text `ok` and a newline, indicating dashboard process health |
| GET /api/v1/cluster | JSON with integer version 1, read time in Unix seconds (`observed_at`) and a `nodes` array. Each item contains the Host fields defined in the data model. |

All four reads require a loopback peer, an accepted authority (`127.0.0.1:8741` or `localhost:8741`), and, when supplied, a matching HTTP origin. A cross-site browser request, credentials or a forwarded identity claim yields 403. Unknown local resources yield 404. POST, PUT, PATCH and DELETE yield 405. Denials contain no host observations and cannot modify them. No endpoint accepts a host sample over the network.

A valid read succeeds even when zero hosts are reporting. The UI renders the four state codes as Reporting, Awaiting sample, Stale sample and Invalid sample, respectively for reporting, awaiting, stale and invalid.
