# Platform observability

The Studio manager uses the official OpenTelemetry Swift SDK, pinned to2.4.2 in `platform/studio/Package.swift` and `Package.resolved`. This follows the operator’s2026-10-31 request to use OTel where possible. It deliberately adds that dependency to the original dependency-free package plan; StudioCore and its local runner remain independent of the SDK, and007 Python locks are unchanged.

`StudioObservability` implements the core `PlatformTelemetry` interface. The SwiftPM manager passes this adapter into its existing audit and resource sampling paths. Aggregate status reports `observability.instrumentation: opentelemetry-swift`; this identifies instrumentation, not exporter connectivity. Direct Core-only development fixtures default to a no-op adapter.

The SDK emits structured logs for the six fixed operational event names and a cumulative `fios.platform.events` counter with the fixed `fios.event` label. Existing durable local audit records remain unchanged. Gauges use existing resource samples: `fios.platform.host.cpu.utilization` (fraction, unit1), host physical/available memory, disk free space and VM available memory (bytes, unitBy), plus `fios.platform.resource.sample.time` (original Unix seconds). Unknown or expired resource values are omitted; samples do not gain authority or freshness by entering telemetry. Resource attributes are only `service.name=fios-studio-manager` and `service.namespace=fios`. No prompts, generated text, model identifiers or job content are added.

Additional SDK gauges cover the readings already collected by the manager: `fios.platform.gpu.utilization` (fraction, unit1), GPU memory `.in_use`/`.allocated` (unitBy), and `fios.platform.gpu.sample.time` (original Unix seconds). GPU values use their own collection time, independently of the host/VM sample. `fios.platform.host.power.low` records1/0 only when low-power mode is known. Memory pressure (`fios.platform.host.memory.pressure`) and thermal state (`fios.platform.host.thermal.state`) are one-valued gauges labelled with the fixed `fios.state` enum value; unknown states publish no point. None of these observations establishes GPU idle or allocatable model memory.

Workload gauges are sampled on the same existing2s manager cycle from its own journal and cached artifact statistics:

| Metric | Unit | Meaning |
| --- | --- | --- |
| `fios.platform.jobs` | `{job}` | Retained local journal records by fixed `fios.job.state`; includes retained removed-job tombstones |
| `fios.platform.inference.unresolved_records` | `{record}` | All retained unresolved inference records |
| `fios.platform.inference.uncertain_records` | `{record}` | The uncertain subset of those records |
| `fios.platform.workers.reservations` | `{reservation}` | Unreaped worker reservations, including pending startup |
| `fios.platform.artifacts.size` | `By` | Retained artifact storage bytes |
| `fios.platform.artifacts.jobs` | `{job}` | Jobs represented in cached artifact storage statistics |
| `fios.platform.sandbox.cleanup.pending` | `{sandbox}` | Owned sandboxes currently awaiting runtime cleanup |
| `fios.platform.sandbox.cleanup.wait` | `s` | Oldest currently observed cleanup wait; omitted when its clock is unknown |
| `fios.platform.workload.sample.time` | `s` | Original aggregate collection time |

Cleanup gauges share the controller’s current operator-status observation. Recovery returns pending/wait to zero without clearing independent inference records. Wait age includes observed runtime outages and is not an availability-relative SLA verdict.

A failed journal query omits the entire workload sample; no additional SQLite instance is opened. Missing or expired samples produce no points. Known zero counts remain zero. These gauges describe retained local records, not live worker/model counts or native completion. They never release a reservation or alter independent inference uncertainty. No job/model/owner IDs or content are included.

No Collector, Prometheus, exporter transport, listener or background export timer is configured or deployed. Metrics are available as actual SDK `MetricData` through `collectMetrics()`; the initializer accepts a standard SDK `MetricReader` and `LogRecordProcessor` implementations for later backend integration. Without such configuration, OTel logs are not delivered externally and cumulative metrics remain in process. The existing audit file supplies durable local event history. Restart resets in-process metrics. This is instrumentation readiness, not end-to-end observability delivery.

A later, separately scoped deployment can select an OTel Collector and Prometheus-compatible backend. It must explicitly configure export, collection and retention; this change does not promise backend availability or create new services. No telemetry is used for service actuation, admission or native idle decisions.

Run the focused SDK tests with a full Xcode toolchain (the local standalone Command Line Tools lack XCTest):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path platform/studio --filter StudioOpenTelemetryTests
```

An ordinary end-to-end SDK check runs the actual manager and CLI against private state:

```sh
node scripts/check-platform-observability.mjs --isolated
```

It copies the actual package sources/dependency pins into a private fixture build and adds only a test capture wrapper. The real SDK captures startup, operator service-intent change and shutdown, resource gauges and empty journal aggregates. Its JSON capture is a test assertion format, not an exporter or product protocol. IP networking is denied during fixture execution; no backend, model, session or native service operation is configured. Private build/state/capture data are retained for review. CI runs the same finite check.

References: [Swift instrumentation](https://opentelemetry.io/docs/languages/swift/), [official Swift core SDK](https://github.com/open-telemetry/opentelemetry-swift-core), [OTLP specification](https://opentelemetry.io/docs/specs/otlp/). No custom wire protocol is introduced.
