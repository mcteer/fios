# Feature specification for authenticated Studio enrollment

**Feature** · `002-studio-enrollment`

**Created** · 2026-11-27

**Status** · Draft

**Input** · Implement roadmap milestone T005. Let the operator enroll the two Studio workers, authenticate their native agents and see trustworthy, current heartbeats in the Mini's inventory.

## User Scenarios & Testing

### User Story 1 · Enroll an approved Studio (P1)

The operator binds each configured Studio entry to one approved machine identity. The agent verifies it is talking to the intended core before sending measurements. The core accepts reports only from the approved machine acting for its assigned Studio.

**Independent test** · Enroll one synthetic worker and try a valid report, an unknown credential, and a valid credential claiming the other Studio.

1. **Given** an approved binding and valid machine credentials on both sides, **when** the agent contacts the core and submits its first valid heartbeat, **then** the assigned Studio shows Reporting with its own measurements.
2. **Given** an unapproved identity, an expired credential, or a credential assigned to a different host, **when** a heartbeat arrives, **then** the core refuses it and preserves the last accepted observation and its freshness.
3. **Given** an agent pointed at a core it cannot authenticate, **when** it attempts to connect, **then** it sends no heartbeat payload.

### User Story 2 · See current worker telemetry (P1)

The operator can tell whether each Studio is reporting now. Stale or invalid reports cannot make a worker appear available. The Mini continues to use its existing local observation path.

**Independent test** · Use two synthetic workers and advance a controlled clock while withholding one worker's heartbeats.

1. **Given** both Studios are enrolled, **when** their independently authenticated reports arrive, **then** each report appears only on its assigned host and each host's freshness is calculated independently.
2. **Given** a Studio stops sending heartbeats, **when** its last accepted observation exceeds the freshness limit, **then** its last good measurements display as stale and it no longer counts as reporting.
3. **Given** a current observation, **when** an authenticated worker submits a duplicate, out-of-order, retired-session, or invalid report, **then** the core leaves the accepted values and freshness unchanged.

### User Story 3 · Recover or withdraw trust (P2)

The operator can recover from a restart, rotate credentials or revoke a Studio binding without affecting the other worker. The supervised native worker reconnects after transient interruption.

**Independent test** · Interrupt a synthetic worker, rotate its credential, revoke enrollment, and restart the core.

1. **Given** a worker process exits or the core becomes temporarily unreachable, **when** the service and authenticated path recover, **then** a new heartbeat restores Reporting within the recovery window. Delayed reports from its retired session cannot replace that heartbeat.
2. **Given** a credential rotation completes, **when** the worker presents the replacement credential, **then** it retains its configured host ID. The retired credential can no longer update that host.
3. **Given** the operator revokes a Studio identity, **when** the operation completes, **then** the Studio immediately stops counting as reporting. Reports using the revoked identity continue to fail after a core restart.
4. **Given** the core restarts, **when** it restores enrollment records, **then** a Studio counts as reporting only after it submits a new accepted heartbeat. The core need not retain historical measurements.

### Edge Cases

- A configured Studio with no binding shows Not enrolled. An enrolled Studio awaiting its first accepted heartbeat shows Awaiting sample. A revoked binding shows Revoked. A previously reporting Studio with an expired observation shows Stale sample.
- A rejected report cannot reset a last-good timestamp, clear a reporting status, or change another worker's record. Rejected reports are observable to the operator by reason without exposing credentials.
- A restart or reconnect can establish a new authenticated session. Once replaced, a session cannot become current again. Within a session, accepted sequence numbers strictly increase. Skipped sequence numbers are permitted.
- A report outside the documented clock-skew and maximum-age limits is rejected. The plan will choose these limits and the clock used to evaluate them. Freshness is based on accepted observations and cannot be prolonged by a future-dated source timestamp.
- After revocation, restoring a worker requires explicit approval and a new credential binding. The worker label can remain the same.

## Requirements

### Functional Requirements

- **FR-001** The operator must explicitly approve a machine identity and bind it to one of the two configured Studio IDs. The core must reject ambiguous bindings and recruitment outside the configured inventory. SSH access alone grants no enrollment authority.
- **FR-002** The worker and core must authenticate each other before exchanging heartbeat data over the private management network. A credential must be scoped to the approved machine identity and be subject to expiry and revocation.
- **FR-003** The core must validate a bounded, versioned heartbeat tied to an authenticated agent session. A heartbeat carries a host ID, session identity, sequence, observation time, physical memory, logical CPU count and one-minute load.
- **FR-004** The core must reject messages that mismatch the approved binding or current session, repeat or regress an accepted sequence, fail clock or schema validation, or use an inactive credential. Rejections must leave accepted observations and freshness intact.
- **FR-005** Inventory must present enrollment status, observation status and the last usable observation when available. The core must distinguish the reported measurements from schedulable capacity and expose no remote administrative controls through the heartbeat interface.
- **FR-006** The operator must be able to rotate and revoke worker credentials and rotate the cluster trust anchor with an operator-approved procedure. Enrollment and revocation decisions must survive a core restart. Previously accepted reports must not regain freshness after a restart.
- **FR-007** Each enrolled Studio must run a native macOS worker supervised by the host service manager, recover from an unexpected worker exit and retry a transient connection loss within a bounded recovery policy.
- **FR-008** Enrollment changes and heartbeat rejections must provide diagnostic outcomes without exposing private credential material. The Mini's local operator dashboard and sampler must continue to work independently of Studio enrollment.
- **FR-009** The core must keep the existing dashboard and administrative workflow restricted to the local operator. The Studio interface accepts machine heartbeats on the approved private management path and grants no operator authority.

### Key Entities

- **Configured Studio** · Stable inventory ID and display label for a worker slot.
- **Enrollment** · Operator-approved association between a configured Studio and a machine identity, with active or revoked state.
- **Credential** · Time-bounded proof tied to the approved identity and cluster trust.
- **Agent session** · Core-recognized instance of an authenticated worker connection with a highest accepted sequence.
- **Heartbeat** · Versioned measurement and freshness evidence from one current session.
- **Worker observation state** · Operator-visible state computed from enrollment and accepted measurements.

## Success Criteria

### Measurable Outcomes

- **SC-001** In a two-worker test, each approved worker updates exactly one configured host. Every unknown, expired, revoked or mismatched credential case is rejected without altering the previous accepted report.
- **SC-002** Under the default preview settings an enrolled worker reports within 10 seconds of a healthy authenticated connection. After its final accepted heartbeat becomes older than 30 seconds it no longer counts as reporting when the inventory is read.
- **SC-003** In controlled tests, duplicates, out-of-order reports, retired sessions, malformed payloads and disallowed clock values leave report contents and freshness unchanged. A new valid report restores fresh status within the default 10-second window once connection and supervision have recovered.
- **SC-004** After completing rotation or revocation, the previously trusted credential cannot update the Studio. Revocation still holds after a core restart. In a separate restart test, an active worker must send a new accepted heartbeat before it counts as reporting again.
- **SC-005** Build the agent service on `fios-core` and verify local startup, supervision, fresh telemetry and recovery. Verify both worker flows using synthetic identities on `fios-core`. Record passing results before building or installing the agent on either Studio.
- **SC-006** After the core verification passes and the operator approves the actual machine identities and trust anchor, verify a supervised native worker and advancing heartbeat on each Studio. Confirm the Mini remains locally accessible throughout.

## Assumptions

- The scope is the Mini control plane, `fios-core`, and the Studios, `edge-a` and `edge-b`. The existing `studio-a` and `studio-b` entries are inventory aliases. Enrollment still requires an operator-approved machine identity for each binding.
- The worker initiates communication over the private management network. Thunderbolt RDMA qualification remains a later milestone. Live deployment uses operator-approved identities and a cluster trust anchor.
- The 30-second freshness window carries forward from Spec 1. The default 10-second reporting target is an initial acceptance assumption. Heartbeat cadence, retry limits, certificate lifetime, clock tolerance and credential storage belong to planning.
- Heartbeats describe host observations. Scheduling, leases, job execution, model serving, user authentication and public ingress are subsequent milestones.
