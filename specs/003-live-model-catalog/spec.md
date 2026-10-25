# 003 — Live model catalog

Automatically reflect MLX-Serve model additions/removals without reloading Fios. Preserve the chat-capability filter and exact peer-qualified IDs.

Acceptance:
- Refresh every 30 seconds while visible, on returning to the tab/window, browser reconnect, and opening the picker; no overlapping requests or loading-label flicker during background updates.
- Keep a valid selection. If it disappears, clear it and require explicit selection rather than silently switching to a potentially large cold model. Empty catalogs disable sending; old conversations still open without resurrecting missing models.
- Transient discovery failures are not treated as an empty catalog. Show an unavailable/retrying status, prevent stale selections from being sent, and recover automatically.
- In-flight replies and saved conversations are unaffected. Catalog refreshes never initiate inference.
