# Reviewed native startup reservation — source contract

Status: source implementation and isolated fixtures only. No installed record,
production artifact, native activation or operational acceptance is supplied.
T002/T027/T049/T051 remain open.

## Entry and scope

The reviewed native build flavor is exactly 26.10.3-fios-platform. Its model-capable
entry acquires a process-lifetime reservation before native cache, backend,
subcommand or model work. Other *-fios-platform versions refuse. Supplying
FIOS_NATIVE_STARTUP cannot downgrade this build to fixture behavior.

Exact --version, --help, -h and the empty usage invocation finish before
reservation/backend initialization. Other argument combinations retain the
guarded ordinary parser. These readonly exceptions cannot run a model.

The existing *-fios-source-fixture/explicit-marker mode remains independent.
Its HOME-relative lock is not installed authority. Upstream/unqualified builds,
foreign processes and independent native participants are not made safe by this
reservation. They still require the all-client compatibility/identity contract;
absence of a cooperating lock owner is not global absence or safe launch proof.

## Fixed protected record

The fixed path is:

    /Library/Application Support/Fios/Studio/native/startup.lock

The guard opens / and each directory component descriptor-relatively, without
following links. Every directory must be root-owned, without set-ID/sticky or
group/other write bits and without an extended ACL. The final record must be a
root-owned, single-link regular file with mode 0444 or 0644, no extended ACL and
exactly 12 bytes. It is never created by the native process.

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 4 | ASCII FSG9 |
| 4 | 1 | version 1 |
| 5 | 3 | zero reserved |
| 8 | 4 | approved nonzero native UID, big endian |

The process must be nonroot with equal real/effective UIDs matching the record.
The record contains no endpoint, model, command, role, credential or admission
capability. Missing, malformed, foreign-UID or unsafe metadata refuses startup;
there is no HOME/argv/environment path override or fallback.

After validating the bounded record, the guard takes an exclusive nonblocking
flock on that same read-only descriptor. Descriptor and named inode identities,
ownership/mode/link count/size and modification/change times must still match.
The descriptor is CLOEXEC. Production close calls deliberately retain it until
kernel process exit, including runtime teardown after main returns/errors;
cooperating startup cannot slip into that interval. Child exec does not inherit
it. Image replacement is independently subject to process-image authentication,
and never proves native completion. Fixture-mode close remains idempotent and
cannot close an unrelated reused descriptor. The record is never unlinked,
replaced, truncated or treated as stale.

## Installation and uncertainty

The future separately reviewed installer must provision the protected namespace
and record for the approved account. It must stop affected processes and
serialize updates before replacing any reservation inode. Replacing a held
inode could create two independent locks and is forbidden. Current development
packages do not provision this record or enable this build flavor.

Acquisition excludes another cooperating process, including across different
HOME values. It does not authenticate the executable, certify native/foreign
participants, load a model, enable the private control transport, prove GPU or
distributed completion, authorize service launch or release inference uncertainty.
Manager/native identity checks and the complete admission contract remain
independent. OS release after process exit is not native terminal proof.

## Finite source verification

    node scripts/check-platform-native-installed-startup.mjs --isolated --zig /ABS/zig

The driver pins Zig, copies the actual guard, substitutes only the installation
root and expected filesystem owner in a private disposable namespace, and runs
libc-only children with IP networking denied. Root ownership is explicitly
synthetic; this is not an installed positive receipt. It checks actual
Debug/ReleaseSafe process exclusion across HOME changes, release with unchanged
inode, CLOEXEC/idempotent close, optimized record/UID/version/mode/hardlink/
symlink/missing-record refusal and the exact duplicate failure when a private
copy omits flock. A separate exact early-close mutation must reproduce the
second-process escape while the first is still alive. Children must exit before
fixture deletion.

The existing check-platform-native-startup.mjs continues to cover the separate
fixture mode. Full linked empty-model HTTP checks additionally require exact
version/help success while another source server holds its startup reservation,
and refusal of another serving process before backend initialization. No test
here loads weights, invokes inference, installs a service or changes RDMA.
