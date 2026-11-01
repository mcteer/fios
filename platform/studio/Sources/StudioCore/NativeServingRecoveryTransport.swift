import Foundation

// Source integration, not a protected installation/profile issuer. The native
// runtime still revalidates its separately supplied reservation before spawn.
// MLX never falls back to the GUI session actuator, including on failure.
struct NativeServingRecoveryTransport:ServiceRecoverySending {
    let applicationHashes:[ManagedService:String]
    private let profile:String
    private let runtime:any ServingProcessControlling
    private let session:SessionControlClient?
    var recoveryProfileHash:String {profile}
    init(runtime:any ServingProcessControlling,approvedHashes:[ManagedService:String],session:SessionControlClient?=nil)throws {
        let base=try ServiceLaunchProfile.digest(approvedHashes),profile=runtime.recoveryProfileHash
        guard runtime.acceptsBaseProfile(base,expectedSHA256:approvedHashes[.mlx]!) else {throw ServiceError.invalid}
        let probe=ServiceLaunchCommand(service:.mlx,id:UUID().uuidString.lowercased(),expectedSHA256:approvedHashes[.mlx]!,profileHash:profile)
        guard runtime.accepts(probe) else {throw ServiceError.invalid}
        if let session {
            // Session enrollment still names its legacy GUI images. Native
            // MLX uses a different combined profile; only the fixed OrbStack
            // delegation crosses into that independently verified session realm.
            guard session.applicationHashes[.orbstack]==approvedHashes[.orbstack] else {throw ServiceError.invalid}
        }
        self.runtime=runtime;self.session=session;applicationHashes=approvedHashes;self.profile=profile
    }
    func accepts(_ command:ServiceLaunchCommand)->Bool {
        WireScalar.uuid(command.id) && command.profileHash==profile && command.expectedSHA256==applicationHashes[command.service]
    }
    func owns(_ candidate:any ServingProcessControlling)->Bool {runtime === candidate}
    func request(_ request:ServiceRecoveryRequest)throws->SessionLaunchResult {
        guard accepts(request.command) else {throw ControlError.unauthorized}
        if request.command.service == .orbstack {
            guard let session else {throw SessionTransportFailure.unavailable}
            return try session.request(operation:request.operation,service:.orbstack,id:request.command.id)
        }
        switch request.operation {
        case .launch:
            // Exact owned-child exit can release local process custody only.
            // This runs off-loop, cannot retire an uncertain generation, and
            // begin still revalidates the independent native start reservation.
            _=runtime.retireKnownExited()
            do {try runtime.begin(request.command,deadline:ProcessInfo.processInfo.systemUptime+10)}
            catch RuntimeError.capacity {
                // This may be a repeated ID while the original spawn is still
                // pending. Capacity failure cannot rewrite it as not-sent.
                return runtime.acknowledgeResult(id:request.command.id)
            }
            return .uncertain // Completion is retrieved by the original ID.
        case .lookup:return runtime.acknowledgeResult(id:request.command.id)
        case .cancel:
            _=runtime.cancelValidation(id:request.command.id)
            return runtime.acknowledgeResult(id:request.command.id)
        }
    }
}
