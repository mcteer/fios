# Withdraw an unattached preparation reference without a native proof

This internal helper removes only an exact reserved CPU bookkeeping claim.
It returns `void`. It issues no inference not-sent/completion proof, releases
no physical/native capacity or inference lease, and changes no native registry,
backend object, service intent or SQLite record. Missing lineage after withdrawal
remains absence of metadata, never proof that inference was not sent.

The source guard must be enabled and initialized/certain. Token, exact model,
correlation, original root, reserved/preparing stage, one model association and
single reference must match. Attached, retained, forked, active, auxiliary or
ordinary impersonating roots refuse. Other roots remain intact. Uncertainty
refuses and is never cleared. Maintenance permits this local removal while
keeping admission closed and its pause identity unchanged.

A reserved claim may have historical completed descendants; this helper does
not attest that native preparation never ran. It checks current bookkeeping,
not native terminality. Callers must not convert success into an inference proof
or fall back to weaker cleanup after refusal. The public edge checks its fixed
negative source before locking; `Known` is callback-free for trusted outer-lock
composition. The actual serving guard remains unsupported, with no transport
or serving caller added.

CPU tests cover exact/unrelated identities, reference/attachment/phase rejection,
independent uncertainty, maintenance, probe ordering, replay and a two-thread
attach/withdraw race. The original missing interface is recorded as interface
absence rather than a behavioral red. Native enclosure and exact evidence are
tracked in [validation](../validation.md); whole native admission/acceptance is
not supplied by this helper.


Final selected-source checks pass:2 original-interface witnesses/8 controls/
40 candidate CPU cases, default162/162, enabled35/35 semantic32/32 link,
4 empty-model runtime checks and post-run byte review. Aggregated2a3eb52…
binds exact scopes in validation. No transport/serving caller or inference
proof/admission authority follows from this subset; whole tasks remain open.

The separate [pristine preparation closure](pristine-preparation-close.md) adds
monotonic retention history and a distinct version2/op3 operation. It does not
upgrade this withdrawal acknowledgement. Only its complete original-scope
compound no-spawn/close decision path can record `not_sent`; neither operation
establishes device completion, capacity or all-client idle.
