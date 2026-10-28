import Foundation
import Darwin

func runWorkerRecoveryTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    var journal:Journal?=try Journal(directory:directory)
    let id=UUID().uuidString.lowercased()
    try journal!.claim(job:id,attempt:0,model:"fixture/model")
    _=try journal!.planWorkerLaunch(job:id,attempt:0)
    let owned=Process(),foreign=Process()
    for process in [owned,foreign] {
        process.executableURL=URL(fileURLWithPath:"/bin/sleep");process.arguments=["30"]
        process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        try process.run()
    }
    defer {
        for process in [owned,foreign] {
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            process.waitUntilExit()
        }
    }
    try journal!.bindWorker(job:id,attempt:0,grant:WorkerGrant.capture(pid:owned.processIdentifier))
    journal=nil;journal=try Journal(directory:directory)
    var admission=AdmissionPolicy()
    let recovery=try WorkerReconciler(journal:journal!,admission:&admission)
    let start=ProcessInfo.processInfo.systemUptime
    while recovery.pending>0 && ProcessInfo.processInfo.systemUptime-start<2 {
        try recovery.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission)
        Thread.sleep(forTimeInterval:0.01)
    }
    guard recovery.pending==0,!recovery.degraded,foreign.isRunning,
          try journal!.activeLaunchCount()==0,try journal!.unresolvedCount()==1,try journal!.uncertainCount()==1 else {
        fatalError("Bound-child recovery touched foreign work or cleared native uncertainty")
    }
    let sample=ResourceSample(sampledAt:10_000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    try admission.reserveWorker(key:"one",sample:sample,now:10_000)
    try admission.reserveWorker(key:"two",sample:sample,now:10_000)
    let blocked=UUID().uuidString.lowercased(),process=Process(),input=Pipe(),output=Pipe()
    try journal!.claim(job:blocked,attempt:0,model:"fixture/model")
    _=try journal!.planWorkerLaunch(job:blocked,attempt:0)
    process.executableURL=URL(fileURLWithPath:"/bin/sleep");process.arguments=["30"]
    process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
    try process.run()
    let worker=try PrivateWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,journal:journal!,job:blocked,attempt:0,started:0)
    let epoch=UUID().uuidString.lowercased()
    let command=try JSONSerialization.data(withJSONObject:["v":1,"type":"run","job_id":blocked,"attempt":0,"model":"fixture/model","epoch":epoch,"endpoint_hash":String(repeating:"a",count:64),"expires_at":5000,"context":[["role":"user","content":String(repeating:"x",count:100000)]]])
    try worker.enqueue(command,expectedModel:"fixture/model",endpointHash:String(repeating:"a",count:64),epoch:epoch,now:0)
    // Fake only monotonic clock advancement, not native pressure/workloads.
    // This child intentionally never consumes the filled input pipe.
    for tick in stride(from:0,through:11500,by:500) where !worker.reaped {
        _=try worker.poll(now:Int64(tick),authorized:true)
        Thread.sleep(forTimeInterval:0.01)
    }
    guard worker.reaped,try journal!.activeLaunchCount()==0,try journal!.unresolvedCount()==2,
          try journal!.uncertainCount()==2,foreign.isRunning else { fatalError("Blocked private command was not finitely revoked/reaped with uncertainty preserved") }
    print("PASS: exact orphan reap/foreign refusal, durable local slots and finite blocked-pipe deadline with native uncertainty preserved")
}
