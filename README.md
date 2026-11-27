# fios

A local workbench for a Mac-based model cluster. The first slice runs a read-only cluster dashboard in OrbStack and collects real telemetry with a native macOS agent.

## Run on the Mini

Use Python 3.11 or newer, Make, and OrbStack in Docker mode. The app uses the Python standard library. The first container build pulls the pinned official Python image.

Start the native sampler for this login session and the detached OrbStack service.

```sh
make dashboard
```

Open [the local dashboard](http://127.0.0.1:8741/). Select **Refresh status** to read the latest observations. The Mini publishes a sample every five seconds. A sample becomes stale after thirty seconds. The Studio cards show **Telemetry unavailable** until the native enrollment service is running. The two Studio names are inventory aliases.

The process binds to IPv4 loopback inside OrbStack host networking. This bootstrap assumes one trusted local operator and trusted processes on the Mini. Keep public ingress, port forwarding and reverse proxies off. The local admin can read inventory and manage worker trust through the native CLI.

In OrbStack, open the `fios` Compose project and select `fios-core-1`. Use `make dashboard-stop` to stop the sampler and remove the service. Observations remain under the Git-ignored `.fios/observations/` directory. The UI mounts only that directory, read-only. The supplied `.env.local` is excluded from Git and the Docker build. These commands do not load it.

## Source layout

| Directory | Owns |
| --- | --- |
| [src/frontend](src/frontend/) | Server-rendered dashboard, HTML template and stylesheet |
| [src/backend](src/backend/) | HTTP routes, local operator checks, inventory contract and native Mac telemetry service |
| [src/agent](src/agent/) | AI harness configuration and authoring presets. Model and tool execution are covered in the roadmap. |

The backend serves the UI and its API from one origin. Its container copies only the backend server and frontend. The native telemetry process runs on macOS. Tests and development tooling live outside the application source. [Python Packaging User Guide on source layouts](https://packaging.python.org/en/latest/discussions/src-layout-vs-flat-layout/)

## Development

GitHub Spec Kit is initialized for Codex. On an Apple Silicon development Mac with Python 3.15, set up the locked developer tooling and verify the workspace.

```sh
make spec-tools
make check
```

`make check` checks the installed integration and feature prerequisites, runs the Python tests and validates Compose. Use `make test` for the standalone application tests. To invoke Spec Kit skills in Codex, start it in the repository after activating `.venv`. See the [Spec Kit setup](.specify/README.md) for commands and feature selection.

For a native-only UI check, run `make sample` followed by `PYTHONPATH=src python3 -B -m backend.core` while the container is stopped. Both servers use the same loopback port. `GET /healthz` measures the UI process. `GET /api/v1/cluster` returns versioned observations and freshness.

## Enroll Studio workers

Run `make enrollment-test` for disposable SQLite and mutual TLS tests. Run `make enrollment-acceptance` on `fios-core` with OrbStack and the operator's macOS login session running. The acceptance runner uses a separate Compose project and disposable launchd jobs, and checks the existing preview after teardown. See the [qualification and rollout guide](specs/002-studio-enrollment/quickstart.md).

Before live rollout, approve the worker-to-slot mapping, the management route and the core SAN, and verify the approved root fingerprint independently. Use a dedicated offline CA. Generate the leaf key and CSR on each consuming host under the corresponding unprivileged service identity. Sign with the approved certificate profile, ignoring CSR-requested extensions. Configure `CA:FALSE`, `digitalSignature`, and an explicit EKU of `clientAuth` for workers or `serverAuth` for the core. The worker leaf has a single DNS SAN equal to its approved machine name. The core leaf has a DNS or IP SAN matching the worker's configured core name. Use 30-day leaves and rotate before expiry. Distribute the public root and signed leaf. Keep each key on its own host, mode 0600 in a service-owned mode-0700 directory. Keep the CA signing key offline. OpenSSL 3 or 4 is supported for issuance and public leaf verification.

On the Mini, run the following once as the trusted local operator, with `PYTHONPATH` pointing to the qualified native source. Create the private parent beforehand. The state directory itself must be new.

```sh
python3 -B -m backend.enroll init --state-dir '/Library/Application Support/fios/enrollment/state'
```

Render the [launchd templates](ops/launchd/) for each approved host using absolute paths and the approved management address. Set `UserName` to the local operator on the Mini and the designated unprivileged service identity on each Studio. Install the qualified source and each rendered plist with administrator-controlled ownership. Use `plutil -lint` before loading an authorized system job. The worker sends outbound reports only. The native service accepts reports on the configured management IP and serves the container's read-only snapshot over loopback. The dashboard continues to mount only the Mini's existing observation directory.

Use the local operator socket to approve, inspect, rotate or revoke. Use the current public leaf fingerprint with `--expected` for rotation, revocation and re-enrollment. For example, on the Mini:

```sh
python3 -B -m backend.enroll --socket '/Library/Application Support/fios/enrollment/state/operator.sock' \
  approve studio-a --machine edge-a --leaf /path/to/edge-a-public-leaf.pem
```

For planned root rotation, stage the verified new public root beside the old on both sides, restart with the dual bundle, replace the core leaf and rotate one worker at a time. After confirming both workers report with the new chain, remove the old root everywhere and restart the services. For a compromised root, stop the listener, remove the compromised root on all endpoints, issue new leaves offline and reapprove them via the independent provisioning channel. For a failed Studio rollout, revoke the affected binding, unload that worker's system job and remove its staged artifact. Preserve the verified current ledger and its retired pins. The other worker can keep reporting.

## Development record

- [Feature specification](specs/001-platform-foundation/spec.md) defines the initial delivery and the product journeys.
- [Development plan and threat review](specs/001-platform-foundation/plan.md) covers agents, routing, storage, admin, models, sandboxes and public identity.
- [Research and qualification criteria](specs/001-platform-foundation/research.md) compare model sizes and licenses, single- and multi-host runtimes, isolation and search providers.
- [Tasks and verified handoff](specs/001-platform-foundation/tasks.md) track implementation and the next executable slice.
- [Creative presets](src/agent/authoring.toml) define initial campaign, one-shot, session and art direction for future Projects.
- [Spec Kit workflow](.specify/README.md) describes the installed Codex skills, tooling and workflow.
