# Tasks

- [x] T001 Specify requested scope and select architecture/design.
- [x] T002 Implement durable authenticated API and bounded attachments.
- [x] T003 Implement streaming proxy, cancellation and error persistence.
- [x] T004 Build professional responsive chat UI and Markdown/code copy controls.
- [x] T005 Package non-root production container and private setup.
- [x] T006 Test unit/API/browser behavior and live gateway streaming.
- [x] T007 Document operation, security limits and acceptance evidence.
- [x] T008 Inspect the accessible reference screenshot and implement the reference-driven dark layout.
- [ ] T009 Obtain user approval of the revised visual design.

### Welcome wordmark placement adjustment

- [x] Lower the welcome-screen Fios wordmark without moving the prompt or composer (responsive desktop offset; 24px on mobile).
- Validation: `npm run build` passed. Browser visual verification pending.

- Follow-up: lowered the wordmark another ~24px on typical desktop screens and 16px on mobile. Rebuilt the Docker app successfully; healthy, and verified the live CSS contains the new offset. Visual browser verification pending.

- Follow-up: increased welcome wordmark offset to clamp(72px, 14dvh, 140px), with 60px on mobile. Docker rebuild and health check passed; verified updated CSS served by the live app. Visual browser verification pending.

- Follow-up: increased welcome wordmark offset to clamp(96px, 18dvh, 180px), with 80px on mobile. Docker rebuild and health check passed; verified live CSS. Visual browser verification pending.

- Changed sidebar and welcome wordmarks to lowercase `fios`. Docker rebuild and health check passed; visual browser verification pending.

### Custom lowercase brand wordmark

- [x] Added a custom path-based lowercase SVG wordmark with rounded strokes and sage-green i dot; applied to main workspace and sidebar, plus matching fi favicon. Preserved existing welcome positioning.
- Validation: `npm test` passed; Docker production rebuild and health check passed; live SVG asset fetch verified. Browser visual verification pending.

- Replaced hand-drawn rounded wordmark with outlined Space Grotesk SemiBold lettering for a geometric, technical appearance. Bundled SIL font license; no external font requests. Existing placement preserved. Docker rebuild and health check passed; live SVG verified. Visual browser verification pending.

### Architecture decision record

- [x] Added retrospective ADR 0001 for replacing Open WebUI, linked it from README and marked archived feature 001 retired/superseded while preserving historical validation status.
- Validation: checked changed Markdown local links and `git diff --check`; documentation-only change, no runtime tests required.
