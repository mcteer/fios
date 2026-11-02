# MLX first-uncertainty diagnostic sites

The initial diagnostic-only cumulative candidate preserves existing uncertainty and epoch behavior. The subsequent capture budget refinement is described below. A site is metadata, not native terminal/admission authority;0 means no first failure recorded. Bind interpretation to this exact patch identity, not another build. Source locations below refer to the original seven-path shared-event candidate before diagnostic insertion.

| Site | Original stream.cpp line | Source statement |
| --- | --- | --- |
| 1 | 63 | `fios_registry.uncertain = true;` |
| 2 | 72 | `fios_registry.uncertain = true;` |
| 3 | 91 | `fios_registry.uncertain = true;` |
| 4 | 103 | `fios_registry.uncertain = true;` |
| 5 | 139 | `fios_registry.uncertain = true;` |
| 6 | 172 | `fios_registry.uncertain = true;` |
| 7 | 196 | `fios_registry.uncertain = true;` |
| 8 | 212 | `fios_registry.uncertain = true;` |
| 9 | 224 | `fios_registry.uncertain = true;` |
| 10 | 236 | `fios_registry.uncertain = true;` |
| 11 | 257 | `fios_registry.uncertain = true;` |
| 12 | 284 | `fios_registry.uncertain = true;` |
| 13 | 293 | `fios_registry.uncertain = true;` |
| 14 | 298 | `if (!fios_registry.metal_pending) {fios_registry.uncertain = true;return;}` |
| 15 | 316 | `fios_registry.uncertain = true;return {};` |
| 16 | 328 | `fios_registry.metal_captures >= fios_limit) {fios_registry.uncertain = true;return {};}` |
| 17 | 340 | `fios_registry.uncertain = true;return;` |
| 18 | 344 | `if (failed) fios_registry.uncertain = true;` |
| 19 | 350 | `if (task->retired &#124;&#124; task->submitted) {fios_registry.uncertain = true;return;}` |
| 20 | 357 | `if (!task->submitted) {fios_registry.uncertain = true;return;}` |
| 21 | 358 | `if (failed) fios_registry.uncertain = true;` |
| 22 | 364 | `if (!task->retired) fios_registry.uncertain = true;` |
| 23 | 372 | `fios_bump();fios_registry.uncertain = true;` |
| 24 | 387 | `fios_registry.uncertain = true;return 0;` |

The refined candidate separates the original combined site16:16 is a retired buffer,25 is a submitted buffer,26 is the per-buffer capture limit and27 is the global capture limit. The historical diagnostic run reported the combined site16; it does not establish which predicate fired. Site15 remains the separate ownership/pending-buffer check.

## Capture budget refinement

The refined diagnostic SDK (patch071061581d068db45245a88fee0fb52786a4f90649900185fb187f4b8841a09e) identifies global capture exhaustion at site27 during actual Gemma execution; this is independent of the stream/pending-buffer bound. Its receipt f31b886b1395a4be9db7c084f8db0d7607fbff967269b678959fb6f19fba44bc passes the existing hardware controls. The later cumulative candidate separates stream/buffer slots (256), per-buffer capture records (4096) and global capture records (16384). These are finite bookkeeping limits, not GPU memory quotas or admission authority. They bound record count, not bytes retained by callback payloads; the private model runner retains its separate process observations and abort threshold. Exhaustion remains sticky and retains all outstanding records; it does not refund resources. Exact metadata boundary fixtures deliberately exit without claiming physical completion. The candidate now includes this functional bound change in addition to first-site diagnostics; it is not diagnostic-only.
