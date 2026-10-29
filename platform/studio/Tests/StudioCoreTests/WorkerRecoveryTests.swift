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

func runLateWorkerRecoveryTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory)
    var admission=AdmissionPolicy()
    // This reaper already exists when a later factory start fails.
    let recovery=try WorkerReconciler(journal:journal,admission:&admission)
    let unknown=WorkerLaunchKey(job:UUID().uuidString.lowercased(),attempt:0)
    let missing=try ModelBroker.reconcileFailedLaunches([unknown],journal:journal,admission:&admission)
    guard missing==[unknown] else {FileHandle.standardError.write(Data("MISSING_WORKER_HISTORY_RELEASED_HOLD\n".utf8));throw JournalError.conflict}
    let failed=WorkerLaunchKey(job:UUID().uuidString.lowercased(),attempt:0)
    let healthy=WorkerLaunchKey(job:UUID().uuidString.lowercased(),attempt:0)
    let failedProcess=Process(),healthyProcess=Process()
    defer {for child in [failedProcess,healthyProcess] {if child.isRunning {child.terminate()};child.waitUntilExit()}}
    for (key,child) in [(failed,failedProcess),(healthy,healthyProcess)] {
        try journal.claim(job:key.job,attempt:key.attempt,model:"fixture/model")
        _=try journal.planWorkerLaunch(job:key.job,attempt:key.attempt)
        child.executableURL=URL(fileURLWithPath:"/bin/sleep");child.arguments=["30"]
        child.standardInput=FileHandle.nullDevice;child.standardOutput=FileHandle.nullDevice;child.standardError=FileHandle.nullDevice
        try child.run()
        try journal.bindWorker(job:key.job,attempt:key.attempt,grant:WorkerGrant.capture(pid:child.processIdentifier))
        try admission.restoreWorker(key:key.reservationKey)
    }
    try journal.markUncertain(job:failed.job,attempt:failed.attempt)
    var holds:Set<WorkerLaunchKey>=[failed]
    let end=ProcessInfo.processInfo.systemUptime+2
    while !holds.isEmpty && ProcessInfo.processInfo.systemUptime<end {
        try recovery.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&admission,failedLaunches:holds)
        holds=try ModelBroker.reconcileFailedLaunches(holds,journal:journal,admission:&admission)
        guard healthyProcess.isRunning else {fatalError("Late reaper signalled a healthy current worker")}
        Thread.sleep(forTimeInterval:0.01)
    }
    guard holds.isEmpty,try journal.workerLaunchReaped(job:failed.job,attempt:failed.attempt),
          try journal.activeLaunchCount()==1,try journal.unresolvedCount()==2,try journal.uncertainCount()==1 else {
        fatalError("Late bound worker failure was not reaped without changing native ownership")
    }
    let sample=ResourceSample(sampledAt:10000,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    try admission.reserveWorker(key:"replacement",sample:sample,now:10000)
    do {try admission.reserveWorker(key:"excess",sample:sample,now:10000);fatalError("Healthy worker reservation was released")}catch AdmissionError.capacity {}
    let unboundDirectory=directory.appendingPathComponent("separate-unbound-fixture")
    let unboundJournal=try Journal(directory:unboundDirectory)
    var unboundAdmission=AdmissionPolicy()
    let unboundRecovery=try WorkerReconciler(journal:unboundJournal,admission:&unboundAdmission)
    let unbound=WorkerLaunchKey(job:UUID().uuidString.lowercased(),attempt:0)
    try unboundJournal.claim(job:unbound.job,attempt:0,model:"fixture/model")
    _=try unboundJournal.planWorkerLaunch(job:unbound.job,attempt:0)
    try unboundJournal.markUncertain(job:unbound.job,attempt:0)
    try unboundRecovery.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),admission:&unboundAdmission,failedLaunches:[unbound])
    guard unboundRecovery.degraded,unboundRecovery.pending==1,
          try ModelBroker.reconcileFailedLaunches([unbound],journal:unboundJournal,admission:&unboundAdmission)==[unbound],
          healthyProcess.isRunning,try unboundJournal.uncertainCount()==1 else {fatalError("Unbound launch uncertainty became local/native absence")}
    print("PASS: same-manager failed bound-worker reap, exact durable hold release, healthy-worker preservation and unbound/missing-history retention; native uncertainty unchanged")
}
