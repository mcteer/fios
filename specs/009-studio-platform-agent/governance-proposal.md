# Governance amendment — accepted for implementation

**Status**: The user reaffirmed proceeding after the specific amendment/read-only inspection scope was presented. Applied as constitution2.1.0 and the narrow AGENTS exception; rationale/affected-spec review in [ADR0003](../../docs/adr/0003-studio-platform-agent.md). The proposal below is retained as the approved scope. No installation, privilege, native integration change, inference or deployment permission is implied. Generic document remediation alone was not used as authorization.

## Rationale

The user requested a manager on both Studios that survives OrbStack failure, owns temporary agent sandboxes and supports local model use. Confirmed A/A/A means boot supervision before login, authoritative activity for every native client and no sandbox external network. Current constitution2.0.0 disables arbitrary code execution, and AGENTS requires containerized support services with daemon authority confined to the existing deployer. Implementing009 without an explicit amendment would violate those rules.

## Proposed narrow changes for a separate review

1. Increment the constitution to **2.1.0**, document amendment date/rationale, and review affected006/007/008/009 contracts before implementation.
2. Principle3/5: retain native MLX/RDMA and the Compose deployment baseline. Permit only the reviewed009 native unprivileged supervisor/manager/session adapter and short-lived private model workers needed to manage the two approved Studios. Reproducibility requires versioned native manifests, exact artifact identities, explicit operator installation and backup/rollback. No RDMA/network/scheduling/model-policy changes are implied.
3. Principle4: retain authentication, localhost-first, secrets protection and prohibition of arbitrary **host** execution. Permit explicitly authorized, finite code execution **only inside009's network-isolated ephemeral sandboxes**, from reviewed immutable images, under enforced resource/lease/ownership constraints. No runtime socket, host mount/namespace, host credential, privileged mode, external network or public listener in sandboxes. Model output cannot grant permissions.
4. AGENTS: retain006's container rule for all other supporting services. Record009 as the sole additional native management exception, not revival of005's disabled installer. Add the platform manager as a separately trusted daemon-authority boundary; never give its runtime capability to the app, observer, Pydantic worker, sandbox or PR-built test image. Docker socket authority is not read-only just because commands are filtered.
5. Keep interface-originated inference within Pydantic. A separate bounded private platform-worker entry point may support009 jobs without extending007 tools/retries/budgets or reading Fios SQLite. No general model-driven Docker, SSH, file or shell tools.
6. Native installation, privileges, forced-command SSH enrollment, real lifecycle/inference tests and deployment remain separate explicit operator gates. Existing app-only automatic deployment remains unchanged and cannot install native programs from a PR/worktree.

## Affected artifacts to review

- Active constitution principles3–5 and AGENTS support/daemon/harness rules.
-006's Compose baseline and disabled native installer: remain intact; append scoped009 exception rather than rewriting historical validation.
-007: no new tools, transport permissions, socket mounts or inference retries.
-008: all-client activity/admission contract may unblock later work, but008 remains parked and unmerged.
-009: this plan/contracts/tasks must reflect the approved wording; if approval changes scope, re-run analysis before implementation.

## Approval and rejection behavior

Approval must identify the narrow amendment and affected authority, not merely acknowledge a passing checklist. Apply it as a separate documented governance change with version bump, rationale and affected-spec review, then re-analyze. If rejected, stop implementation; do not replace native supervision with an ineffective container or silently redefine sandbox code as outside the constitution. No operational change follows from policy approval alone.
