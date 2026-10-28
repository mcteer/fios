import Foundation

// Resource operations use SandboxExecutor's shared lifecycle budget, not an
// independent subprocess pool. No task IPC accepts this protocol or commands.
protocol VMResourceReading:Sendable {
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample
    func releaseAfterVerifiedAbsence(id:String)
}
extension VMResourceReading {
    func releaseAfterVerifiedAbsence(id:String) {}
}
extension OwnedVMResourceReader:VMResourceReading {}

enum VMReadFailure:Error,Sendable {case unavailable}
struct VMReadResult:Sendable {
    let job:String
    let runtimeID:String
    let result:Result<VMKernelSample,VMReadFailure>
}
