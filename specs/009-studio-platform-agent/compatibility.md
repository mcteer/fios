# Installed Studio compatibility — 2026-10-26

## Authorized read-only inventory

After the user reaffirmed proceeding in response to the explicit narrow amendment/read-only SSH proposal, used existing SSH authentication with `BatchMode=yes`, `StrictHostKeyChecking=yes`,5s connection timeout. No host-key enrollment, privilege escalation, process changes, service configuration or model workload.

| Observation | Edge A | Edge B |
| --- | --- | --- |
| Confirmed hostname | fios-edge-a | fios-edge-b |
| macOS |27.0.1 |27.0.1 |
| Architecture |arm64 |arm64 |
| MLX app / serving API version |26.10.3 /26.10.3 |26.10.3 /26.10.3 |
| MLX code identifier / team |com.dalcu.mlx-core / S77TW432YG |com.dalcu.mlx-core / S77TW432YG |
| MLX app executable SHA256 |26a368e8dc05c963ff8521d5ddef36a9103214387f4857ca436dba0e1fa6e3bf |26a368e8dc05c963ff8521d5ddef36a9103214387f4857ca436dba0e1fa6e3bf |
| OrbStack app version |2.2.5 |2.2.5 |
| OrbStack app executable SHA256 |48e096f309541c42ff9aa029dd1afae06bcae2875aa4a6c1ca273f79d44d9738 |48e096f309541c42ff9aa029dd1afae06bcae2875aa4a6c1ca273f79d44d9738 |
| Native-local `/health` |HTTP200 |HTTP200 |
| Native-local `/metrics.json` |HTTP200 |HTTP200 |

Local HTTP reads were fixed loopback URLs, no proxy, timeout2s and1MiB maximum response. Printed only status/version/key names, never metrics sessions, prompts, response text, credentials, process argv or native log bodies. App executable hashes do not attest the independently running native child/config/source.

## GPU and configured-VM-cap follow-up

Within the same authorized read-only SSH scope, queried only AGXAccelerator numeric PerformanceStatistics and, after `orbctl status` reported running, `orbctl config get memory_mib`. Fixed native commands, bounded capture, strict host keys and no privilege escalation. Only selected numeric facts were emitted; no raw registry/session/configuration/log bodies or credentials were recorded.

| Observation | Edge A | Edge B |
| --- | --- | --- |
| Readable Device Utilization % counters |1 |1 |
| Instantaneous GPU percentage |0.0 |0.0 |
| Configured OrbStack cap, MiB |16384 |16384 |
| Running Linux machines |0 |0 |
| Native orbctl/scli SHA256 |`b2793e99e3f452b86233d59cd5e503e069821224c022628f52521dc5b4bcab8a` |same |

The native orbctl alias resolves to `/Applications/OrbStack.app/Contents/MacOS/scli.app/Contents/MacOS/scli`; this is separate from the Docker multicall client. Subsequent fixed read-only hash/list queries recorded only its digest and the machine count, never machine names or raw inventory bodies. The development manifest now pins `orbctl_cli_sha256` separately from `docker_cli_sha256`; neither inventory pin grants enrollment.

This establishes actual target GPU-counter accessibility and a16GiB configured cap on both Studios. Zero here is an observed instantaneous counter, **not** all-client idle proof. The configured cap is **not** remaining usable VM capacity. No inference, remote containers, application restart, settings change or installation occurred. Fixed same-kernel memory readers and capacity-policy tests are described in telemetry-research.md; their production enrollment and continuous whole-VM coverage remain pending.

## Gate G2: NOT SATISFIED

Both local metrics responses expose `counters`, `decode_serial`, `gauges`, `histograms`, `sessions`. Gauge keys include `process_start_time_seconds`, `requests_prefilling`, `requests_running`, `requests_waiting` and resource/token counters. No raw session content was logged. Loopback metric availability resolves access feasibility; it does **not** establish coherent per-request ownership or all-client idle semantics.

The version-aligned public source already inspected in research shows running/waiting sampled from scheduler counters, while model acquisition/preloading occurs elsewhere. The existing public metrics have not demonstrated coherent ingress→preparation→queue→compute→response-delivery ownership. A resident-only interface is not a user requirement and is no longer an acceptance prerequisite. Searches of the reviewed server source did not identify such a contract; absence of a search hit is not claimed as exhaustive proof that no internal facility exists. None of the documented/observed capabilities currently proves the required behavior.

Therefore T002 remains incomplete for native activation/acceptance. The mistaken dependency blocking all independent implementation has been removed; local implementation and mock testing proceed. Do not invent a green gate from zero counters or implement managed-only accounting and claim all-client correctness. No unsafe experiment was run to test this hypothesis.

## Required integration decision

A versioned native observation/admission integration is required if no supported existing API can provide the activity contract. Source-only integration/testing against pinned26.10.3 is already authorized (user reaffirmed2026-10-27); do not request that approval again. See `native-integration.md` for implemented development hooks and remaining technical acceptance gaps. It needs all-client ingress/preparation/queue/compute/response ownership, coherent model/instance/sequence, native non-preemption while allowing normal on-demand replacement of an idle resident model. This is a serving-software change, not a Docker/SSH access workaround. Do not patch/restart the installed native application, inject instrumentation, open metrics remotely or install a proxy pretending bypass clients cannot exist.

## Follow-up read-only child/runtime inventory

Using the same bounded strict-host-key SSH scope, queried only the11234 listener PID/executable path, executable hashes and filtered local Docker info. No process argv, environment, container configuration, raw sessions, model call or service change.

| Observation | Edge A | Edge B |
| --- | --- | --- |
| Listener executable | `/Applications/MLX-Serve.app/Contents/MacOS/mlx-serve` | same |
| Observed listener PID (ephemeral, not identity proof) |40245 |2737 |
| Listener executable SHA256 | `4c2416121c33011bddd0002f4179b7b0b1a273136a6f2041286c80285d422a62` | same |
| Docker multicall CLI SHA256 | `927c58aed356a37f08f2586a90df4c6d8c5e890060de95ac3d11301d03959463` | same |
| Explicit private Docker socket | `/Users/mcteer/.orbstack/run/docker.sock` | same |
| Docker server / OS / architecture |29.8.2 / linux / aarch64 |same |
| Reported runtime CPUs |32 |28 |
| Reported runtime memory bytes |16814260224 |16814907392 |

CLI is `/Applications/OrbStack.app/Contents/MacOS/xbin/docker-tools`, invoked through its fixed `docker` basename. Read-only daemon commands used explicit `--host unix://...` and `DOCKER_CONFIG=/var/empty`. These observations identify the actual listener file and runtime envelope; they do **not** prove source equivalence, all-client lifecycle coverage, configured-limit enforcement, PID start identity or caps surviving reboot. No runtime setting was altered or increased. Native G2 and live overlap/race/slow-reader acceptance remain pending; independent service/package implementation/testing continues.

### Native capture versus request sequence (source checkpoint)

The unknown-only source diagnostic now exposes `sample_sequence` independently from request-allocation `sequence`. Both are process-instance-bound. Sampling advances its own JSON-safe counter under the ownership mutex; request/admission tickets retain their original allocation/maintenance semantics. Exhaustion saturates and fences uncertainty. A future normalized adapter must use the capture counter for native observation replay checks, not mistake allocation stability for a repeated sample or refresh an old sample by assigning a manager sequence. Native capture timestamps, authenticated process/profile binding, full source/ABI/modalities/device coverage and native atomic admission remain separate unfinished integration; this diagnostic still reports unknown and cannot authorize model work or lifecycle changes.
