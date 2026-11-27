# AI agent harness

This component owns the model-facing instructions and configuration for chat, code review and campaign authoring. Its current asset is the [versioned authoring profile](authoring.toml), which defines narration, campaign and session modes, and image presets. Model dispatch and tool execution are planned work.

The backend owns identity, authorization, job admission and the native host telemetry service. Future model-proposed actions go through those backend checks. The developer's Spec Kit skills live in the repository's `.agents/skills/` directory.
