# Validation

- `npm test`: all 11 tests passed, including extended API integration assertions for immediate rejection of removed models within the former cache window, no-store catalog responses, and additions/removals advertised by mock MLX.
- `npm run build`: passed.
- `npx playwright test`: all 5 scenarios passed. Two new scenarios control browser time and catalog responses to verify automatic addition/removal, valid-selection preservation, removed-selection/localStorage clearing, empty lists, send blocking, outage/recovery, draft preservation, refresh on focus/visibility/reconnect/picker open, and suspension of polling while hidden. Existing chat/attachment/copy/streaming/delete/mobile regressions still pass.
- Rebuilt and recreated production OrbStack container; healthy.
- Real authenticated `node scripts/check.mjs` discovery passed against native Mini MLX-Serve (4 advertised chat models at validation time). No inference requests or actual model additions/removals were performed for this change; catalog mutations and outage behavior were tested using controlled fixtures rather than changing cluster configuration.
- Also restored the composer's original 96px default height on desktop/mobile at the user's request; the redundant sidebar Models link remains removed. Browser regressions assert the restored height.
