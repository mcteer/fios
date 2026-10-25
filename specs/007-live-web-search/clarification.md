# Clarification Review — Harness-Native Search Tool

Date: 2026-10-25. Branch: `007-live-web-search`. Scope: complete planning through analysis, not implementation.

## User decisions

Two questions asked and answered across the clarification conversation:

1. **Activation:** user selected **B — automatic**, DuckDuckGo provider, no per-message enable/consent prompt.
2. **Execution:** after explicitly rejecting an assistant-selected Node architecture, user answered **“Inside the harness as a search tool.”** The Pydantic AI agent chooses whether/what to search through a real function tool.

The architectural directive is authoritative: Python owns decision/tool/retrieval/evidence. No Node preprocessor, deterministic intent router, cloud/local classifier pass, standalone search service or provider switch. The earlier draft is superseded, not an approved fallback.

## Explicit technical planning defaults

These are visible proposals within the approved architecture, not invented answers from the user:

- Exactly one attempted `web_search`, at most two actual same-model POSTs; zero retries. The second request is a bounded tool-result continuation, not an inference retry. Unknown/repeated/parallel calls fail closed.
- Readable public-page excerpts plus clearly labeled snippet-only evidence; failure results allow one explanatory continuation without claiming fresh verification.
- Model sees existing local history/attachments. Python validates generated query arguments using eligible plain-user provenance, fixed generic words and secret/code/private guards before external access. No claim of perfect semantic secret recognition.
- Public transport pins validated DNS addresses, respects robots, restricts redirects and enforces15s tool/byte/request limits. No scripts/logins/CAPTCHA/proxy evasion. Metadata-only persistence and same-app-container packaging.
- Unsupported models get explicit no-search/error outcomes, never substituted or silently retried without tools. Actual tool behavior for a named model needs a future explicitly authorized inference check.
- Existing one-request/no-tools guidance requires a **narrow explicit exception**, not deletion of all safety restrictions. Tasks include policy/guard update before implementation.

## Coverage review

| Category | Final status |
| --- | --- |
| Functional scope | Resolved: automatic **agent-invoked** harness search tool |
| Data model | Resolved: run deps/one attempt/ephemeral result/safe per-answer metadata |
| Interaction/UX | Resolved: progress, sources, snippet distinction, no-tool/error, answer reset, mobile/accessibility |
| Non-functional quality | Resolved design: explicit budgets/cancellation/rate/memory/context constraints |
| Integration | Clear: pinned Agent APIs and DuckDuckGo HTML candidate; live acceptance is a test gate, not assumed |
| Edge cases | Clear: incompatible model, mixed streams, missing terminator, SSRF, injection, context, rollback |
| Constraints/tradeoffs | Resolved: exact model/local inference/no new service; one narrow tool exception |
| Terminology | Clear: retrieved vs sent-to-model vs factual verification; continuation vs retry |
| Completion signals | Clear: unit/mock Agent/browser/container + separate live provider/model acceptance |
| Placeholders | None; future empirical checks explicitly assigned rather than fabricated as completed |

Quality checklist: reopened14/16 → **16/16** after the architecture answer and coherent rewrite. Newly passing: no unresolved product clarification; testable/unambiguous requirements. No regressions or outstanding product questions. Modified spec sections: clarification, stories, requirements, entities, outcomes and assumptions. No optional architecture decision remains silently adopted outside the user instruction. Technical design is reviewable in plan/contracts; implementation tests may expose changes requiring explicit review.

No extension hooks configured. Technical plan/tasks are drafted; analysis/remediation are part of the user-requested planning scope, not separate implementation approval. No application dependencies, service configuration or model inference changed/run by this clarification.

## Authorized analysis remediation

The user explicitly confirmed that this workflow includes correcting analysis findings and repeating the read-only review. The initial five findings have document-level remedies: T001 separates architecture approval from proposed numeric limits; data-model §2.1–4 defines exhaustive reasons/shapes/nullability/transitions; the retrieval contract honors full Retry-After without a15min clamp; FR-009 scopes `src/agent/` to agent/search execution; all22 story tasks carry their required US labels. Related consistency fixes make manifests immutable before emission, gate citation badges on sent_to_model, atomically persist status/source pairs, recover idle as well as active interrupted retrieval, and introduce test injection before dependent integration tests. These do not move search out of the harness or introduce another service. Implementation tasks remain unchecked.
