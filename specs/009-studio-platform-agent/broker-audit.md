# T044 broker audit

Whole-task status: **open**. This audit separates the broker's own implementation/evidence gaps from native admission/profile/installed acceptance in T002/T022/T045/T051. No real inference or installed service action is authorized by these tests.

| Requirement | Current source/evidence | Remaining work |
| --- | --- | --- |
|≤4 POSTs/job, attempts0..3, no reset/replay | Durable request history/ordinal gate; child once-only POST accounting/no retries; restart/ownership and installed-worker/mock endpoint tests | Retain these guards through asynchronous startup changes; native acceptance separate |
|1 active/job,2 active-or-uncertain host requests | Broker entry gate plus journal inference rows; older uncertainty survives newer completion and process restart | No native capacity may be issued from local-worker absence |
|2 workers,512MiB reservations before spawn | Admission reserve precedes claim/factory; durable launch intent precedes Process.run; startup reconciliation restores reservations | Unknown/unbound failures remain held; no age/empty-query release |
|Release local memory only after worker gone | PrivateWorker exact grant/reap path and WorkerReconciler; same-manager late bound failures now adopted from the explicit broker failure set | Preserve scoped/durable proof when factory startup is split into phases |
|RSS1s/512MiB and cleanup≤2s | Actual kernel self-RSS read; exact threshold/loss/TERM/KILL tests; real ordinary/orphan/blocked-pipe child reaping | Actual breach-to-reap pipeline rehearsal remains unverified; no measured512MiB enforcement claim |
|Startup10s/write10s and independent heartbeat/status | Pipe startup/write guards and finite blocked-pipe test | Factory.start/Process.run are still synchronous in ModelBroker.submit; the worker clock starts after Process.run. Nonblocking startup with persistent pre-spawn ownership remains required |
|Request/job output and lifetime bounds |128000 policy-inclusive UTF-16 input;64000/request parser;≤4 history ordinals imply≤256000/job; durable job leases cap lifetime1800s | Preserve counters/leases across startup/cancel/restart; no text in durable logs/state |
|Persist before dispatch; uncertain crash ownership | Claim/launch intent before spawn; scoped dispatch marker before command bytes; zero-POST+terminal+reap or correlated completion only | Late reaper never resolves inference. Unbound historical-image census/enrollment and full native integration remain separately gated |

The late-failure fixture uses actual owned sleep children and an already-existing reaper to represent a factory failure after a grant was bound. It demonstrates same-manager local recovery and healthy-worker preservation, not an induced installed-factory failure, model competence, native terminality or a complete T044 acceptance run. The exact missing-history guard mutation fails before starting those new children; its private empty fixture unwinds normally before the outer runner reports the expected failure.
