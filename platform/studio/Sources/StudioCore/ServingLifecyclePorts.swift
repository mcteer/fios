import Foundation

// Trusted code-only wiring, not decoded metadata/native authority. No installed
// producer exists. The callback must be nonblocking: it can return only an
// already prepared intent backed by a separately retained native reservation,
// never acquire a lease, hash a file or perform IPC on the manager heartbeat.
struct ServingLifecyclePorts:Sendable {
    let runtime:any ServingProcessControlling
    let intent:@Sendable(ServiceRecordedLaunch,ServiceDesired)->ServingStopIntent?
}
