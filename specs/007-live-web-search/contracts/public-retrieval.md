# Contract: Python Tool Public-Web Retrieval

Only `web_search` inside the Pydantic harness invokes this boundary. The model supplies a query, **not** a URL, engine, headers or request method. Search endpoint is fixed to **`http://searxng:8080/search`** on the private Compose network. This is the sole explicit private-HTTP exception, implemented in a separate credential-free client, not a relaxation of the public page transport. Query parameters are fixed except the validated query: JSON/general/en/safe-search1/page1; no model-selected URL/engine/pagination. Organic result URLs remain untrusted and public-only.

## Fixed budgets (first limit wins)

| Budget | Limit |
| --- | --- |
| Tool attempt / query | 1 / 1 per user turn; no pagination or retry |
| Retained organic results | 5, deduplicated by normalized URL |
| Page chains attempted | 3, ranked order; no further link following |
| Concurrent public sockets | 2 |
| HTTP attempts | 14 harness attempts including the one gateway request, public robots and redirect hops. SearXNG's separate Bing/Brave engine fan-out is not counted as harness HTTP; do not claim14 total wire requests across both processes |
| Redirects | 0 for provider/robots; <=2 per page chain; each target validated and site rules checked |
| Tool wall time | 15s from invocation; monotonic; no budget reset |
| Provider / other request | 6s gateway absolute (5s client timeout) / 4s public requests, within15s tool deadline; upstream engine timeout3s/max4s |
| DNS / parser | 2s / 1s, additionally bounded by remaining tool time |
| Body | 1 MiB/provider or page, 64 KiB/robots, 5 MiB aggregate; header bytes <=32 KiB |
| Encodings/types | identity only; gateway application/json, public UTF-8 text/html or text/plain; skip compressed/binary/unsupported charset |
| Result URL/title | <=2,048 / <=300 UTF-16 units |
| Excerpt / total enrichment | <=3,000/source; <=16,000 UTF-16 units including framing; serialized tool evidence <=64 KiB |
| Parser resources | one private parser subprocess at a time, address-space64 MiB/CPU1s, installed isolated Python, bounded stdin/stdout, no shell/DB/listener |
| Robots cache | in-memory <=128 origins, <=1hour, obey stricter HTTP no-store/cache expiry; no query/result cache |
| Provider limiter | worker-wide min5s between searches, <=12/minute; no delayed replay queue |
| Provider block/429 | >=60s cooldown; honor the full valid Retry-After, including >15min; no immediate retry, delayed replay or shortened deadline |

This rate limit is Fios protection, not an entitlement from SearXNG's upstream engines. Stricter site crawl-delay/request-rate rules also apply; skip if they cannot be honored within the deadline. Cache/cooldown are worker-memory state and reset on worker restart; this is not durable rate-limit enforcement across restarts. Do not restart/rotate workers to evade a known restriction, and do not replay interrupted requests.

`Retry-After` accepts delta-seconds (unsigned decimal integer) or an RFC HTTP-date. Parse at receipt using bounded header input; compute a monotonic not-before deadline from max(60s, requested delay), with a past date/zero delay still subject to the60s floor. A valid3600s header forbids a new provider request at900s; it is never clamped to15min. Missing header uses60s. A present malformed, conflicting duplicate or nonrepresentable value fails closed: suppress provider requests for the remainder of that worker's lifetime rather than inventing an earlier retry time. Valid values longer than the tool deadline do not keep a run open: finish the current tool with its blocked/rate_limited outcome; later calls return rate_limited without network access until allowed. Expiry only permits a **new model-requested tool invocation**, never a scheduled retry. Fixture coverage includes seconds/HTTP-date, >15min, zero/past, missing, malformed and numeric/date overflow.

## URL, resolver and connection rules

1. Parse strictly with length/control/encoding validation. Allow only HTTP80/HTTPS443; no userinfo, IP-literal authority, ambiguous slash/backslash/percent authority, single-label or local suffix (`localhost`, `.local`, `.lab`, `.internal`) names. Reject configured MLX gateway/peer hostnames even if resolution looks public. Never fetch a user-supplied address directly as a tool action.
2. Parse SearXNG organic result URLs using the same public rules; do not treat the internal gateway hostname as an eligible page source. Do not connect to tracking wrappers, ads or arbitrary redirect services as a shortcut. Drop fragments/tracking-only URL parameters; do not execute HTML `<base>`, canonical/meta-refresh or script navigation.
3. Resolve absolute public hostname A and AAAA using the configured container DNS resolver, max2s, no injected DNS server/DoH URL. Validate complete answer set and CNAME terminal name; reject the whole destination if any non-global/special-use/private answer appears. Catch mapped IPv4, CGNAT, NAT64/Teredo/6to4, multicast, documentation, link-local, unspecified and reserved ranges using conservative IANA-informed deny fixtures in addition to ipaddress. Private DNS infrastructure is allowed solely for name resolution, not HTTP.
4. Pin **one** validated numeric IP in the transport's network backend; no implicit re-resolution/fallback address at socket connect. Preserve original hostname for Host/TLS SNI/cert verification. Verify connected server address matches approved numeric IP before transmitting request content. Never disable TLS checks. No proxy environment or Unix sockets, no keepalive reused across differently validated destinations, HTTP/2 disabled for this small boundary.
5. Manually revalidate every page redirect, including public→private, different port, CNAME change and downgrade. HTTPS→HTTP downgrade blocked. Fetch rules for a new target origin before following. The global14-request/15s budget may make some valid chains unavailable; return partial/snippet state rather than exceed limits.
6. Each request starts with an explicit minimal header allowlist: honest User-Agent, safe Accept, Accept-Encoding identity, Host generated from validated URL. No Authorization, Cookie, Referer, user-IP forwarding headers, MLX key, session secret or provider Set-Cookie replay. Separate client/state from authenticated MLX transport.

For public page/robots traffic, the check-and-use boundary lives at **connect_tcp**, not merely URL precheck. Tests inspect actual delegated numeric connection addresses plus TLS hostname, and inject DNS rebinding; a successful mock URL validator alone is insufficient.

## Site rules / parsers

Get `/robots.txt` using the same public transport. 404 means no rules. Disallow, invalid/oversized content, 401/403/429/5xx, timeout or redirect means do not fetch that site's page. Use pinned Protego for agent rules/wildcards and crawl-delay/request-rate; honor stricter cache directives and access refusal. SearXNG delegates its fixed Bing/Brave upstream requests to its packaged engine implementations, outside this custom pinned-IP page transport. No proxy/Tor/key or custom anti-bot bypass is configured; engine failures remain failures. This is a distinct trusted-service boundary, not a claim of identical SSRF/header/robots controls inside SearXNG. Recheck upstream restrictions at acceptance; a later prohibition is a release blocker, not a bypass opportunity.

The gateway JSON adapter requires a bounded results list, reads only URL/title/content, rejects malformed responses and privately addressed sources, and ignores infoboxes/answers/suggestions. Empty with upstream errors is unavailable, not an empty success; usable results with upstream errors remain partial. HTTP denial/rate limits fail explicitly; no engine-set switch or direct-DDG fallback. Bound/dedupe results; no ad click/tracker fetches. HTML parser extracts main/article/body readable text and ignores scripts/styles/forms/templates/navigation/comments/hidden content. No JS/headless browser, images, frames, fonts, downloads, PDFs, login or recursive links. Plain text may be read within identical limits.

Parser subprocess receives only bounded bytes/mode, not MLX secrets or full model context. Parent enforces one-second timeout, kills/reaps on cancel and protocol failure; Linux parent-death protection is tested in hardened container. CPU/memory failures skip that page or fail the provider parse safely. End-to-end tool deadline includes helper startup and cleanup; no thread left parsing untrusted input indefinitely.

## Results and failure semantics

- `retrieved`: all retained evidence is page-backed; `partial`: page evidence exists but some selected sources are snippets/skipped; `snippets_only`: only successfully parsed SearXNG snippets, clearly labeled; each source kind stays explicit.
- `empty`: recognizable zero organic results; `blocked`: challenge/denied provider; `rate_limited`: provider/local limit; `timeout`: wall deadline; `unavailable`: transport/layout/parser/provider failure; `privacy_skipped`: unsafe query; `context_limit`: no useful evidence fits.
- All expected failures return the exhaustive fixed outcome/reason pairs in [data model §2.1](../data-model.md) to the same Agent, consume the attempt and may permit one no-current-evidence continuation. Partial/snippet evidence can be returned on page timeout **within** the global deadline; if the global deadline expires, discard unfinished evidence and return timeout with sources=[]/retrieved_at=null. Never upgrade partial retrieval to full verification.
- Cancellation is not an ordinary search failure: abort immediately, close the harness's gateway/public DNS/sockets/helper and do not resume model generation. Already-started SearXNG engine work can finish under its3s/max4s upstream timeout; cancellation is not a guarantee of immediate remote-service compute interruption. No stale-result reuse or automatic later retry.

## Test isolation

Public HTTP/DNS/clock/parser seams are injected in Python tests only. Mock server traffic uses a dedicated fixture-worker launcher in tests, not production environment variables that bypass public-address protections. Production cannot be told to permit localhost by a browser request, query argument or generic `TEST_MODE` switch. CI must deny real provider/DNS/model egress and test deterministic fixtures; live Python tool/provider smoke is explicitly opt-in, uses a fixed nonsensitive query and a uniquely named disposable Compose SearXNG service, cleaned up with its networks. CI additionally starts the pinned nonroot/read-only SearXNG image with `--network none` and checks static `/healthz`/engine configuration only, never live search.
