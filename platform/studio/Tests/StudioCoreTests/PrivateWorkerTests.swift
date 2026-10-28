import Foundation
import CryptoKit

func runPrivateWorkerTests() throws {
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try Journal(directory:directory)
    let older=UUID().uuidString.lowercased()
    try journal.claim(job:older,attempt:0,model:"fixture/model");try journal.markUncertain(job:older,attempt:0)
    func launch(job:String,mode:String="complete") throws -> PrivateWorker {
        try journal.claim(job:job,attempt:0,model:"fixture/model")
        _=try journal.planWorkerLaunch(job:job,attempt:0)
        let process=Process(),input=Pipe(),output=Pipe()
        process.executableURL=root.appendingPathComponent(".venv/bin/python")
        process.arguments=["-I","-B",root.appendingPathComponent("tests/fixtures/platform/mock-worker.py").path]
        process.environment=["PATH":"/usr/bin:/bin","LANG":"C","MLX_BASE_URL":"http://127.0.0.1:1/v1","FIOS_WEB_SEARCH":"off","PYDANTIC_AI_NO_BANNER":"1","FIOS_PLATFORM_FIXTURE_DELAY":"1.25","FIOS_PLATFORM_FIXTURE_MODE":mode]
        process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        try process.run()
        return try PrivateWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,journal:journal,job:job,attempt:0,started:Int64(ProcessInfo.processInfo.systemUptime*1000))
    }
    let job=UUID().uuidString.lowercased(),epoch=UUID().uuidString.lowercased()
    let worker=try launch(job:job)
    guard let binding=try journal.workerGrants().first else { fatalError("Missing durable worker binding") }
    do { try journal.bindWorker(job:job,attempt:0,grant:binding.grant);fatalError("Duplicate private worker grant accepted") } catch JournalError.conflict {}
    do { try journal.recordWorkerGone(job:job,attempt:0,grant:binding.grant);fatalError("Live private worker released") } catch JournalError.conflict {}
    let hash=SHA256.hash(data:Data("http://127.0.0.1:1/v1".utf8)).map { String(format:"%02x",$0) }.joined()
    func send(_ worker:PrivateWorker,id:String) throws {
        let now=HostResources.nowMilliseconds()
        let command=try JSONSerialization.data(withJSONObject:["v":1,"type":"run","job_id":id,"attempt":0,"model":"fixture/model","epoch":epoch,"endpoint_hash":hash,"expires_at":now+5000,"context":[["role":"user","content":"fixture only"]]])
        try worker.enqueue(command,expectedModel:"fixture/model",endpointHash:hash,epoch:epoch,now:now)
    }
    try send(worker,id:job)
    let end=ProcessInfo.processInfo.systemUptime+10
    var complete=false,text=""
    while !worker.reaped && ProcessInfo.processInfo.systemUptime<end {
        for event in try worker.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:true) {
            if case .complete=event { complete=true }
            if case .text(_,let content)=event { text+=content }
        }
        Thread.sleep(forTimeInterval:0.01)
    }
    guard worker.reaped,worker.memorySamples>=1,complete,text=="MOCK_ONLY",try journal.unresolvedCount()==1,try journal.hasClaim(job:older,attempt:0) else { fatalError("Private child completion/reap/correlated ownership failed") }
    do { try send(worker,id:job);fatalError("Child permission replay accepted") } catch ControlError.invalid_request {}
    let failedID=UUID().uuidString.lowercased(),failed=try launch(job:failedID,mode:"missing-model")
    try send(failed,id:failedID)
    let unavailableEnd=ProcessInfo.processInfo.systemUptime+10
    while !failed.reaped && ProcessInfo.processInfo.systemUptime<unavailableEnd {
        _=try failed.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:true)
        Thread.sleep(forTimeInterval:0.01)
    }
    guard failed.reaped,try journal.unresolvedCount()==1,try journal.hasClaim(job:older,attempt:0) else { fatalError("Trusted zero-POST proof did not release only current ownership") }
    let cancelledID=UUID().uuidString.lowercased(),cancelled=try launch(job:cancelledID)
    try cancelled.cancel(now:Int64(ProcessInfo.processInfo.systemUptime*1000))
    let stop=ProcessInfo.processInfo.systemUptime+3
    while !cancelled.reaped && ProcessInfo.processInfo.systemUptime<stop {
        do { _=try cancelled.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:false) }
        catch ModelProtocolError.invalid {} // EOF before command produces an unscoped fixed child error.
        Thread.sleep(forTimeInterval:0.01)
    }
    guard cancelled.reaped,try journal.workerGrants().isEmpty,try journal.unresolvedCount()==2,try journal.uncertainCount()==2 else { fatalError("Cancellation released native uncertainty or failed to reap") }
    print("PASS: actual private installed-Pydantic child, bounded pipes, completion-specific journal release, cancellation/reaping and older uncertainty retention (mock transport only)")
}
