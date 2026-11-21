# Administrative model-load request custody

`POST /v1/load-model` dispatches to its administrative handler before the normal router's model binding. After that handler resolves its requested ID/path/alias, bind its original accepted ingress to the exact registry entry before calling the existing loader. Reuse that resolved ID for the load and its error response. An intervening default change must not select another model.

Use the existing native request tracker. Do not create a replacement root, change correlation, activate the diagnostic primary guard or issue an admission/terminal proof. An ordinary request without tracked ingress retains its existing path. Conflicting ownership, a target mutation, independent uncertainty or an unknown target must refuse before preparation under the existing guard semantics.

The isolated fixture executes the actual metadata helper with CPU registry/loader substitutes and the actual tracker. Original explicit/default/marketing-default calls fail the missing-association assertion; ordinary untracked behavior is a passing control. Candidate cases cover exact IDs, changed default, retained original correlation and pre-loader refusal. Full source builds and empty-model checks are separate from actual loaded-model/native acceptance.
