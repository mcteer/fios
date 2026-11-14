import Foundation

// Explicitly invoked once by trusted reviewed bootstrap enrollment, never by a
// task/model packet and never an automatic recurring telemetry service.
final class VMProbeCoordinator {
    private let journal:Journal
    private let jobs:JobController
    private let sandbox:SandboxTaskController
    init(journal:Journal,jobs:JobController,sandbox:SandboxTaskController) {
        self.journal=journal;self.jobs=jobs;self.sandbox=sandbox
    }
    func begin(permission:VMProbePermission,sample:ResourceSample,admission:inout AdmissionPolicy,now:Int64)throws->String {
        let id=permission.id,nonce=permission.nonce
        let configuration=try SandboxConfiguration(job:id,nonce:nonce,image:permission.image,memory:512<<20,cpus:1)
        let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:permission.ownerHash,requestHash:VMProbePermission.sourceHash,created:permission.issued,lifetime:30000)
        try admission.reserveVMProbe(configuration,permission:permission,sample:sample,now:now)
        do {
            try permission.consume(job:id,now:now)
            _=try journal.reserveSandbox(job:job,configuration:configuration)
            try jobs.authorizeVMProbe(id:id,permission:permission,now:now)
            try sandbox.register(id:id,owner:permission.ownerHash,source:VMProbePermission.source,inputSHA256:VMProbePermission.sourceHash,binding:nil,now:now)
            return id
        } catch {
            // No runtime submission occurs inside begin. If durable state is
            // present, let normal proof-gated lifecycle cleanup retain it.
            if let stored=try? journal.jobs().contains(where:{$0.id==id}) {
                if stored {try? journal.transitionJob(id:id,to:.revoking,now:now)}
                else {admission.releaseProvenAbsent(job:id)}
            }
            throw error
        }
    }
}
