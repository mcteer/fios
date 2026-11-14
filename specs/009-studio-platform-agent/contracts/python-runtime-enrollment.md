# Protected Python worker policy/factory composition

This source interface follows the existing runtime/session enrollment pattern. No policy is installed and public startup does not call this factory. Installation, complete release review and positive installed acceptance remain separately gated. A decoded document and private candidate receipt cannot construct the opaque policy.

## Fixed inputs

The only policy path is `/Library/Application Support/Fios/Studio/python-enrollment.json`; the runtime is `/Library/Application Support/Fios/Studio/python/runtime`, with its fixed `bin/python` and existing candidate manifest. There is no request-selected executable/module, argv, environment, URL, credential or model field.

The strict4KiB version1 document has exactly: `version`, `purpose` (`reviewed_platform_python_worker`), `uid`, `host`, `state_path`, `review_sha256`, `manager_sha256`, `manifest_sha256`, `python_sha256`, `uv_lock_sha256`, `producer_sha256`, `release_template_sha256`, `policy_sha256`, `python_version` (`3.11.17`) and `package_version` (`0.1.0`). Host is one of the two approved Studios. UID/host/state must match the actual manager context; review hashes are binding/audit metadata, not self-authenticating approval tokens.

## Constructor and factory boundary

Only the fixed installed manager image may load root-protected policy bytes. The constructor checks its root-protected image and kernel PID/start/UID identity, account/Studio/state and pinned root-protected interpreter binary. Development or PR images return unconfigured before reading the policy. Loading starts no subprocess and creates no runtime/model action.

`makeFactory` is a separate code-only operation which must run off the serialized manager loop. It rechecks the unchanged protected policy and manager identity, performs complete declared root-protected runtime byte review, matches interpreter/lock/producer/template identities and rechecks the interpreter before the existing fixed metadata probe. The resulting Python factory still needs independent reviewed native compatibility, exact host/model binding, readiness/resources, lease/budget and durable request accounting before any model dispatch. No public startup/dispatch wiring is enabled by this source composition.

Root-tree observations do not attest atomic mapped code or whole-OS/publisher provenance. Operator updates must preserve the separately reviewed stopped-process/backup/serialized-installation discipline. Positive installed constructor/factory, native guard/admission and Studio operational acceptance are unproven; ordinary metadata/private-runtime tests do not close those tasks.
