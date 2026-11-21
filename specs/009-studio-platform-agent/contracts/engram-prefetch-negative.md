# Existing Engram read-ahead: negative source fence

The current DeepSeek plugin can retain Engram read-ahead across prompt chunks.
Its existing worker does not capture original request custody. The four-path
candidate marks sticky negative evidence before publishing that worker, after
its input-copy/allocation setup. It changes no IO schedule, prefetch math,
thread count, numerical code, model setting or wire protocol.

The flag has one explicitly registered host-owned Shared storage. The plugin
sets it before spawning; the fixed backend getter reads it without callbacks,
loads, synchronization or model operations. The existing host negative probe
already composes that getter. Worker completion, local stop/join/free, subsequent
objects and metadata cannot reset the flag or establish native terminality.
Allocation failure before publication has no effect on this flag.

The checker reconstructs the exact four-path parent from its three hashes and
new file, then executes each prefix's actual constructor, freeGrid, finish and
fixed getter. Tables and worker IO are metadata substitutes; allocators,
threads, field-copy/free methods and Shared storage are real. The candidate
latch declaration is injected into the original fixture only to isolate its
missing publication fence. Four original runtime failures and their controls
are checked in fresh network-denied processes in Debug/ReleaseSafe. Optional
`--shared-units` builds separate plugin/host objects to test the actual shared
address boundary. It exercises no real table, model or GPU.

This does not implement Engram original custody or bounded parent cleanup.
It prevents this unqualified path from supporting a future idle/complete claim.
Full native build/unit/empty-model integration evidence remains independently
scoped. All-client source/proof/admission, installed acceptance and native
activation are separate unfinished requirements.

The async source review also distinguishes unused/compiled-out paths: no
production caller of the generic SDK Poster's enablePosting was found in the
reviewed src tree. This native candidate's build uses mas=true; the existing
outside-plugin supported predicate is false and loadAtStartup returns before
settings/loading. Those are source/profile review facts, not proof for another
build profile and not a reason to change either path.
