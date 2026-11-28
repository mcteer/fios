# Qualification and rollback rehearsal

The portable, Core rehearsal and native MLX-LM comparison targets are available. Studio promotion requires hardware evidence for the selected profile and all release gates below.

1. From the repository root on fios-core, run `make check`, `make scheduling-test`, `make chat-test` and `make chat-acceptance`. Record the active preview's health, assigned ports and service ownership. Use disposable local directories and identities.
2. Run `make pair-test` portable suite with two synthetic enrolled workers, then `make pair-acceptance` on the Mini. Exercise 100 paired versus single claim races, each receipt order, duplicated submission/finish, first-rank success followed by peer failure, policy checker outage and cancellation while checking. Expect zero partial reservations, visible partial answers or duplicate usage. Verify owner, admin, reporter and peer access tests. Rehearse management-container restart, native OrbStack recovery, ledger restart, stale-rank return and cleanup. Inspect the web flow with WebKit including keyboard selection, queue status, cancellation and unavailable model. Record teardown and verify preview health before any Studio build or install. The maintenance-only rehearsal is `PYTHONPATH=src:tests python3 -B tests/macos/verify_pair.py --outage`. It briefly stops OrbStack and restores the existing development preview.
   With the candidate unpublished, race admin trial submission against chat, then repeat with one host already held and one host stale. Retry the original key, cancel, crash and recover. Verify both-or-neither placement, no early reuse, and denials for browser, non-admin and worker trial submission. Present a trial grant to each chat payload operation. Expect no conversation, user usage or alias activation.
3. Verify both enrolled Studios, observed macOS builds, RDMA enablement, cable endpoints, private peer reachability, compatible pinned artifacts, disk space, normal pressure and measured headroom. Record per-host floor, trial ceiling, wall-time cap and latency limit before loading. Use a run-scoped native supervisor with an independent lease watchdog. Stop on missing telemetry, pressure, ceiling or floor violation. Do not automatically modify network services or reboot a host.
   Submit the pinned fixture recipe through the local admin operation on the reservation ledger that owns the real hosts. Keep the alias disabled throughout the trial and collect its report only after the two execution receipts. Reserve the baseline slot separately for the one-host comparison.
4. For each of the three candidates record source/build/pack revisions, license checks, topology, support for fixed membership, bind restrictions, process lifetime and evidence of actual transport. With each viable configuration run the same reviewed synthetic prompts, pinned template, temperature zero and fixed context/output budget on one Studio and on both. Include the six fixed-answer controls, two held-out read-only SQL cases and a separate context/output cap fixture from 004. Measure time to first answer, prefill and decode rate and both memory peaks. Require all exact-answer/SQL checks, publication controls, normal pressure, one cold plus five warm successes, the full-budget run and worst latency within the predeclared limit. Use matching conversions for the one-versus-two comparison. Record hardware-incompatible candidates with their observed reason. Never count a synthetic report toward promotion.
   First promotion requires the same model, pack, inputs and settings to pass on one Studio and on the pair. If the baseline exceeds safe capacity, select a smaller comparable candidate and repeat both measurements.

5. On the real pair show both live model partitions and attempt-bound data-plane activity on the mapped RDMA devices. Run the adapter-specific observations and TCP-only control from the [pair contract](contracts/pair.md#evidence-required-from-each-adapter) with the same verifier. Check that setup traffic alone, mixed transport and another attempt’s receipt all fail. Record the positive and negative verdicts with the pinned build. Exercise a restricted link-loss injection on the dedicated trial path while retaining management access, then kill each owned rank in separate runs. Keep an independent observer on each host. Verify surviving/stale processes stop within the 15-second lease plus the two-second poll, peer recovery supplies fresh capacity and stale frames never publish. A TCP fallback fails qualification. Verify cancellation, withdrawal during generation and unchanged single-host chat after cleanup.
6. Use the native admin interface in a disposable configuration to demonstrate promotion, one complete paired web turn, regular-user denial, stale promotion rejection, withdrawal and rollback. Restore a matched backup with fencing and inspect prior history. Verify preview health within the existing two-second request deadline. Remove only trial-owned processes, ephemeral environments, staged artifacts, certificates, containers and image tags. Keep a sanitized evidence record with per-candidate disposition in tasks.md. Production promotion remains a separate operator action.

## Native MLX-LM validation commands

Run from fios-core after both Studios have the verified dedicated Thunderbolt routes. These commands use scoped SSH, verify pinned artifacts and remove their temporary environments and identities.

- `PYTHONPATH=src:tests python3 -B tests/macos/verify_jaccl_model.py --candidate qwen3-instruct` compares one Studio and the pair on the fixed workload. It also exercises the native rank entry point with the reporter receiving the sole message payload.
- Append `--leases-only` to run the hardware scheduler receipts, TCP transport rejection, cancellation and rank-loss scenarios without repeating the full-context workload.
- Append `--leases-only --link-window` for a coordinated administrator link interruption. The harness prints its run directory and waits for the administrator terminal to arm it on edge-b. From that terminal, validate sudo, create the run directory’s `link-armed` file and wait for `link-ready` before cycling the dedicated interface. Restore `en5` automatically after the interruption. The harness requires a failed generation, released reservations and a successful paired turn after recovery.
- Append `--web-only` for the private disposable browser-to-pair exercise with a fixed fixture publication check. The active production alias requires its own separate promotion.

For the link-loss retest, open an interactive shell on edge-b before starting the harness.

```sh
ssh -t mcteer@fios-edge-b.local
sudo -v
```

Sudo hides password characters. Press Return after typing the password. A successful validation returns to the shell prompt. Keep that terminal open.

On fios-core, run:

```sh
PYTHONPATH=src:tests python3 -B tests/macos/verify_jaccl_model.py \
  --candidate qwen3-instruct --leases-only --link-window
```

When the harness prints `Run on edge-b:`, paste the full `/bin/sh` command from that line into the edge-b terminal. The helper verifies the management route, validates sudo in that terminal, and arms the current run. After both ranks start, it cycles edge-b's `en5` for four seconds and restores it. The harness verifies failed inference, cleanup and a successful retry. If interrupted and the interface remains down, run `sudo /sbin/ifconfig en5 up` on edge-b.
