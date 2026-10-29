import Foundation
import Darwin

func runWorkerRSSBreachTests()throws {
    guard let path=ProcessInfo.processInfo.environment["FIOS_PLATFORM_RSS_FIXTURE"] else {throw RuntimeError.invalid}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var cleanupProven=true
    defer {
        if cleanupProven {try? FileManager.default.removeItem(at:directory)}
        else {FileHandle.standardError.write(Data("OWNED_WORKER_FIXTURE_RETAINED\n".utf8))}
    }
    let journal=try Journal(directory:directory),id=UUID().uuidString.lowercased()
    let key="model:\(id):0",now=HostResources.nowMilliseconds()
    let sample=ResourceSample(sampledAt:now,physical:128<<30,available:64<<30,vmAvailable:nil,diskFree:100<<30,cpu:10,pressure:.normal,thermal:.nominal)
    var admission=AdmissionPolicy()
    try admission.reserveWorker(key:key,sample:sample,now:now)
    try journal.claim(job:id,attempt:0,model:"fixture/model")
    let nonce=try journal.planWorkerLaunch(job:id,attempt:0)
    let process=Process(),input=Pipe(),output=Pipe()
    process.executableURL=URL(fileURLWithPath:path);process.arguments=[]
    process.environment=["PATH":"/usr/bin:/bin","LANG":"C"]
    process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
    var cleanupGrant:WorkerGrant?
    cleanupProven=false
    defer {cleanupProven=finishOwnedWorkerFixture(process,grant:cleanupGrant)}
    try process.run()
    let captured=try WorkerGrant.capture(pid:process.processIdentifier);cleanupGrant=captured
    let started=Int64(ProcessInfo.processInfo.systemUptime*1000)
    let worker=try PrivateWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,journal:journal,job:id,attempt:0,started:started,capturedGrant:captured,launchNonce:nonce)
    let readiness=ProcessInfo.processInfo.systemUptime+5
    var resident:UInt64=0
    while ProcessInfo.processInfo.systemUptime<readiness {
        resident=(try? WorkerResources.residentBytes(pid:process.processIdentifier)) ?? 0
        if resident>512<<20 {break}
        Thread.sleep(forTimeInterval:0.005)
    }
    guard resident>512<<20 else {throw WorkerResourceError.unavailable}
    // Keep both local reservations until the real supervisor proves reap.
    try admission.reserveWorker(key:"other",sample:sample,now:now)
    do {try admission.reserveWorker(key:"third",sample:sample,now:now);throw RuntimeError.identity}
    catch AdmissionError.capacity {}
    let breach=ProcessInfo.processInfo.systemUptime,deadline=breach+2
    while !worker.reaped && ProcessInfo.processInfo.systemUptime<deadline {
        _=try worker.poll(now:Int64(ProcessInfo.processInfo.systemUptime*1000),authorized:true)
        if !worker.reaped {
            do {try admission.reserveWorker(key:"early",sample:sample,now:now);throw RuntimeError.identity}
            catch AdmissionError.capacity {}
        }
        Thread.sleep(forTimeInterval:0.005)
    }
    let elapsed=Int((ProcessInfo.processInfo.systemUptime-breach)*1000)
    guard worker.reaped,elapsed<2000,worker.memorySamples>=1,
          try journal.workerLaunchReaped(job:id,attempt:0),try journal.uncertainCount()==1 else {
        FileHandle.standardError.write(Data("WORKER_RSS_BREACH_NOT_REAPED\n".utf8));throw WorkerResourceError.invalid
    }
    guard elapsed<1750 else {
        FileHandle.standardError.write(Data("WORKER_RSS_CLEANUP_MARGIN_MISSED\n".utf8));throw WorkerResourceError.invalid
    }
    admission.releaseWorkerAfterReap(key:key)
    try admission.reserveWorker(key:"after-reap",sample:sample,now:now)
    print("PASS: actual owned worker RSS\(resident) bytes exceeds512MiB, TERM-ignoring child reaped in\(elapsed)ms, reservations retained until reap and native uncertainty preserved; no command/model/network")
}
