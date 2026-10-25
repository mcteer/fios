# Tasks: Containerized Supporting Services

**Status**: Complete and closed (2026-10-25), T001–T008 complete. PR #3 merged and deployed as `84418cdf2ec9d08e44e3bf0f6f59872734be5983`; final outcomes reconciled from PR evidence into validation.md.

- [x] T001 Specify user requirements and plan on the dedicated branch; record constitutional/security boundaries in spec.md and plan.md.
- [x] T002 Remove rejected native jobs/programs, retain data/backups/evidence, and record container-only policy in AGENTS.md.
- [x] T003 [US1] Containerize scripts/observe-hosts.mjs, Dockerfile and compose.yaml using a named metadata volume; extend tests/readiness-observer.test.js.
- [x] T004 [US2] Replace native poller/installer with container-only delivery, pinned Dockerfile.deployer, public API checks and private container state; extend tests/deployment.test.js.
- [x] T005 [US3] Update README.md/.env.example and operational contracts; analyze coverage and guard against native services/socket leakage.
- [x] T006 Run locked unit/Python/build/browser/audits/config and isolated hardened upgrade/rollback plus observer/container-runtime checks; write validation.md.
- [x] T007 Open reviewed PR, require final-head green CI, merge exact head and await merged-main CI.
- [x] T008 Deploy reviewed container stack with stopped backup, verify production observer/harness/model states and no native jobs; record administrative outcome in PR/report.

Dependencies: T001→T002→T003/T004 (parallel files apart from Compose integration)→T005→T006→T007→T008. US1 independently proves readiness stop/recovery; US2 proves gates/backup/rollback; US3 proves installer rejection and durable policy. Deliver/test incrementally, never enable unmerged controller code against production.

Coverage: FR-001/002→T002/004/005; FR-003/004→T003/006; FR-005/006/007→T004/006; FR-008→T005–008. SC-001/005→T002/006/008; SC-002/003→T003/006/008; SC-004→T006–008. No unresolved clarification. Native removal is an explicitly user-authorized immediate operational revert, not an unreviewed product deployment.
