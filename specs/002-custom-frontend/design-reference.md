# Reference-driven visual revision

Reference inspected successfully: `/Users/mcteer/Desktop/Screenshot 2026-10-23 at 9.15.39 PM.png`.

The prior light/sage design is rejected. Match the supplied MLX-Serve screenshot's visual language, not its unrelated feature inventory:

- Near-black charcoal main canvas (#222522), slightly lighter inset sidebar (#2e312e), off-white text, fine dark borders.
- Narrow sidebar with compact navigation and session rows, restrained typography, no large decorative branding or boxed new-chat CTA.
- Centered Fios wordmark near the top, large uninterrupted negative space.
- Centered sans-serif “How can I help you today?” heading, compact horizontal action pills beneath it, wide dark rounded composer directly below those pills around the middle of the empty-state canvas.
- Attachment icon and model-selection pill inside composer, blue circular send button. Model menu opens upward, away from the viewport edge. Per subsequent user feedback, omit the redundant Models sidebar link. The requested 192px composer was subsequently rejected as too large; restore its original 96px default height on desktop and mobile, retaining auto-growth for longer input.
- Existing conversation layout remains readable and scrollable with composer anchored at the bottom after a conversation begins.
- Preserve real chat/history/delete/attachments/Markdown/copy/streaming/auth behavior. Do not add fake media, task or agent controls simply because they appear in the reference.
- Maintain a usable mobile drawer, visible keyboard focus, and reduced-motion handling.

Acceptance: compare generated desktop screenshot at the reference's 1190×806 viewport; run existing desktop/mobile browser and API tests after changing the UI. User approval remains necessary; do not claim pixel-perfect identity or reproduce macOS window chrome in a web page.
