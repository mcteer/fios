import Foundation
import Darwin

func runAsyncWorkerStartTests()throws {
    let gate=DispatchSemaphore(value:0)
    let began=ProcessInfo.processInfo.systemUptime
    let operation=PendingPythonWorker {cancelled in
        _=gate.wait(timeout:.now()+2)
        return .failure(cancelled() ? .cancelled:.unavailable)
    }
    guard ProcessInfo.processInfo.systemUptime-began<0.25,operation.take()==nil else {
        FileHandle.standardError.write(Data("WORKER_START_BLOCKED_CONTROL_LOOP\n".utf8));throw JournalError.conflict
    }
    operation.cancel();gate.signal()
    let end=ProcessInfo.processInfo.systemUptime+2
    var received=false
    while ProcessInfo.processInfo.systemUptime<end {
        if let result=operation.take() {
            guard case .failure(.cancelled)=result else {throw JournalError.conflict}
            received=true;break
        }
        Thread.sleep(forTimeInterval:0.005)
    }
    guard received,operation.take()==nil else {throw JournalError.conflict}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),id=UUID().uuidString.lowercased()
    try journal.claim(job:id,attempt:0,model:"fixture/model")
    let nonce=try journal.planWorkerLaunch(job:id,attempt:0)
    try journal.markUncertain(job:id,attempt:0)
    do {
        try journal.recordWorkerNotStarted(job:id,attempt:0,nonce:UUID().uuidString.lowercased())
        throw RuntimeError.identity
    }catch JournalError.conflict {}
    guard try journal.activeLaunchCount()==1,try journal.uncertainCount()==1 else {throw JournalError.conflict}
    try journal.recordWorkerNotStarted(job:id,attempt:0,nonce:nonce)
    guard try journal.activeLaunchCount()==0,try journal.workerLaunchReaped(job:id,attempt:0),
          try journal.uncertainCount()==1,try journal.requestCount(job:id)==1 else {throw JournalError.conflict}
    do {
        try journal.recordWorkerNotStarted(job:id,attempt:0,nonce:nonce)
        throw RuntimeError.identity
    }catch JournalError.conflict {}
    try runLateCancelledWorkerBindingTest()
    print("PASS: off-loop bounded worker-start result, responsive poll/cancel and once-only ownership transfer; no process/model request in gate fixture")
}

private func runLateCancelledWorkerBindingTest()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var cleanupProven=true
    defer {
        if cleanupProven {try? FileManager.default.removeItem(at:directory)}
        else {FileHandle.standardError.write(Data("OWNED_WORKER_FIXTURE_RETAINED\n".utf8))}
    }
    let journal=try Journal(directory:directory),id=UUID().uuidString.lowercased(),epoch=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),managerEpoch:epoch,nativeEpoch:"fixture-native",canonicalModel:"fixture/model",nativeModel:"fixture/model",sequence:1,sampledAt:1000)
    try journal.claim(job:id,attempt:0,model:"fixture/model",scope:scope)
    let nonce=try journal.planWorkerLaunch(job:id,attempt:0)
    let process=Process(),input=Pipe(),output=Pipe()
    process.executableURL=URL(fileURLWithPath:"/bin/sleep");process.arguments=["30"]
    process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
    var cleanupGrant:WorkerGrant?
    cleanupProven=false
    defer {cleanupProven=finishOwnedWorkerFixture(process,grant:cleanupGrant)}
    try process.run()
    let grant=try WorkerGrant.capture(pid:process.processIdentifier);cleanupGrant=grant
    try journal.markUncertain(job:id,attempt:0)
    do {
        try journal.bindWorker(job:id,attempt:0,grant:grant,nonce:UUID().uuidString.lowercased())
        throw RuntimeError.identity
    }catch JournalError.conflict {}
    let clock=Int64(ProcessInfo.processInfo.systemUptime*1000)
    let transport=StartedPythonWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,grant:grant)
    let worker=try transport.bind(journal:journal,key:WorkerLaunchKey(job:id,attempt:0),nonce:nonce,started:clock,readyAt:clock)
    let command=try JSONSerialization.data(withJSONObject:["v":1,"type":"run","job_id":id,"attempt":0,"model":"fixture/model","epoch":epoch,"endpoint_hash":scope.endpointHash,"expires_at":6000,"context":[["role":"user","content":"fixture only"]]])
    do {
        try worker.enqueue(command,expectedModel:"fixture/model",endpointHash:scope.endpointHash,epoch:epoch,now:1000)
        throw RuntimeError.identity
    }catch ControlError.invalid_request {}
    try worker.cancel(now:clock)
    let end=ProcessInfo.processInfo.systemUptime+2
    while !worker.reaped && ProcessInfo.processInfo.systemUptime<end {
        _=try worker.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:false)
        Thread.sleep(forTimeInterval:0.005)
    }
    guard worker.reaped,try journal.workerLaunchReaped(job:id,attempt:0),try journal.uncertainCount()==1,
          try journal.requestCount(job:id)==1 else {throw JournalError.conflict}
}
