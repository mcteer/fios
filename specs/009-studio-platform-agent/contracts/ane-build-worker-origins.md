# Original ownership in existing ANE build workers

The model constructor retains its caller while joining sibling compiler threads, but the original `Model.Build.run` worker entry does not install that caller's TLS ownership group. This is distinct from the second inference lane. The source repair reproduces the loss with actual-method CPU callbacks, retains original custody before spawn, enters it from stable worker storage and restores it on return.

Constructor and partial-start paths must join every started worker before returning or freeing its storage. A failed spawn can retire only its unpublished local clone while the source remains certain. Missing required origin refuses before compilation, including the one-worker/serial path. Worker entry/finish refusal must propagate constructor failure; independent uncertainty keeps the original scope and parent data. Existing serial fallback and unselected operation must remain compatible.

Tests use explicit CPU substitutes for native compilation and, where needed, declared thread-creation failure substitutes. They do not run ANE/model work, introduce an engine or model policy, or issue native/device terminal, idle, all-client or admission authority. Exact source projection, enclosing builds and separate runtime checks are required before qualification. Installed/native acceptance remains open.

Corrected source qualification passes full-file AST plus10 original failures/2 controls/12 candidate cases, default162/162 native tests, enabled35/35 semantic32/32 link and4 empty-model runtime checks. Aggregate11b2deb4… and the initial parser/fixture failures are recorded in [validation](../validation.md). This completes this selected source increment only.
