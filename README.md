# fios

A local workbench for a Mac-based model cluster. The first slice runs a read-only cluster dashboard in OrbStack and collects real telemetry with a native macOS agent.

## Run on the Mini

Use Python 3.11 or newer, Make, and OrbStack in Docker mode. The app uses the Python standard library. The first container build pulls the pinned official Python image.

Start the native sampler for this login session and the detached OrbStack service.

```sh
make dashboard
```

Open [the local dashboard](http://127.0.0.1:8741/). Select **Refresh status** to read the latest observations. The Mini publishes a sample every five seconds. A sample becomes stale after thirty seconds. The two Studio names are inventory aliases. They show **Awaiting sample** until observations are available.

The process binds to IPv4 loopback inside OrbStack host networking. This bootstrap assumes one trusted local operator and trusted processes on the Mini. Keep public ingress, port forwarding and reverse proxies off. The local admin can read inventory. A future authenticated agent channel will carry administrative operations.

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

On a Studio, run `make agent NODE=studio-a` or `make agent NODE=studio-b` for a foreground sampler. It writes locally without listening on the network. Authenticated remote collection is the next development slice.

## Development record

- [Feature specification](specs/001-platform-foundation/spec.md) defines the initial delivery and the product journeys.
- [Development plan and threat review](specs/001-platform-foundation/plan.md) covers agents, routing, storage, admin, models, sandboxes and public identity.
- [Research and qualification criteria](specs/001-platform-foundation/research.md) compare model sizes and licenses, single- and multi-host runtimes, isolation and search providers.
- [Tasks and verified handoff](specs/001-platform-foundation/tasks.md) track implementation and the next executable slice.
- [Creative presets](src/agent/authoring.toml) define initial campaign, one-shot, session and art direction for future Projects.
- [Spec Kit workflow](.specify/README.md) describes the installed Codex skills, tooling and workflow.
