import Foundation

extension Journal {
    // Serialized manager-owner consistency only. A cached runtime scope must
    // include every locally retained sandbox, including creating/reconciling
    // work. This is not complete runtime inventory or a lifecycle permit.
    func serviceScopeContainsRetainedSandboxes(_ scope:ServiceAffectedScope)throws->Bool {
        guard scope.service == .orbstack else {return true}
        let known=Dictionary(uniqueKeysWithValues:try jobs().map {($0.id,$0)})
        let included=Set(scope.ownedJobs)
        for sandbox in try sandboxRecords() {
            guard let job=known[sandbox.configuration.job] else {return false}
            if job.state == .removed {
                guard sandbox.removalProven else {return false}
            }else if !included.contains(job.id) {return false}
        }
        return true
    }
}
