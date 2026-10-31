# Sandbox image candidates

`package-platform-sandbox.mjs` is an explicit, unprivileged, one-shot local producer. It builds and probes an **unapproved candidate**; it never edits the platform release's empty approved-image list, installs a policy, admits a job, starts a native service or invokes a model.

```sh
node scripts/package-platform-sandbox.mjs --review /ABSOLUTE/REVIEW.json --sha256 INDEPENDENT_REVIEW_SHA256 --output /ABSOLUTE/PRIVATE_PARENT/NEW_CANDIDATE
node scripts/check-platform-runner.mjs --isolated --image sha256:ACTUAL_CANDIDATE_IMAGE_ID
```

The output parent must already be the invoking account's0700 directory; the target must be new. The review is canonical `JSON.stringify(value,null,2)+'\n'`,≤4096 bytes, regular/single-link/root-or-current-owner, without links or unsafe write permissions. Its independently supplied SHA256 binds these exact fields:

| Field | Required value |
| --- | --- |
| `version` |1 |
| `purpose` |`sandbox_base_build_review` |
| `base_image` |Already-cached `sha256:`+64 lowercase hex; mutable tags reject |
| `docker_cli_sha256` |Reviewed OrbStack Docker multicall artifact SHA256 |
| `python_version` |`3.11.17` |
| `platform` |`linux/arm64` |
| `provenance_sha256` |Independent base/dependency review receipt SHA256 |
| `dockerfile_sha256` |Exact reviewed recipe SHA256 |
| `runner_sha256` |Exact reviewed runner SHA256 |

This document is metadata, not proof of its own provenance and not an admission capability. A synthetic fixture review must never become production approval. Genuine base/dependency/image review, root-enrolled immutable image IDs, native/resource/admission policy and installed acceptance remain separate requirements; T033 remains open until its approved-artifact requirement is satisfied.

The producer reads the fixed installed OrbStack multicall image, verifies its independently reviewed digest and preserves the `docker` basename in its private copy. It uses only the account database's existing local OrbStack socket, a fixed environment and `DOCKER_CONFIG=/var/empty`; no inherited Docker context, remote endpoint, credentials or arbitrary argv are accepted. Base presence/architecture and absence of ONBUILD actions are checked before building. Source bytes/identities are captured before build and rechecked afterward. The build uses the cached immutable base, `--pull=false` and `--network=none`; no package-install or pull command is issued. Its context contains only the reviewed Dockerfile/runner.

The final stage starts from scratch, copying the baked Python environment, ELF dependency libraries and the single `/bin/cat` program required by the fixed metadata reader. It excludes the application tree and general shell/Node entry points. The final image has only four fixed environment values, numeric nonroot user, fixed Python pipe entry point and workspace. Inherited CMD, exposed ports, volumes, health actions and ONBUILD actions reject. Dependency libraries/site packages still require independent base review; absence of every possible helper executable is not claimed.

A fixed harmless framed task verifies actual CPython3.11.17/arm64/nonroot execution, runner bytes, missing app/shell/Node/control sockets and inability to reopen the runner control descriptor. The probe uses network-none/read-only/cap-drop/no-new-privileges,512MiB/zero swap,1CPU,64PIDs,128MiB workspace and64MiB/tmp. It has no model request. The owner pipe stays open through completion; output is bounded and retained on failure. Only an exact saved ID/name/image/nonce stopped container is removed, followed by a successful empty exact-ID query.

`candidate.json` and its printed receipt SHA bind the actual immutable image ID, base/review/provenance/source-input hashes, recipe/runner hashes and probe scope. Both `approved` and `activation` are always false. Review the actual resulting ID; byte-identical rebuilds/layer digests are not promised. Runtime admission must use its separately approved immutable ID with pull-never, never rebuild from this receipt or silently substitute another image.

Failures retain the private context, IDs/nonces, available probe stdout/stderr and build state; there is no automatic uncertain-resource cleanup. Diagnose exact ownership/terminality before any explicit cleanup. Successful output retains the image/receipt for review, with the probe verified absent. This is not native inference terminal proof or whole-repository/native provenance. The runner and attach rehearsals likewise retain evidence on failure and preserve supplied images.

For a cached OCI image saved to a private directory, an offline content inventory can bind the archive, addressed OCI index/manifest/config, compressed blobs, uncompressed layer digests and selected runtime paths without extracting or executing image files:

```sh
.venv/bin/python -I -B scripts/audit-platform-sandbox-base.py --archive /ABSOLUTE/base.tar --image sha256:EXACT_CACHED_IMAGE_ID --output /ABSOLUTE/PRIVATE_PARENT/NEW_AUDIT
```

The auditor requires a new output directory under an owned0700 parent, limits archive/layer/member sizes and rechecks the archive's file identity. It refuses duplicate archive names, digest substitution, traversal, whiteouts and special runtime files. Output records file hashes and link targets; it does not resolve arbitrary filesystem links or authenticate a publisher/build chain. `provenance.json` binds `inventory.json` and the auditor bytes, with approval/activation false. Its digest may describe content evidence in a candidate's base review, but does not turn that metadata into production approval. Review baked site packages explicitly: the current application-derived base includes the installed `fios_agent` package and its dependencies even though the final image omits `/app`. A content inventory is not an audit of those packages or proof that every possible helper executable is absent.
