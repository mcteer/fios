import Foundation
import CryptoKit

private final class HeldVMReader:VMResourceReading,@unchecked Sendable {
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        entered.signal();guard release.wait(timeout:.now()+2) == .success else {throw RuntimeError.deadline}
        return VMKernelSample(sampledAt:1000,total:16<<20,free:8<<20,bootHash:String(repeating:"a",count:64))
    }
}
func runAsyncVMResourceTests() throws {
    let path="/usr/bin/false",digest=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let runtime=try DockerRuntime(executable:VerifiedExecutable(path:path,sha256:digest),socket:"/fixture/not-a-runtime.sock")
    let image="sha256:"+String(repeating:"c",count:64),reader=HeldVMReader()
    let queue=try SandboxExecutor(runtime:runtime,allowedImages:[image],resourceReader:reader)
    let configuration=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"b",count:64),image:image,memory:512<<20,cpus:1),id=String(repeating:"d",count:64)
    let began=ProcessInfo.processInfo.systemUptime
    try queue.submitResources(configuration:configuration,id:id,leaseUntil:10000)
    guard ProcessInfo.processInfo.systemUptime-began<0.1,reader.entered.wait(timeout:.now()+1) == .success,queue.drainResources().isEmpty else {fatalError("VM read blocked heartbeat/result drain")}
    do {try queue.submitResources(configuration:configuration,id:id,leaseUntil:10000);fatalError("Concurrent read into same target accepted")}catch AdmissionError.capacity {}
    reader.release.signal()
    let deadline=ProcessInfo.processInfo.systemUptime+1
    var results:[VMReadResult]=[]
    while results.isEmpty && ProcessInfo.processInfo.systemUptime<deadline {results=queue.drainResources();Thread.sleep(forTimeInterval:0.001)}
    guard results.count==1,let result=results.first,result.job==configuration.job,result.runtimeID==id,case .success(let sample)=result.result,sample.free==8<<20,queue.drainResources().isEmpty,queue.drain().isEmpty else {fatalError("VM result correlation/bounds failed")}
    print("PASS: VM work stays off-loop in shared runtime budget, duplicate target refused and correlated finite resource result drains exactly once")
}
