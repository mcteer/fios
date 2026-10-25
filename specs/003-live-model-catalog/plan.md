# Plan

Extract model discovery into a React hook with 30-second visible-page polling, focus/visibility/online listeners, abort/timeout handling, single-flight requests, and unmount cleanup. Opening the picker triggers a fresh read. Keep the backend's existing no-store `/api/models` route (already forces upstream discovery); force fresh validation before submitting inference as well.

Reconcile selection independently of chat history. Preserve valid choices, clear removed ones, and only auto-select on first successful discovery if no prior selection exists. Disable sends/options on discovery failure, but keep the last known catalog for context until recovery.

Browser tests intercept catalog responses, control browser time, and assert addition/removal, empty state, focus refresh, selected-model stability, failure/recovery and draft preservation without touching actual model files or cluster configuration.
