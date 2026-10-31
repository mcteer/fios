# Platform observability

The Studio manager uses the official OpenTelemetry Swift SDK, pinned to2.4.2 in `platform/studio/Package.swift` and `Package.resolved`. This follows the operator’s2026-10-31 request to use OTel where possible. It deliberately adds that dependency to the original dependency-free package plan; StudioCore and its local runner remain independent of the SDK, and007 Python locks are unchanged.

`StudioObservability` implements the core `PlatformTelemetry` interface. The SwiftPM manager passes this adapter into its existing audit and resource sampling paths. Aggregate status reports `observability.instrumentation: opentelemetry-swift`; this identifies instrumentation, not exporter connectivity. Direct Core-only development fixtures default to a no-op adapter.

The SDK emits structured logs for the six fixed operational event names and a cumulative `fios.platform.events` counter with the fixed `fios.event` label. Existing durable local audit records remain unchanged. Gauges use existing resource samples: `fios.platform.host.cpu.utilization` (fraction, unit1), host physical/available memory, disk free space and VM available memory (bytes, unitBy), plus `fios.platform.resource.sample.time` (original Unix seconds). `fios.platform.vm.sample.time` reports the VM reading’s separate original collection time in seconds; it is omitted alongside unavailable or expired VM memory, even when the host sample remains fresh. Unknown or expired resource values are omitted; samples do not gain authority or freshness by entering telemetry. Resource attributes are `service.name=fios-studio-manager`, `service.namespace=fios`, `host.name` from the local OS-reported host name, and a random UUID `service.instance.id` created once per SDK instance. The product constructs one SDK instance per manager run, shared by metrics and logs. The host label is observational and is not normalized into a reviewed Studio identity or used for admission; the telemetry UUID is not a native/process identity proof. No prompts, generated text, model identifiers or job content are added.

Additional SDK gauges cover the readings already collected by the manager: `fios.platform.gpu.utilization` (fraction, unit1), GPU memory `.in_use`/`.allocated` (unitBy), and `fios.platform.gpu.sample.time` (original Unix seconds). GPU values use their own collection time, independently of the host/VM sample. `fios.platform.host.power.low` records1/0 only when low-power mode is known. Memory pressure (`fios.platform.host.memory.pressure`) and thermal state (`fios.platform.host.thermal.state`) are one-valued gauges labelled with the fixed `fios.state` enum value; unknown states publish no point. None of these observations establishes GPU idle or allocatable model memory.

The same2s manager cycle emits `fios.platform.service.state` (unit1): one current point per fixed `fios.service` (`mlx` or `orbstack`), labelled by the existing `fios.service.desired` and `fios.service.observed` enum values. Desired state comes from the manager journal; observed state uses the same source-age/session/pending classification as operator status. Missing or stale observations therefore remain `unknown`, even when desired intent changes. The metric is a status sample, not proof of native state or actuation. Expired aggregate samples are omitted. Failed journal reads clear the service sample rather than retaining old states; no extra connection, service probe or listener is created.

Workload gauges are sampled on the same existing2s manager cycle from its own journal and cached artifact statistics:

| Metric | Unit | Meaning |
| --- | --- | --- |
| `fios.platform.jobs` | `{job}` | Retained local journal records by fixed `fios.job.state`; includes retained removed-job tombstones |
| `fios.platform.inference.unresolved_records` | `{record}` | All retained unresolved inference records |
| `fios.platform.inference.uncertain_records` | `{record}` | The uncertain subset of those records |
| `fios.platform.workers.reservations` | `{reservation}` | Unreaped worker reservations, including pending startup |
| `fios.platform.artifacts.size` | `By` | Retained artifact storage bytes |
| `fios.platform.artifacts.jobs` | `{job}` | Jobs represented in cached artifact storage statistics |
| `fios.platform.sandbox.memory.reserved` | `By` | Sum of declared memory limits for sandbox records without confirmed runtime removal |
| `fios.platform.sandbox.cpu.reserved` | `{cpu}` | Sum of declared CPU reservations for those records |
| `fios.platform.sandbox.workspace.capacity` | `By` | Sum of selected workspace tmpfs capacities for those records |
| `fios.platform.sandbox.cleanup.pending` | `{sandbox}` | Owned sandboxes currently awaiting runtime cleanup |
| `fios.platform.sandbox.cleanup.wait` | `s` | Oldest currently observed cleanup wait; omitted when its clock is unknown |
| `fios.platform.workload.sample.time` | `s` | Original aggregate collection time |

Sandbox reservation totals stay counted during cancellation/reconciliation and disappear only when each record has confirmed runtime removal. They describe declared local reservations, not measured consumption, allocatable VM memory or a native release. Workspace capacity is inside the container memory limit; adding it to memory reservation would double-count that capacity.

Cleanup gauges share the controller’s current operator-status observation. Recovery returns pending/wait to zero without clearing independent inference records. Wait age includes observed runtime outages and is not an availability-relative SLA verdict.

A failed journal query omits the entire workload sample; no additional SQLite instance is opened. Missing or expired samples produce no points. Known zero counts remain zero. These gauges describe retained local records, not live worker/model counts or native completion. They never release a reservation or alter independent inference uncertainty. No job/model/owner IDs or content are included.

Native-control diagnostics use the existing accepted reply cache and the same manager cycle. Gauges under `fios.platform.native.ingress.` expose only partial request-tracker metadata:

| Metric suffix | Unit | Meaning |
| --- | --- | --- |
| `owners`, `unparsed`, `preparing`, `active`, `responding` | `{owner}` | Tracked ownership records/phases, not GPU execution or concurrent model requests |
| `model_identities` | `{identity}` | Count of model identities represented by tracked ownership, not resident models; identifiers are never emitted |
| `closed` | `1` | The source tracker’s ingress fence flag, not complete native admission authority |
| `tracker_uncertain` | `1` | That tracker’s uncertainty flag, independent of retained inference-record uncertainty |
| `receipt.time` | `s` | Original accepted reply receipt time |
| `source.time` | `s` | Original native capture time, omitted when absent, including legacy replies |

Every point has fixed `fios.scope=native_ingress_tracker` and `fios.sample.clock=source_and_receipt|receipt_only`. Source and receipt ages remain independent; either expired known clock omits the sample. Missing/unconfigured/unavailable diagnostics omit points rather than inventing zero. These observations never become a `NativeSnapshot`, clear independent uncertainty or authorize model/service work. A zero count is simply a fresh diagnostic count in this partial source scope. The SDK does not poll native sources. An explicitly configured manager client refreshes its diagnostic cache with read-only observations on the existing2s controller cycle, sharing the single native-control slot. Periodic reads never reconcile durable intent or issue pause/resume; explicit operator requests retain precedence. Unconfigured product managers make no such requests.

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

References: [Swift instrumentation](https://opentelemetry.io/docs/languages/swift/), [official Swift core SDK](https://github.com/open-telemetry/opentelemetry-swift-core), [OTLP specification](https://opentelemetry.io/docs/specs/otlp/), [service instance conventions](https://opentelemetry.io/docs/specs/semconv/resource/service/) and [host resource conventions](https://opentelemetry.io/docs/specs/semconv/resource/host/). No custom wire protocol is introduced.
