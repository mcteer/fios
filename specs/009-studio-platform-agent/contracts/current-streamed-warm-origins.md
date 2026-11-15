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
