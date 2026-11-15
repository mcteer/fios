# Fixed-tracker registry preparation withdrawal

The current `ModelRegistry` exposes its existing strict CPU-reference withdrawal
through the same fixed process tracker as claim and attachment. Call it outside
the registry mutex so its public fixed negative probe runs before tracker locking.
It returns `void`, reads no current catalog/generation and does not actuate model
loading, eviction, capacity or inference reconciliation. Current catalog freshness
is not needed to remove that exact local bookkeeping reference; success does not
attest catalog freshness or native inactivity.

The underlying exact token/model/correlation, unattached/single-reference and
independent-uncertainty checks remain mandatory. Attached or mismatched references
refuse without changing ownership. Missing lineage and successful withdrawal
remain no not-sent/completion proof. The actual serving source guard stays false.
No wire or serving caller is added.

The existing actual-native registry stub test now covers attached/wrong-target
refusal, exact withdrawal, unchanged unloaded model/catalog generation and the
unsupported guard. It never loads a model. Exact one-file reverse/reapply and
full-file AST checks pass; native enclosure evidence is recorded separately in
[validation](../validation.md). No new behavioral-red claim is made for this
adapter method's original absence.


Final selected-source enclosure passes actual default162/162, enabled35/35
semantic32/32 link steps,4 empty-model runtime checks and post-run byte review.
Aggregate5ba97713… binds exact evidence in validation. These are CPU adapter and
ordinary empty-model checks, not inference proof or installed native acceptance.
