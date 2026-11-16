# Native test graph and SDK boundary integration

T018/T022 remain open; whole39/55 remains unchanged. This source repair is
functional integration, not native coverage, terminality or admission authority.

Running the real filtered native test target exposed two earlier gaps. The
enabled test root did not link the selected ownership C++ ports or force its
actual Zig host exports into the test root. Separately, the SDK ANE guard imported
a host `fios/` latch directly; the unchanged import-closure checker rejected that
edge for50 plugin closures. Neither failed aggregate is a passing native test.

The repair links the same existing selected SDK/DS4 ownership port sources into
the test module and imports the actual SDK ownership exports when that build
option is enabled. It introduces no replacement ABI, dummy symbol, numerical
implementation or source-guard activation. Ordinary disabled builds retain their
existing selection.

The ANE reported-run latch moves into `sdk/ane/run_uncertainty.zig`, where its
only shared dependency is `sdk/util/shared.zig`. The old host API forwards to
that same SDK implementation. Its exact shared-storage key, atomic acquire/
release behavior and sticky failure semantics remain. Success cannot clear it;
this is negative evidence, never positive completion. The SDK guard imports its
local SDK implementation, so it no longer crosses into host code. No import rule
or allowlist is relaxed.

The checker verifies the exact five-file reverse/reapply parent projection and
runs the unchanged real closure checker against both complete private source
copies under network denial. The original violation must reproduce and the
candidate must pass. These results establish that declared dependency boundary,
not whole-repository provenance or loaded/native acceptance.

```sh
.venv/bin/python -I scripts/check-platform-native-test-integration.py \
  --parent /private/tmp/REVIEWED_PARENT \
  --source /private/tmp/REVIEWED_CANDIDATE
```

Enabled native compilation/linking and actual filtered registry/latch execution
are separate qualifications. Keep their logs and exact source identities beside
the closure receipt. No installed action or model is needed for these checks.
