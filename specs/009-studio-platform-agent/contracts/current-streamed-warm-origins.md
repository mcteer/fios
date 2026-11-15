# Current streamed-warmer ownership port — source work

This ports the previously reviewed warmer custody algorithm to the relocated
current worker. Numerical kernel, event values, iteration adaptation and model
settings stay unchanged. It is not a new model engine or native admission API.

The compiled source-SDK profile exposes a fixed C custody ABI through every
actual host/engine/module root. Legacy profiles without the source-SDK build option keep it disabled. The
warmer never imports the host tracker implementation into a plugin object.
Enabled callers capture/merge original request groups before publishing arm or
hold work. Each committed chunk retains its own original group; the worker
enters/restores that group across commit and releases it only after retirement.
Missing custody refuses before the backend. Unknown groups remain quarantined.

The existing process Shared latch reports failures across compilation units.
Unported profiles still mark construction unproven. The ported profile cannot
turn false flags or local join into all-client/device/terminal authority. Its
actual serving primary guard remains false. There is no wire/reset operation,
model fallback, new inference budget or inference-journal resolution.

The bounded original-worker join protocol retains its object on refusal. The
expert parent consumes that result before freeing any dependent resources;
initialization unwinding uses the same check. The wrapper rechecks independent
cleanup uncertainty after its inner destructor. Source error paths retain
parents rather than interpreting a void return as successful cleanup.

The repository origin checker reconstructs the exact ten-path parent and runs
the actual generic worker with its existing CPU Trace backend, real host C
ownership bridge, current SDK bindings and original C shims. Baseline ABI
declarations are injected only to isolate the missing custody algorithm. It
does not execute a Metal warmer, model or Pydantic dispatch.

The separate parent checker executes actual cleanup methods with metadata
resource spies. Neither test creates a native proof. The earlier default162 native
cases, final enabled object/link,16 ownership cases,16 parent cases and4 current
empty-native integration checks are recorded independently in validation. The
complete all-client contract, physical acceptance and native admission remain
unfinished.

Supplemental checker profiles use the same exact parent/candidate projection
and pinned compiler. `--embedded` executes each of the12 embedded worker tests
in a fresh process in Debug and ReleaseSafe, with legacy ownership disabled:
these cover lease/pause/refusal/drain and original CPU Trace behavior. An explicit
module import prevents a lazy import from producing a zero-test success.
`--bounded` executes the owned-profile blocked-retirement case in both modes.
Its CPU backend waits on a test-owned atomic: join must refuse at its bound and
retain the backend, then consume local cleanup only after actual retirement.
Original native uncertainty must remain set after that local cleanup. Neither
profile uses Metal, issues model requests or creates an admission proof.

Run the same isolated command as the default matrix, adding exactly one of
`--embedded` or `--bounded`. Each compiler/test subprocess is bounded to120s;
network access is denied and zero selected tests fail validation. These
supplements leave the native patch, installed configuration and application
package inputs unchanged. Results are recorded separately in validation.
