# Feature 002 validation

Validated on the Mac Mini under OrbStack, 2026-10-23 local date.

## Automated checks passed

- `npm test`: **11 tests passed**. Covers signed/expiring sessions, split UTF-8 and SSE framing, browser stream framing, SQLite cascading deletion, retained attachment context, aggregate context caps, source parsing, PDF text extraction, image signature classification, and invalid/oversized inputs. The API integration test additionally covers auth, cookie flags, cross-origin rejection, model filtering, streaming, upstream HTTP errors, cancellation, deletion during generation, persistence across backend restart, and subsequent deletion.
- `npm run build`: production React/Vite build passed.
- Initial `npx playwright test`: **2 desktop/mobile browser scenarios passed** against controlled mock MLX. Tests cover login, source attachment and removal, response streaming, syntax highlighting, clipboard contents, reopening history after refresh, confirmed deletion, mobile navigation, no horizontal viewport overflow, and stopping a response. Desktop test observed no browser runtime errors.
- `npm audit` and production dependency audit: **0 known vulnerabilities** at validation time. This is not a security audit.
- Code formatted with Prettier; dependency versions are pinned in project files and the lockfile (repository changes remain uncommitted).

## Reference-driven revision checks

- Rebuilt and redeployed the dark interface after inspecting the accessible reference.
- `npm run build` passed; all **11 unit/API tests** and **3 browser scenarios** passed after the visual changes.
- Added browser coverage proving that the composer model picker changes models without submitting an unsent draft, and that the popup stays in the viewport.
- Inspected the 1190×806 desktop screenshot against the supplied reference and the 390×844 mobile screenshot for layout. Mobile navigation is hidden and non-focusable when closed.
- OrbStack container recreated successfully and reports healthy. Backend/MLX configuration and saved chats were retained.

## Actual deployment checks passed

- Built `fios:0.1.0` using native ARM64 Node 24.15.0; `docker compose up -d --wait` reports healthy.
- Live production browser login, model-picker rendering and empty-state UI passed without browser runtime errors.
- Bound exclusively to `127.0.0.1:3000`. Service runs as UID 1000, with read-only root, no capabilities, no-new-privileges, bounded CPU/RAM, and named data volume.
- Authenticated model discovery through the Fios API reached the Mini gateway at `host.docker.internal:11234/v1` and returned seven chat-capable entries from the Mini and both Studios. Non-chat media entries are filtered out.
- `node scripts/check.mjs 'mlx-community/gemma-4-e4b-it-4bit'` passed a **real authenticated attachment + streaming inference** test. The temporary text attachment specified `workspace_name = "Fios connected"`; the actual model streamed `Fios connected`. The script deleted the temporary chat afterward. This loaded only the existing small Mini model; no large Studio model was loaded for this test.
- A temporary chat survived **actual container force-recreation** in the named volume and was then deleted successfully.
- Text PDF extraction was separately exercised **inside the production Linux container**, using a generated one-page fixture and the isolated PDF worker.
- MLX-Serve, its model configuration, and the RDMA cluster were not modified. Open WebUI was not reintroduced.

## Remaining acceptance / limitations

- The replacement reference screenshot (`Screenshot 2026-10-23 at 9.15.39 PM.png`) was successfully opened and inspected. The rejected light design was replaced with a reference-driven charcoal layout, compact session sidebar, centered greeting/wordmark and composer, action pills, composer model selector, and circular blue send control. Desktop screenshots are generated at the reference's 1190×806 viewport for direct comparison. User approval is still pending; this does not claim pixel-perfect identity or copy unrelated media/agent features.
- Real image comprehension, model-specific behavior on large Studio models, distributed RDMA execution, long-context performance, concurrent users, backup restore and disaster recovery are not claimed as tested.
- Syntax formatting depends on Markdown/fenced code emitted by the model. The system prompt requests language-tagged code fences; Fios does not guess where arbitrary unmarked prose should become executable code.
- No OCR, arbitrary binary/office-document extraction, agent execution, tools, LAN exposure, TLS or multi-user permissions are enabled.
- Browser tests use mock inference, while the separate real smoke test exercises the complete authenticated Fios backend/gateway path. These are distinct checks.

## Artifacts

- `test-results/fios-desktop.png`
- `test-results/fios-conversation.png`
- `test-results/fios-mobile.png`

Screenshots and browser test artifacts are local and Git-ignored; rerun browser tests to regenerate them.
