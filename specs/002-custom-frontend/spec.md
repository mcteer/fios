# 002 — Professional Fios chat

Status: Implemented and deployed; automated/live checks passed; user visual approval pending

## Requirements

Build a simple, professional ChatGPT/Claude-style web UI, not Open WebUI. Provide persistent conversations with deletion, attachments for context, correctly formatted Markdown and fenced code, text/code copy icons, streamed responses, and model selection from local MLX-Serve. Run in OrbStack as a container. Leave inference and RDMA configuration untouched.

## User stories / acceptance

- US1: Start a conversation, select a chat-capable model, send a message, see tokens as they arrive, and stop generation. Errors and interrupted responses are explicit and usable.
- US2: Refresh or recreate the container and reopen saved messages. Delete a conversation with confirmation; deletion removes its messages and associated attachment data.
- US3: Attach text/source files, text-extractable PDFs, or images. Show filenames and sizes before sending; allow removal. Reject unsupported/oversized/empty documents clearly. Include accepted attachments in subsequent model context. Images require an advertised vision-capable model. Scanned PDFs/OCR and arbitrary binaries are out of scope.
- US4: Render Markdown, tables, lists, links and syntax-highlighted fenced code without executing HTML. Copy message text or individual code using accessible icon buttons and visible confirmation.
- US5: Desktop has a refined sidebar, conversation canvas, clear hierarchy, understated colors, and an anchored composer. Mobile sidebar is dismissible; keyboard navigation and reduced-motion preferences are respected.
- US6: Authenticate with a local access password; no public signup. Persist data in a named volume; bind localhost only. No execution tools or Docker socket access.

## Explicit first-version boundaries

Single-user local application, not a multi-tenant service. Attachment limits: 10 MiB/file, 5 files/request, 20 MiB total; extracted text capped per file and aggregate history context bounded. No OCR, office document parsing, web browsing, agents, or inference settings UI. No automatic large-model loading: user selects the target. Use exact gateway model IDs. UI health and upstream connectivity are distinct.
