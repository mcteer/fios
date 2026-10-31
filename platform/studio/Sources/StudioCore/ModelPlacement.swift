import Foundation

// Operator allocation: this exact small model belongs only on core. This
// restriction does not classify other models or grant readiness/admission.
enum ModelPlacementPolicy {
    static let coreSmallModel="mlx-community/gemma-4-e4b-it-4bit"
    static func respectsCoreSmallAssignment(host:String,canonical:String,native:String)->Bool {
        guard WireScalar.exactModel(canonical,coreSmallModel) || WireScalar.exactModel(native,coreSmallModel) else {return true}
        return host=="fios-core" || host=="fios-core.lab"
    }
}

extension WorkerDispatchBinding {
    var modelPlacementAccepted:Bool {
        ModelPlacementPolicy.respectsCoreSmallAssignment(host:host,canonical:canonicalModel,native:nativeModel)
    }
}
