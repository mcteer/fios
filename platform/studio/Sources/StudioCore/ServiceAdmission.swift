import Foundation

// Durable operator intent is an independent admission fence. A cached native
// or runtime source cannot reopen a service after maintenance/stopped commits.
// This read-only check supplies no readiness, resource or native-idle proof.
enum ServiceAdmissionPolicy {
    static func permits(journal:Journal,model:Bool,sandbox:Bool)throws->Bool {
        guard model || sandbox else {return false}
        if model,try journal.desired(service:ManagedService.mlx.rawValue) != ServiceDesired.running.rawValue {return false}
        if sandbox,try journal.desired(service:ManagedService.orbstack.rawValue) != ServiceDesired.running.rawValue {return false}
        return true
    }
}
