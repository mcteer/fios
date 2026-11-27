# Data model

These logical fields extend the Spec 3 job ledger and describe the new private content store and catalog. Existing job, session, hold, incarnation, usage and reconciliation constraints continue to apply.

| Field | Canonical rule |
| --- | --- |
| `Profile.revision` | Immutable digest of the complete manifest covering upstream and converted artifacts, hashes, license, runtime/build, tokenizer/template, host class, settings, evidence policy and eval versions. |
| `Profile.alias` | Exactly `general-chat` on the Mini or `coding` on one enrolled Studio. |
| `Profile.limits` | Positive measured peak bytes, positive bounded total context tokens, reserved output smaller than total context, one active request per executor and finite deadlines. |
| `Qualification.trial_budget` | Immutable settings for one trial. Require positive workload budget bytes and a positive host headroom floor. Fresh free headroom before launch must cover both. Budget includes the full model workload, worker and policy overhead. Mini budget is at most 6,000,000,000 bytes. Footprint at or above budget, headroom below the floor, unavailable measurements or non-normal pressure abort the trial. |
| `Qualification.evidence` | Append-only trial record scoped to one profile and target hardware, dated, with fixture outcomes, units, memory method, cold/warm timing, operator-defined latency bounds, license review and rollback result. Synthetic trials are labeled separately. |
| `Qualification.state` | Candidate → passed or failed. An admin may promote a passed real trial or withdraw an active revision. At most one promoted revision per alias. Invalidation closes admission immediately. |
| `Conversation.id` | Server-issued opaque identifier scoped to the verified owner. A deletion tombstone may outlive all content. |
| `Conversation.title` | Plain text, at most 80 Unicode characters. Neutral placeholder until approved subject-bearing material exists. Derived titles share conversation ownership and deletion. |
| `Turn.request` | Immutable owner/incarnation/key with private keyed digest of normalized client intent. A changed request under the same key conflicts. Pinned profile and job saved at first admission. |
| `Turn.content` | Private user text and approved immutable ordered answer segments, at most 16 KiB user text and 64 KiB total answer per turn. One active turn per conversation. Limit each owner's active history to 64 MiB of UTF-8 content including titles. Charge prompts, answers and titles by UTF-8 byte count, including the placeholder when a conversation is created. |
| `Turn.reserved_bytes` | Durable nonnegative per-turn allowance for unpublished answer bytes and possible title growth. Initially reserve up to 64 KiB for the answer and the maximum title growth allowed under `Conversation.title` in UTF-8. Retained content plus all open reservations must fit the owner's quota. Admission and conversion to retained content are atomic. Terminal settlement or deletion releases unused bytes once. Restore reconciles reservations with the private turn state before reopening admission. |
| `Turn.publication` | Each segment carries sequence, checksum, decision and policy revision. Only current-policy-approved, owner-visible text may leave staging. Deleted, denied or ambiguous content cannot be fetched. |
| `Turn.usage` | Preserve Spec 3 measured, estimated and unknown tags independently for input and output. Validate against their respective admitted token budgets, including prompt overhead. Real jobs have no synthetic tariff. |

Terminal state follows the job even if content was removed. Only completed, currently approved exchanges enter later context. A bounded per-owner metadata/row cap supplements the byte quota so empty conversations cannot exhaust storage. Keep digests and key material private. A quota refusal preserves existing history for owner-directed deletion.
