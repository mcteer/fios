import Foundation

// Safe bootstrap/recovery adapter before reviewed runtime enrollment. Does not
// discover a Docker context, spawn a CLI, connect a socket or invent absence.
final class UnavailableSandboxRuntime:SandboxCreateSlotExecuting {
    private var results:[SandboxExecution]=[]
    var active:Int {0}
    func submitCreate(configuration:SandboxConfiguration,beforePublish:()throws->Void)throws {
        // Disabled runtime cannot supply a create slot. Do not run the
        // journal callback or turn disabled work into an unresolved effect.
        throw AdmissionError.capacity
    }
    func submit(job:String,command:SandboxCommand) throws {
        guard results.count<2,!results.contains(where:{$0.job==job}) else {throw AdmissionError.capacity}
        results.append(SandboxExecution(job:job,result:.failure(.unavailable)))
    }
    func drain()->[SandboxExecution] {let value=results;results.removeAll();return value}
}
