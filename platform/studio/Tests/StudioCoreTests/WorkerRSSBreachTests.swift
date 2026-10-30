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
    process.environment=["PATH":"/usr/bin:/bin","LANG":"C","FIOS_PLATFORM_RSS_TERM_EXIT":"1"]
    process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
    var cleanupGrant:WorkerGrant?
    cleanupProven=false
    defer {cleanupProven=finishOwnedWorkerFixture(process,grant:cleanupGrant)}
    try process.run()
    let captured=try WorkerGrant.capture(pid:process.processIdentifier);cleanupGrant=captured
    let started=Int64(ProcessInfo.processInfo.systemUptime*1000)
    let readiness=ProcessInfo.processInfo.systemUptime+5
    var resident:UInt64=0,peakResident:UInt64=0,samples=0,unavailable=0
    while ProcessInfo.processInfo.systemUptime<readiness {
        if let value=try? WorkerResources.residentBytes(pid:process.processIdentifier) {resident=value;samples+=1}
        else {resident=0;unavailable+=1}
        peakResident=max(peakResident,resident)
        if resident>512<<20 {break}
        Thread.sleep(forTimeInterval:0.005)
    }
    guard resident>512<<20 else {
        let live=process.isRunning
        let diagnostics:[String:Any]=["phase":"worker_rss_setup","peak_rss":peakResident,"last_rss":resident,
            "samples":samples,"unavailable_samples":unavailable,"running":live,
            "exit_status":live ? NSNull():process.terminationStatus as Any]
        FileHandle.standardError.write(try JSONSerialization.data(withJSONObject:diagnostics,options:.sortedKeys))
        FileHandle.standardError.write(Data("\nWORKER_RSS_SETUP_NOT_OVERSIZED\n".utf8))
        throw WorkerResourceError.unavailable
    }
    // Keep both local reservations until the real supervisor proves reap.
    try admission.reserveWorker(key:"other",sample:sample,now:now)
    do {try admission.reserveWorker(key:"third",sample:sample,now:now);throw RuntimeError.identity}
    catch AdmissionError.capacity {}
    let breach=ProcessInfo.processInfo.systemUptime,deadline=breach+2
    let worker=try PrivateWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,journal:journal,job:id,attempt:0,started:started,readyAt:Int64(ProcessInfo.processInfo.systemUptime*1000),capturedGrant:captured,launchNonce:nonce)
    var polls=0,maxPollMilliseconds=0
    while !worker.reaped && ProcessInfo.processInfo.systemUptime<deadline {
        let before=ProcessInfo.processInfo.systemUptime
        _=try worker.poll(now:Int64(before*1000),authorized:true)
        maxPollMilliseconds=max(maxPollMilliseconds,Int((ProcessInfo.processInfo.systemUptime-before)*1000));polls+=1
        guard polls != 1 || worker.memorySamples==1 else {
            FileHandle.standardError.write(Data("FIO_WORKER_RSS_INITIAL_SAMPLE_MISSING\n".utf8));throw WorkerResourceError.invalid
        }
        if !worker.reaped {
            do {try admission.reserveWorker(key:"early",sample:sample,now:now);throw RuntimeError.identity}
            catch AdmissionError.capacity {}
        }
        Thread.sleep(forTimeInterval:0.005)
    }
    let elapsed=Int((ProcessInfo.processInfo.systemUptime-breach)*1000)
    let marked=try journal.workerLaunchReaped(job:id,attempt:0),uncertain=try journal.uncertainCount()
    guard worker.reaped,elapsed<2000,worker.memorySamples>=1,marked,uncertain==1 else {
        let running=process.isRunning
        let diagnostics:[String:Any]=["phase":"worker_rss_reap","reaped":worker.reaped,"elapsed_ms":elapsed,
            "samples":worker.memorySamples,"polls":polls,"max_poll_ms":maxPollMilliseconds,
            "running":running,"output_eof":worker.outputEOFObserved,"local_absence":(try? captured.provenGone()) ?? false,
            "durable_reaped":marked,"uncertain":uncertain,"exit_status":running ? NSNull():process.terminationStatus as Any]
        FileHandle.standardError.write(try JSONSerialization.data(withJSONObject:diagnostics,options:.sortedKeys))
        FileHandle.standardError.write(Data("\nWORKER_RSS_BREACH_NOT_REAPED\n".utf8));throw WorkerResourceError.invalid
    }
    guard process.terminationReason == .uncaughtSignal,process.terminationStatus==SIGKILL else {
        FileHandle.standardError.write(Data("WORKER_RSS_HARD_LIMIT_NOT_KILLED\n".utf8));throw WorkerResourceError.invalid
    }
    guard elapsed<1750 else {
        FileHandle.standardError.write(Data("WORKER_RSS_CLEANUP_MARGIN_MISSED\n".utf8));throw WorkerResourceError.invalid
    }
    admission.releaseWorkerAfterReap(key:key)
    try admission.reserveWorker(key:"after-reap",sample:sample,now:now)
    print("PASS: actual owned worker RSS\(resident) bytes exceeds512MiB, hard-limit child reaped in\(elapsed)ms, reservations retained until reap and native uncertainty preserved; no command/model/network")
}
