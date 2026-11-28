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

## Qualify the job scheduler

Run `make scheduling-test` for deterministic ledger and scheduler tests. On `fios-core`, run `make scheduling-acceptance` for the native operator CLI and two synthetic workers over mutual TLS. It uses disposable state and checks the existing preview before and after the run.

Synthetic scheduling requires `--test-loopback --synthetic-scheduling` on `backend.enroll serve` and a private ledger initialized with `backend.enroll job-init --state-dir PATH`. Use the existing `--socket PATH` operator interface. Read `job-context`, then pass its incarnation with the original key and request to `job-submit`. Reuse that complete envelope on retry and stop on `ledger_changed`. The per-operator waiting queue holds 16 jobs. A full queue returns a five-second retry hint.

Use `job-backup --state-dir PATH --target FILE` and `job-restore --state-dir PATH --snapshot FILE` with the native service stopped. Both paths must be private and owned by the operator. Restore rotates the ledger incarnation, quarantines both slots and invalidates snapshot jobs that may have already executed. Resume admission only after each worker authenticates, confirms cleanup and supplies fresh capacity. Review the history before explicitly scheduling replacement work. To disable scheduling, cancel or settle active jobs, confirm cleanup, and restart the enrollment service without the synthetic scheduling flag. [Spec 3 interfaces](specs/003-job-ledger-scheduling/contracts/dispatch.md)

## Service layout

| Service | Deployment | Owns |
| --- | --- | --- |
| Browser UI | Independent OrbStack container on fios-core | Chat and dashboard assets, browser checks, and the client for the native chat API |
| Persistence and scheduling | Separate native service on fios-core | Private SQLite job and conversation files, model catalog, and exclusive job leases |
| MLX runtime | Native Apple Silicon macOS process on the serving Mac | Metal and unified-memory inference with verified local weights |
| Management agent | One dedicated OrbStack container on each of fios-core, edge-a, and edge-b | Host telemetry with dependency supervision and management actions tracked in T009 |
| Host supervisor | Native launchd service on each Mac in T009 | Host telemetry, OrbStack outage detection and recovery, and narrow host-local controls |

The opt-in [chat Compose overlay](compose.chat.yaml) mounts the UI-only bridge key and read-only observations. The UI image and container have no model runtime, database files, or host administration socket. The native storage service owns migration and backup. Rebuilding or replacing the UI container leaves the native conversation store in place.

Chat history stays on fios-core until the operator deletes the conversation. `job-backup` copies operational state in `jobs.sqlite`. With the native service stopped, preserve `conversations.sqlite` and its private digest key alongside the ledger snapshot to recover the matching history. Keep that set private and apply your retention policy to copies, since deleting a live conversation cannot erase an earlier offline copy. Restoring the ledger rotates its incarnation, fences executors and clears active model aliases.

The dedicated [management Compose project](compose.management.yaml) currently serves read-only native telemetry at `/v1/host` on loopback port 8745. Point `FIOS_OBSERVATIONS_DIR` at the native sampler's output. Set `FIOS_INVENTORY_ID` to `fios-core`, `studio-a` for edge-a, or `studio-b` for edge-b. The same image can run on each host. The Studio SSH names are `fios-edge-a.local` and `fios-edge-b.local`. The inventory uses the slot IDs above. The native supervisor and Studio rollout still follow the Core-first operations qualification. [Operations roadmap](specs/001-platform-foundation/tasks.md#following-milestones)

The native enrollment service enables chat only with a private inference key, a loopback policy port, and a pinned policy revision. The UI receives its separate bridge key. Record an operator-reviewed qualification report with `model-record`, then use `model-promote` with the expected current revision. Use `model-withdraw` to fence affected work. Compare the artifacts and reports against the qualification criteria before importing them. [Qualification and rollback procedure](specs/004-private-chat-coding/quickstart.md)

Run `make chat-test` for portable verification. On fios-core, `make chat-acceptance` exercises the browser API against an isolated OrbStack UI and native test service, replaces the UI container and verifies that chat history reopens. It cleans up the run-owned container and image. Runtime measurement and promotion have their own gates. [Spec 4 qualification guide](specs/004-private-chat-coding/quickstart.md)

## Development record

- [Feature specification](specs/001-platform-foundation/spec.md) defines the initial delivery and the product journeys.
- [Development plan and threat review](specs/001-platform-foundation/plan.md) covers agents, routing, storage, admin, models, sandboxes and public identity.
- [Research and qualification criteria](specs/001-platform-foundation/research.md) compare model sizes and licenses, single- and multi-host runtimes, isolation and search providers.
- [Tasks and verified handoff](specs/001-platform-foundation/tasks.md) track implementation and the next executable slice.
- [Future roadmap](specs/roadmap.md) tracks Deep Research and subsequent milestones.
- [Creative presets](src/agent/authoring.toml) define initial campaign, one-shot, session and art direction for future Projects.
- [Spec Kit workflow](.specify/README.md) describes the installed Codex skills, tooling and workflow.

## Paired Studio inference

Spec 005 uses a private JACCL link between the two Studios. Paired jobs acquire both reservations before starting. The reporter alone retrieves conversation text and submits an answer. The Mini commits the answer after both ranks complete and their transport records agree.

Use `make pair-test` for the portable suite and `make pair-acceptance` on fios-core for the disposable native services. The hardware guide covers the matched model workload, authenticated leases, failure tests and release checks. Disable a paired alias with `model-withdraw` and its expected revision. The workers fence and clean both rank processes before either slot is reused. [Spec 005 hardware validation](specs/005-paired-studio-inference/quickstart.md)

### Large MoE qualification

Spec 006 reserves both Studios for a large mixture-of-experts model. Fios-core coordinates requests and publication. The private **Large MoE** choice requires an approved hardware report for the exact weights, runtime, tokenizer, checker and Studio pair. Its limit is 8,192 total tokens, including up to 1,024 generated tokens.

Use `make moe-test` for placement, budget and evidence tests, and `make moe-acceptance` on fios-core for the disposable services and WebKit check. The hardware procedure covers the separate probe and full-pack approvals, rank and link interruptions, actual browser timings, withdrawal and cleanup. [Spec 006 qualification guide](specs/006-large-moe-qualification/quickstart.md)
