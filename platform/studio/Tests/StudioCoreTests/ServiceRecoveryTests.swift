import Foundation

func runServiceRecoveryTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let hash=String(repeating:"a",count:64),pins:[ManagedService:String]=[.mlx:hash,.orbstack:hash]
    let journal=try Journal(directory:directory)
    func absent(_ now:Int64,session:Bool=true,credentials:Bool=true)->ServiceObservation {
        ServiceObservation(identity:nil,responding:false,sessionReady:session,credentialsReady:credentials,
            nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:now)
    }
    var recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard try recovery.plan(service:.mlx,desired:.running,observation:nil,now:1000,tick:1000)==nil,
          try recovery.plan(service:.mlx,desired:.maintenance,observation:absent(1000),now:1000,tick:1000)==nil,
          try recovery.plan(service:.mlx,desired:.stopped,observation:absent(1000),now:1000,tick:1000)==nil,
          try recovery.plan(service:.mlx,desired:.running,observation:absent(1000,session:false),now:1000,tick:1000)==nil,
          try recovery.plan(service:.mlx,desired:.running,observation:absent(1000,credentials:false),now:1000,tick:1000)==nil else {fatalError("Recovery bypassed intent/source/session/credential gate")}
    guard let first=try recovery.plan(service:.mlx,desired:.running,observation:absent(1000),now:1000,tick:1000) else {fatalError("Proven absent service was not reserved")}
    guard try recovery.plan(service:.mlx,desired:.running,observation:absent(2000),now:2000,tick:2000)==nil else {fatalError("Pending launch replayed")}
    // New controller restores durable intent while the same single writer is
    // held. Fresh absence and elapsed time cannot retire unknown dispatch.
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard try recovery.plan(service:.mlx,desired:.running,observation:absent(700000),now:700000,tick:700000)==nil else {fatalError("Restart/age cleared uncertain launch")}
    do {try recovery.notSent(service:.mlx,id:UUID().uuidString.lowercased());fatalError("Foreign acknowledgement cleared intent")}catch ServiceError.invalid {}
    // Fail the real atomic rename against a private directory while retaining
    // the exact old state file. A failed durable acknowledgement cannot make
    // the live controller forget its outstanding launch intent.
    do {
        let target=directory.appendingPathComponent("service-recovery.json")
        let saved=directory.appendingPathComponent("retained-recovery.json")
        try FileManager.default.moveItem(at:target,to:saved)
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer {
            try? FileManager.default.removeItem(at:target)
            try? FileManager.default.moveItem(at:saved,to:target)
        }
        do {try recovery.notSent(service:.mlx,id:first.id);throw RuntimeError.identity}
        catch JournalError.storage {}
        guard recovery.isPending(.mlx) else {
            FileHandle.standardError.write(Data("SERVICE_RECOVERY_ACK_PUBLISHED_BEFORE_DURABILITY\n".utf8));throw RuntimeError.identity
        }
    }
    try recovery.notSent(service:.mlx,id:first.id)
    guard let second=try recovery.plan(service:.mlx,desired:.running,observation:absent(700000),now:700000,tick:700000) else {fatalError("Correlated non-dispatch proof did not permit later launch")}
    do {try recovery.notSent(service:.mlx,id:first.id);fatalError("Old proof retired a newer intent")}catch ServiceError.invalid {}
    try recovery.notSent(service:.mlx,id:second.id)
    guard try recovery.plan(service:.mlx,desired:.running,observation:absent(700001),now:700001,tick:700001)==nil else {fatalError("Minimum launch spacing bypassed")}
    for now:Int64 in [710000,720000] {
        guard let command=try recovery.plan(service:.mlx,desired:.running,observation:absent(now),now:now,tick:now) else {fatalError("Finite restart budget refused an available start")}
        try recovery.notSent(service:.mlx,id:command.id)
    }
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard try recovery.plan(service:.mlx,desired:.running,observation:absent(730000),now:730000,tick:730000)==nil else {fatalError("Controller restart reset three-start budget")}
    guard let independent=try recovery.plan(service:.orbstack,desired:.running,observation:absent(730000),now:730000,tick:730000) else {fatalError("One service consumed the other's budget")}
    do {try recovery.started(service:.orbstack,id:independent.id,identity:ServiceIdentity(pid:42,start:1,sha256:String(repeating:"b",count:64)));fatalError("Changed process identity acknowledged launch")}catch ServiceError.invalid {}
    try recovery.started(service:.orbstack,id:independent.id,identity:ServiceIdentity(pid:42,start:1,sha256:hash))
    let present=ServiceObservation(identity:ServiceIdentity(pid:42,start:1,sha256:hash),responding:true,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:730000)
    guard try recovery.plan(service:.orbstack,desired:.running,observation:present,now:730000,tick:730000)==nil else {fatalError("Existing verified service was launched again")}
    guard try recovery.plan(service:.orbstack,desired:.running,observation:absent(740000),now:740000,tick:729999)==nil,
          try recovery.plan(service:.orbstack,desired:.running,observation:absent(750000),now:750000,tick:750000)==nil else {fatalError("Monotonic rollback did not irreversibly fence launches")}
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard try recovery.plan(service:.orbstack,desired:.running,observation:absent(800000),now:800000,tick:800000)==nil else {fatalError("Restart erased clock fence")}
    do {_ = try ServiceRecoveryController(journal:journal,approvedHashes:[.mlx:String(repeating:"b",count:64),.orbstack:hash]);fatalError("Changed installed identity adopted prior launch state")}catch ServiceError.invalid {}
    let file=directory.appendingPathComponent("service-recovery.json"),original=try Data(contentsOf:file)
    let text=String(decoding:original,as:UTF8.self)
    let malformed=[text.replacingOccurrences(of:"\"version\":1",with:"\"version\":1.0"),String(text.dropLast())+",\"future_launch_authority\":true}"]
    for value in malformed {
        try AtomicState.write(Data(value.utf8),to:file)
        do {_ = try ServiceRecoveryController(journal:journal,approvedHashes:pins);fatalError("Malformed/future recovery state adopted")}catch ServiceError.invalid {}
    }
    try AtomicState.write(original,to:file)
    print("PASS: durable fixed-service launch intent, prerequisite gates, no absence/timeout/restart replay, correlated not-sent proof, independent persistent budgets and sticky clock/identity fences; no native launches")
}

func runServiceRecoveryBackupTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let source=root.appendingPathComponent("state"),bundle=root.appendingPathComponent("bundle"),restored=root.appendingPathComponent("restored")
    let hash=String(repeating:"a",count:64),pins:[ManagedService:String]=[.mlx:hash,.orbstack:hash]
    do {
        let journal=try Journal(directory:source)
        try journal.claim(job:UUID().uuidString.lowercased(),attempt:0,model:"fixture/exact")
        _=try ArtifactStore(directory:source.appendingPathComponent("artifacts"),availableBytes:{100<<30})
        let recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
        let absent=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:1000)
        guard try recovery.plan(service:.mlx,desired:.running,observation:absent,now:1000,tick:1000) != nil else {fatalError("Missing backup launch fixture")}
    }
    let original=try Data(contentsOf:source.appendingPathComponent("service-recovery.json"))
    let receipt=try StoppedStateBackup.create(directory:source,destination:bundle)
    guard FileManager.default.fileExists(atPath:bundle.appendingPathComponent("service-recovery.json").path) else {fatalError("Stopped backup discarded unresolved service launch intent")}
    _=try StoppedStateBackup.verify(directory:bundle,expectedSHA256:receipt.sha256)
    _=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:receipt.sha256,destination:restored)
    guard try Data(contentsOf:restored.appendingPathComponent("service-recovery.json"))==original else {fatalError("Restore changed service intent")}
    do {
        let journal=try Journal(directory:restored),recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
        let absent=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:2000)
        guard try journal.uncertainCount()==1,
              try recovery.plan(service:.mlx,desired:.running,observation:absent,now:2000,tick:2000)==nil else {fatalError("Restore refunded native ownership or launch intent")}
    }
    try AtomicState.write(Data("changed".utf8),to:bundle.appendingPathComponent("service-recovery.json"))
    do {_ = try StoppedStateBackup.verify(directory:bundle,expectedSHA256:receipt.sha256);fatalError("Changed launch intent passed backup verification")}catch JournalError.invalid {}
    print("PASS: stopped bundle preserves exact unresolved service intent plus native uncertainty, refuses tampering and does not replay after restore")
}
