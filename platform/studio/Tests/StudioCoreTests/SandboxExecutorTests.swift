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
    let now=Date(timeIntervalSince1970:1704067200) // 2024-01-01T00:00:00Z
    for (running,stamp,expected):(Bool,String,Int?) in [
        (false,"0001-01-01T00:00:00Z",nil),
        (false,"2023-02-29T00:00:00Z",nil),
        (false,"2024-01-01T00:00:01.001Z",nil),
        (false,"2024-01-01T00:00:01.000000001Z",nil),
        (false,"2024-01-01T00:00:01Z",0),
        (false,"2023-12-31T23:59:59.999999999Z",0),
        (true,"2024-01-01T00:00:00Z",nil),
    ] {
        guard SandboxExitStatus.recorded(running:running,code:0,finishedAt:stamp,now:now)==expected else {
            fatalError("Sandbox exit proof accepted a sentinel, invalid or future stamp, or lost a valid boundary: \(stamp)")
        }
    }
    // Fixed harmless test executable, not Docker: no daemon operation.
    let path="/usr/bin/false"
    let sha=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let runtime=try DockerRuntime(executable:VerifiedExecutable(path:path,sha256:sha),socket:"/fixture/not-a-runtime.sock")
    let image="sha256:"+String(repeating:"a",count:64)
    let executor=try SandboxExecutor(runtime:runtime,allowedImages:[image])
    let a=UUID().uuidString.lowercased(),b=UUID().uuidString.lowercased()
    let config=try SandboxConfiguration(job:a,nonce:String(repeating:"b",count:64),image:image,memory:512<<20,cpus:1)
    let unapproved=try SandboxConfiguration(job:b,nonce:String(repeating:"b",count:64),image:"sha256:"+String(repeating:"c",count:64),memory:512<<20,cpus:1)
    do { try executor.submit(job:a,command:.create(config));fatalError("Create was published without the prepublication callback") } catch RuntimeError.invalid {}
    do { try executor.submitCreate(configuration:unapproved,beforePublish:{fatalError("Unapproved image reached prepublication callback")});fatalError("Unapproved image reserved a create slot") } catch SandboxExecutionFailure.unapprovedImage {}
    try executor.submit(job:a,command:.inspect(config,nil))
    try executor.submit(job:b,command:.inspect(unapproved,nil))
    let third=UUID().uuidString.lowercased()
    let thirdConfig=try SandboxConfiguration(job:third,nonce:String(repeating:"b",count:64),image:image,memory:512<<20,cpus:1)
    do { try executor.submit(job:third,command:.inspect(thirdConfig,nil));fatalError("Runtime executor exceeded two total slots") } catch AdmissionError.capacity {}
    do { try executor.submit(job:third,command:.stop(String(repeating:"f",count:64)));fatalError("Unbound foreign ID reached stop") } catch SandboxExecutionFailure.identity {}
    var results:[SandboxExecution]=[]
    let deadline=ProcessInfo.processInfo.systemUptime+3
    while results.count<2 && ProcessInfo.processInfo.systemUptime<deadline {
        results+=executor.drain();Thread.sleep(forTimeInterval:0.01)
    }
    guard results.count==2,Set(results.map(\.job))==Set([a,b]),
          results.allSatisfy({if case .failure(.unavailable)=$0.result {return true};return false}) else {fatalError("CLI failure became absence or operation results crossed jobs")}
    var commits=0
    try executor.submitCreate(configuration:config,beforePublish:{
        guard executor.active==1,executor.drain().isEmpty else {fatalError("Create published before prepublication callback")}
        commits+=1
    })
    var createResults:[SandboxExecution]=[]
    let createDeadline=ProcessInfo.processInfo.systemUptime+3
    while createResults.isEmpty && ProcessInfo.processInfo.systemUptime<createDeadline {
        createResults=executor.drain();Thread.sleep(forTimeInterval:0.001)
    }
    guard commits==1,createResults.count==1,createResults[0].job==a,
          case .failure(.unavailable)=createResults[0].result,executor.drain().isEmpty else {
        fatalError("Dedicated create path did not commit once and return its exact result")
    }
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
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-exit-proof-"+a)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    for (stamp,expected):(String,Int?) in [("0001-01-01T00:00:00Z",nil),("2024-01-01T00:00:00.000000001Z",0)] {
        let inspect:[[String:Any]]=[["Id":id,"Name":"/"+config.name,"Image":image,
            "Config":["Labels":["fios.platform.job":a,"fios.platform.nonce":config.nonce]],
            "State":["Running":false,"ExitCode":0,"OOMKilled":false,"FinishedAt":stamp]]]
        let json=String(decoding:try JSONSerialization.data(withJSONObject:inspect),as:UTF8.self)
        let cli=directory.appendingPathComponent("mock-runtime")
        let script=Data("#!/bin/sh\ncase \"$3\" in container) printf '%s\\n' '\(id)';; inspect) printf '%s' '\(json)';; *) exit 1;; esac\n".utf8)
        try script.write(to:cli)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:cli.path)
        let digest=SHA256.hash(data:script).map{String(format:"%02x",$0)}.joined()
        let mock=try DockerRuntime(executable:VerifiedExecutable(path:cli.path,sha256:digest),socket:"/fixture/not-a-runtime.sock")
        let subject=try SandboxExecutor(runtime:mock,allowedImages:[image])
        try subject.submit(job:a,command:.inspect(config,id))
        let end=ProcessInfo.processInfo.systemUptime+3
        var replies:[SandboxExecution]=[]
        while replies.isEmpty && ProcessInfo.processInfo.systemUptime<end {replies=subject.drain();Thread.sleep(forTimeInterval:0.001)}
        guard replies.count==1,case .success(.observed(.present(let exactID,_,_,_,false),let proof,false))=replies[0].result,
              exactID==id,proof==expected else {fatalError("Mock runtime inspect confused stopped presence and exit proof")}
    }
    print("PASS: fixed asynchronous runtime executor, combined two-slot lifecycle/VM budget, disjoint once-only result channels, immutable images and CLI failure is not absence (no Docker daemon)")
}
