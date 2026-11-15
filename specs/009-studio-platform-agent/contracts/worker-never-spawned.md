# Live cancellation before worker creation

T021 now has a concrete local non-dispatch issuer for a launch that the original Python factory cancels before `Process.run`. It does not issue native completion or quiescence evidence.

`Journal.planWorkerStart` commits the ordinary launch intent, then returns an opaque live plan containing the exact job, attempt, nonce and inference scope. Its initializer is confined to the journal source file. The factory verifies the selected binding against the complete scope and consumes the plan once before creating its asynchronous operation. A nonce, recovered launch row or local reap record cannot reconstruct that plan.

Only the factory file can construct `WorkerNeverSpawnedEvidence`. The constructor is reached when either of the two cancellation checks before process creation returns; other errors remain unavailable and successful process creation returns the ordinary transport. The background operation performs no journal I/O and transfers its result once to the serialized broker.

The broker passes this evidence to one journal transaction. It requires the exact job/attempt/scope, the original current-boot unreaped nonce, no worker grant and a reserved/uncertain scope. It atomically records the local launch as never started, removes only that attempt's unresolved claim and records `not_sent`. A dispatched scope refuses. Request history and its ordinal remain spent. Only after the transaction succeeds does the broker release the local worker reservation. Failure retains the launch hold and uncertainty.

The existing generic cancellation/local-reap operation still leaves inference claims untouched. A process that was created, an unavailable start, census/restart history and unrelated or older uncertain attempts gain no non-dispatch evidence from this path. The live plan is not persisted or reconstructed after manager restart; stored unresolved claims retain the existing recovery rules.

The real installed-Python factory fixture exercises an initially cancelled operation before process creation, rejects a different binding scope, consumes the plan once, refuses a foreign job/attempt and replay, preserves older native uncertainty and history, refuses a contradictory dispatched state and refuses reconstructing a live plan from durable local-reap history. Reopening its isolated journal retains the exact states. The pending-source-loss integration accepts only per-attempt `uncertain` or proven `not_sent`, keeps history spent, and preserves the earlier uncertainty count. Existing late-created-worker cancellation and reap-only tests still require retained inference uncertainty.

All model traffic in the full suite uses its fixed private mock endpoint. This source increment does not complete whole T021: the native terminal/quiescence issuer, complete all-client contract, installed enrollment and Studio acceptance remain open. Whole-task progress remains39/55.
