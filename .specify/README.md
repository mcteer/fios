# Spec Kit for fios

GitHub Spec Kit v1.4.5 is initialized at the repository root with the Codex integration, the Bash core scripts and the bundled Full SDD Cycle workflow. Specify installed the nine project skills under `.agents/skills/`. The project constitution is in `memory/constitution.md`. [Upstream release](https://github.com/github/spec-kit/releases/tag/v1.4.5) · [Codex integration](https://github.com/github/spec-kit/blob/v1.4.5/docs/integrations/codex.md)

## Use the installed framework

On a fresh Apple Silicon development Mac with CPython 3.15, run the following from the repository root. `make spec-tools` installs Specify and its hash-pinned wheels in a project-local virtual environment and selects the existing foundation roadmap if this checkout has no current feature. The application itself uses the standard library and supports Python 3.11 or newer.

```sh
make spec-tools
source .venv/bin/activate
specify integration status
specify workflow list
make spec-check
codex
```

For other development platforms, use an upstream-supported installation of `specify-cli==1.4.5` and set `SPECIFY=specify` when invoking Make. On a fresh checkout, select the existing roadmap by running `SPECIFY_FEATURE_DIRECTORY=specs/001-platform-foundation bash .specify/scripts/bash/check-prerequisites.sh --require-spec --require-tasks` once. Spec Kit maintains its active-feature pointer locally. [Official installation guide](https://github.com/github/spec-kit/blob/v1.4.5/docs/installation.md)

Use `$speckit-specify` for a new feature, `$speckit-clarify` for open product decisions, `$speckit-plan` for design and `$speckit-tasks` for verifiable slices. Use `$speckit-analyze` to check consistency across the artifacts. When the requested deliverable is a plan, finish at the planning boundary. Invoke `$speckit-implement` when implementation is requested.

The [current roadmap](../specs/001-platform-foundation/tasks.md) has its own [specification](../specs/001-platform-foundation/spec.md) and [development plan](../specs/001-platform-foundation/plan.md). The core scripts can resolve these artifacts from this workspace.

## Initialization record

The official CLI was installed from the published PyPI wheel and initialized with `specify init --here --integration codex --script sh --force --non-interactive` after checking the merge in a disposable directory. The saved integration manifest and workflow registry are part of the checkout. Normal setup uses `make spec-tools` and does not require reinitialization.

Specify reported Codex as default, all managed files matching, and zero missing files. A local Codex app-server discovery request for this repository reported all nine enabled skills. The existing spec, development plan, roadmap, constitution and AGENTS.md passed checksum verification after initialization.
