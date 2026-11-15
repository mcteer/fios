# Vendor GUI launch coexistence

This source candidate addresses the documented manual-GUI interference gap in T027/T049. The old vendor GUI start path finds listeners by port, selects an executable-name prefix and sends TERM/KILL before launching its own child. The candidate removes that orphan-reaping block and its PID/name/wait helpers.

The shared launch method checks `FiosServerLaunchPreflight` before generation-default migration, configuration changes or process creation. Presence of the existing fixed `/Library/Application Support/Fios/Studio/native/startup.lock` reservation refuses GUI startup, including when the managed server is absent. Metadata errors refuse. Presence is durable startup intent, not evidence that a server runs or that the marker is a valid enrollment.

When the reservation is absent, IPv4 and IPv6-only bind probes refuse an occupied/unknown port. Both descriptors close before return. The helper never listens, connects, signals or starts a process. This transient check does not retain a native startup reservation or serialize a later race. The existing own-Process stop/deinit behavior remains.

Installed handover still requires reviewed immutable native/GUI artifacts, stopping the old GUI before activation, preventing competing unreviewed GUI launches/updates, preserving configuration and the native startup guard. No installed GUI is changed here; no native version/primary-guard/profile gate is enabled. This source component does not complete T027/T049 or Studio acceptance.

The [two-file patch](../../../platform/studio/native/mlx-serve-gui-launch-preflight.patch) is an independent vendor-app projection on3736ed55, not another native engine layer. The [checker](../../../scripts/check-platform-gui-launch-preflight.mjs) reverses/reapplies it and verifies the exact parent manager hash. It compiles the actual helper with the [fixture](../../../platform/studio/native/gui_launch_preflight_test.swift.fixture) under pinned Swift6.4.2/selected Xcode SDK in debug and optimized modes. Real private IPv4/IPv6 listeners retain their descriptor/bound address/listening state; free-port probes release their descriptors, marker presence/path errors refuse and zero port refuses. Outbound networking is denied. No GUI/server/model is launched.

```sh
node scripts/check-platform-gui-launch-preflight.mjs --isolated --source /private/tmp/PRIVATE_VENDOR_SOURCE
```

The separately recorded enclosing GUI build uses its existing locked dependencies, automatic resolution disabled and no updates. Optional Keychain/netrc lookup is disabled for public artifacts; dependency pins/checksums remain enforced. It compiles the app without launching it. These selected source/build receipts do not establish installed identity or whole-native provenance. Whole-task progress remains39/55.
