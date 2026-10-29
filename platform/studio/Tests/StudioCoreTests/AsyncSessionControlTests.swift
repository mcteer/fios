import Foundation

func runAsyncSessionControlTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),hash=String(repeating:"a",count:64),pins:[ManagedService:String]=[.mlx:hash,.orbstack:hash]
    let recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    let absent=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:1000)
    guard let request=try recovery.next(service:.mlx,desired:.running,observation:absent,now:1000,tick:1000) else {fatalError("Missing sender launch fixture")}
    // There is intentionally no socket/listener. Failure must stay unknown;
    // this fixture never connects to a native helper or launches an app.
    let peer=NativeControlPeer(pid:2,start:1,executable:try VerifiedExecutable(path:"/usr/bin/true",sha256:hash))
    let client=try SessionControlClient(directory:directory,peer:peer,instance:UUID().uuidString.lowercased(),profile:request.command.profileHash,approvedHashes:pins)
    let queue=AsyncSessionControl(client:client)
    try queue.submit(request)
    do {try queue.submit(request);fatalError("Session sender queued another exchange")}catch RuntimeError.capacity {}
    func result()throws->SessionRecoveryResult {
        let deadline=ProcessInfo.processInfo.systemUptime+3
        while ProcessInfo.processInfo.systemUptime<deadline {
            if let result=queue.poll() {return result}
            Thread.sleep(forTimeInterval:0.005)
        }
        throw RuntimeError.deadline
    }
    let first=try result()
    guard first.request.command.id==request.command.id else {fatalError("Sender lost receipt correlation")}
    switch first.value {case .failure(.unavailable):break;case .success:fatalError("Missing transport became non-dispatch proof")}
    do {try queue.submit(request);fatalError("Consumed launch token was retried after transport failure")}catch RuntimeError.invalid {}
    guard let lookup=try recovery.next(service:.mlx,desired:.stopped,observation:nil,now:2000,tick:2000),lookup.operation == .lookup else {fatalError("Transport failure refunded a dispatch")}
    try queue.submit(lookup)
    let second=try result()
    guard second.request.operation == .lookup,second.request.command.id==request.command.id else {fatalError("Reconciliation was promoted back to launch")}
    switch second.value {case .failure(.unavailable):break;case .success:fatalError("Missing lookup transport manufactured a proof")}
    print("PASS: one off-loop session exchange/result, finite unavailable transport, correlated receipt, one-use launch token and lookup-only recovery without native actions")
}
