import Foundation

// Shared consistency checks for an already trusted binding, not a producer of
// compatibility, capacity, NativeSnapshot or an atomic native reservation.
// Production must still provide the audited all-client native guard. The
// observation alone cannot close the source-to-dispatch race.
enum NativeAdmission {
    static func bindingIsCoherent(_ binding:WorkerDispatchBinding)->Bool {
        binding.nativeCompatibilityAccepted && binding.modelPlacementAccepted &&
        WireScalar.host(binding.host) && WireScalar.model(binding.canonicalModel) && WireScalar.model(binding.nativeModel) &&
        WireScalar.sha256(binding.profileHash) && WireScalar.uuid(binding.managerEpoch) &&
        binding.nativeSnapshot.host.utf8.elementsEqual(binding.host.utf8) &&
        binding.nativeSnapshot.endpointHash==PythonWorkerFactory.digest(binding.baseURL)
    }
    static func permitsDispatch(_ binding:WorkerDispatchBinding,now:Int64)throws->Bool {
        guard bindingIsCoherent(binding) else {return false}
        return try ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now)
    }
    static func retainsSource(_ binding:WorkerDispatchBinding,now:Int64)throws->Bool {
        guard bindingIsCoherent(binding) else {return false}
        // The original request may itself be preparing/loading. This check
        // retains source quality, rather than granting another dispatch.
        return try ActivityPolicy.evaluate(binding.nativeSnapshot,now:now) != .unknown
    }
}
