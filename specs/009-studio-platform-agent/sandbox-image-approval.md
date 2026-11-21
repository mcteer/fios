# Sandbox image artifact approval — 2026-11-14

The operator answered **“Approve image only”** to the exact artifact question for:

`sha256:0406a8451a382eef038d8ac37035ccfb4e2a1e4e7b22c4a349fd9c4648a77c0b`

This approves that immutable artifact for later enrollment. It does not approve enrollment, installation, activation, native admission, a model request or deployment. Publisher/build authenticity remains unestablished, as stated in the approved review. This document records the operator decision; it is not a machine-consumed enrollment policy or runtime authority.

The unchanged pre-decision review is `/private/tmp/fios-009-sandbox-review-k_1f4su1/review-summary.json`, SHA `ad7a08d5e6a6d862619fec07f89ff6255a4672b2171523a30dfc6672ae2271b4`. Its `approved:false` is preserved as historical pre-approval evidence. Candidate SHA `0f0c78714fecf00acfaf3d25fc6e96d0b6a419d56ee076ba9bdfcf6e07b8f238`; base archive SHA `8b4ec841ed28c3d8849dcea509f862515f5a694896a88c4a11a5be9e376766dc`; measured base-content receipt SHA `f13c7cfef4245958375e306abcfabf8b607d59b40ae3a9eb4279ae0f0b76ea6a`.

Readonly post-decision verification is `/private/tmp/fios-009-image-approval-X0phNL/verification.json`, SHA `647209c7b8ac69b74f624c928376538555c33b86a3a47a4aa979aca67a3b570e`. It independently rechecks the immutable image/configuration/labels through the pinned private CLI, candidate/review/archive/content identities, original probe-container absence and clean437ecbf review checkout. The five current image-producer inputs still match declared projection `361dd44be8ee8fedf0d60e4ac545f7e1d6bee22a33c3088b9b9e84038f77caa9`; this is not whole-repository/native provenance. Current unrelated workspace edits are not included in that projection.

Together with the previously passing build/runner/std-library/private-worker/mock-model/artifact tests, this satisfies T033's remaining approved-artifact requirement. **39/55 whole tasks are complete;16 remain open.** T036 and installed/runtime/Studio/native acceptance remain open. Production `approved_sandbox_images` remains empty, and no protected policy, enrollment file, image, container or installed service was changed by the recheck.
