import Foundation
import CryptoKit

private final class SlotVMReader:VMResourceReading,@unchecked Sendable {
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var absent:[String]=[]
    var absenceProofs:[String] {lock.lock();defer {lock.unlock()};return absent}
    func releaseAfterVerifiedAbsence(id:String) {lock.lock();absent.append(id);lock.unlock()}
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        entered.signal();guard release.wait(timeout:.now()+2) == .success else {throw RuntimeError.deadline}
        return VMKernelSample(sampledAt:1000,total:16<<20,free:8<<20,bootHash:String(repeating:"f",count:64))
    }
}
func runSandboxExecutorTests() throws {
    // Fixed harmless test executable, not Docker: no daemon operation.
    let path="/usr/bin/false"
    let sha=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let runtime=try DockerRuntime(executable:VerifiedExecutable(path:path,sha256:sha),socket:"/fixture/not-a-runtime.sock")
    let image="sha256:"+String(repeating:"a",count:64)
    let executor=try SandboxExecutor(runtime:runtime,allowedImages:[image])
    let a=UUID().uuidString.lowercased(),b=UUID().uuidString.lowercased()
    let config=try SandboxConfiguration(job:a,nonce:String(repeating:"b",count:64),image:image,memory:512<<20,cpus:1)
    let unapproved=try SandboxConfiguration(job:b,nonce:String(repeating:"b",count:64),image:"sha256:"+String(repeating:"c",count:64),memory:512<<20,cpus:1)
    try executor.submit(job:a,command:.inspect(config,nil))
    try executor.submit(job:b,command:.create(unapproved))
    let third=UUID().uuidString.lowercased()
    let thirdConfig=try SandboxConfiguration(job:third,nonce:String(repeating:"b",count:64),image:image,memory:512<<20,cpus:1)
    do { try executor.submit(job:third,command:.inspect(thirdConfig,nil));fatalError("Runtime executor exceeded two total slots") } catch AdmissionError.capacity {}
    do { try executor.submit(job:third,command:.stop(String(repeating:"f",count:64)));fatalError("Unbound foreign ID reached stop") } catch SandboxExecutionFailure.identity {}
    var results:[SandboxExecution]=[]
    let deadline=ProcessInfo.processInfo.systemUptime+3
    while results.count<2 && ProcessInfo.processInfo.systemUptime<deadline {
        results+=executor.drain();Thread.sleep(forTimeInterval:0.01)
    }
    guard results.count==2,results.contains(where:{if case .failure(.unavailable)=$0.result {return true};return false}),
          results.contains(where:{if case .failure(.unapprovedImage)=$0.result {return true};return false}) else { fatalError("CLI failure became absence or unapproved image reached daemon") }
    let reader=SlotVMReader(),shared=try SandboxExecutor(runtime:runtime,allowedImages:[image],resourceReader:reader)
    let id=String(repeating:"d",count:64)
    try shared.submitResources(configuration:config,id:id,leaseUntil:10000)
    guard reader.entered.wait(timeout:.now()+1) == .success else {fatalError("Shared VM reader did not start")}
    try shared.submit(job:third,command:.inspect(thirdConfig,nil))
    do {try shared.submit(job:b,command:.inspect(unapproved,nil));fatalError("VM reader escaped combined two-slot budget")}catch AdmissionError.capacity {}
    var lifecycle:[SandboxExecution]=[]
    let sharedDeadline=ProcessInfo.processInfo.systemUptime+2
    while lifecycle.isEmpty && ProcessInfo.processInfo.systemUptime<sharedDeadline {lifecycle=shared.drain();Thread.sleep(forTimeInterval:0.001)}
    guard lifecycle.count==1,shared.drainResources().isEmpty else {fatalError("VM/lifecycle channels mixed")}
    reader.release.signal()
    while shared.active>0 && ProcessInfo.processInfo.systemUptime<sharedDeadline {Thread.sleep(forTimeInterval:0.001)}
    guard shared.drain().isEmpty else {fatalError("VM sample consumed as lifecycle proof")}
    do {try shared.submitResources(configuration:config,id:id,leaseUntil:10000);fatalError("Retained resource result bypassed slot/once-only bound")}catch AdmissionError.capacity {}
    let samples=shared.drainResources()
    guard samples.count==1,samples[0].job==a,samples[0].runtimeID==id,shared.drainResources().isEmpty else {fatalError("Shared VM result lost/cross-correlated")}
    guard reader.absenceProofs.isEmpty else {fatalError("Failed CLI query cleared resource uncertainty")}
    let truePath="/usr/bin/true",trueSHA=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:truePath))).map {String(format:"%02x",$0)}.joined()
    let absentRuntime=try DockerRuntime(executable:VerifiedExecutable(path:truePath,sha256:trueSHA),socket:"/fixture/not-a-runtime.sock")
    let absenceExecutor=try SandboxExecutor(runtime:absentRuntime,allowedImages:[image],resourceReader:reader)
    try absenceExecutor.submit(job:a,command:.inspect(config,id))
    let absenceDeadline=ProcessInfo.processInfo.systemUptime+2
    var absence:[SandboxExecution]=[]
    while absence.isEmpty && ProcessInfo.processInfo.systemUptime<absenceDeadline {absence=absenceExecutor.drain();Thread.sleep(forTimeInterval:0.001)}
    guard absence.count==1,reader.absenceProofs==[id] else {fatalError("Exact-ID absence proof did not release resource fence")}
    print("PASS: fixed asynchronous runtime executor, combined two-slot lifecycle/VM budget, disjoint once-only result channels, immutable images and CLI failure is not absence (no Docker daemon)")
}
