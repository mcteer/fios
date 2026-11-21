import Foundation

// Shared consistency checks for an already trusted binding, not a producer of
// compatibility, capacity, NativeSnapshot or an atomic native reservation.
// Production must still provide the audited all-client native guard. The
// observation alone cannot close the source-to-dispatch race.
enum NativeAdmission {
    // Exact UTF-8 identity plus a monotonic observation checkpoint. Neither
    // predicate establishes freshness, eligibility or dispatch authority.
    static func scopeIdentity(_ binding:WorkerDispatchBinding)->[Data] {
        [binding.host,binding.profileHash,binding.managerEpoch,binding.nativeSnapshot.nativeEpoch,
         binding.nativeSnapshot.endpointHash,binding.canonicalModel,binding.nativeModel].map {Data($0.utf8)}
    }
    static func retainsCheckpoint(_ current:WorkerDispatchBinding,original:WorkerDispatchBinding)->Bool {
        scopeIdentity(current)==scopeIdentity(original) &&
        current.nativeSnapshot.sequence>=original.nativeSnapshot.sequence &&
        current.nativeSnapshot.sampledAt>=original.nativeSnapshot.sampledAt
    }
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
        switch try ActivityPolicy.evaluate(binding.nativeSnapshot,now:now) {
        case .busy(let model):return WireScalar.exactModel(model,binding.canonicalModel)
        case .idle:return true
        case .preparing:
            // Preparation may retain an idle previous resident during a model
            // replacement. An outstanding owner is different: loading must not
            // mask a conflicting or unidentified active model.
            let snapshot=binding.nativeSnapshot
            guard snapshot.outstandingOwners>0 else {return true}
            guard let model=snapshot.residentModel else {return false}
            return WireScalar.exactModel(model,binding.canonicalModel)
        case .unknown:return false
        }
    }
}
