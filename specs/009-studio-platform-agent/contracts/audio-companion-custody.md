# Audio companion request custody

The existing MLX-Serve transcription handler can load an aligner and a diarizer after the primary ASR request is active. Before each exact companion reaches `ensureLoaded`, associate its resolved registry ID with the original request through `bindAuxiliaryCurrent`. Retain the original primary, token and correlation. Association is idempotent for the same companion and precedes both ready and cold-load paths.

Apply this only when the selected entry already has the source ownership guard. Ordinary unenrolled behavior remains unchanged. Missing owner, independent uncertainty or an existing mutation must refuse before the loader; existing handler error/optional-companion behavior remains unchanged. No new inference implementation, model selection policy, retry, native admission or terminal proof is introduced.

The isolated regression substitutes only registry resolution and the loader. It executes the actual candidate helper and actual native tracker under Debug and ReleaseSafe. The baseline uses each original call shape and must fail its pre-loader model-association assertion; unenrolled behavior is a passing control. Positive controls retain the original correlation after caller retirement; negative controls execute no loader. This is selected source/CPU evidence, not loaded modality or Studio acceptance.
