import Foundation

func runServiceRecoveryTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let hash=String(repeating:"a",count:64),pins:[ManagedService:String]=[.mlx:hash,.orbstack:hash]
    let base=try ServiceLaunchProfile.digest(pins)
    let binding=["--host","127.0.0.1","--port","11234"]
    let nativeArgs=["--serve"]+binding+["--api-key-env","FIOS_MLX_SERVING_API_KEY","--model","fixture/Exact"]
    let nativeEnv=["HOME":"/Users/fixture","FIOS_MLX_SERVING_API_KEY":"fixture-secret-a"]
    let fingerprint=try ServiceLaunchProfile.nativeDigest(base:base,arguments:nativeArgs,environment:nativeEnv,workingDirectory:"/")
    var rotated=nativeEnv;rotated["FIOS_MLX_SERVING_API_KEY"]="fixture-secret-b"
    guard fingerprint == (try ServiceLaunchProfile.nativeDigest(base:base,arguments:nativeArgs,environment:rotated,workingDirectory:"/")),
          fingerprint != (try ServiceLaunchProfile.nativeDigest(base:base,arguments:nativeArgs,environment:nativeEnv,workingDirectory:"/Users/fixture")),
          fingerprint != (try ServiceLaunchProfile.nativeDigest(base:base,arguments:["--serve","--model","fixture/Other"],environment:nativeEnv,workingDirectory:"/")) else {fatalError("Native launch binding lost exact configuration or became a credential verifier")}
    // The actual pinned parser leaves missing/empty environment credentials
    // open. Native launch configuration must fail before any process effect.
    _=try NativeServingLaunchInputs(arguments:nativeArgs,environment:nativeEnv,workingDirectory:"/")
    _=try NativeServingLaunchInputs(arguments:["--serve"]+binding+["--api-key","fixture-key"],environment:[:],workingDirectory:"/")
    for args in [["--serve"],["--serve","--api-key-env"],["--serve","--api-key",""],
                 ["--serve","--api-key-env","OTHER"],["--serve","--api-key=fixture"],
                 ["--serve","--api-key-env","FIOS_MLX_SERVING_API_KEY","--api-key","fixture"]] {
        do {_=try NativeServingLaunchInputs(arguments:args+binding,environment:nativeEnv,workingDirectory:"/");fatalError("Invalid native credential channel accepted")}
        catch RuntimeError.invalid {}
    }
    for env:[String:String] in [[:],["FIOS_MLX_SERVING_API_KEY":""]] {
        do {_=try NativeServingLaunchInputs(arguments:nativeArgs,environment:env,workingDirectory:"/");fatalError("Missing native credential accepted")}
        catch RuntimeError.invalid {}
    }
    for host in ["127.0.0.1","::1","0.0.0.0","::","192.0.2.10"] {
        let arguments=["--serve","--host",host,"--port","11234","--api-key","fixture-key"]
        guard try NativeServingLaunchInputs(arguments:arguments,environment:[:],workingDirectory:"/").arguments==arguments else {fatalError("Explicit reviewed binding changed")}
    }
    for arguments in [["--serve","--api-key","fixture-key"],
                      ["--serve","--host","127.0.0.1","--api-key","fixture-key"],
                      ["--serve","--port","11234","--api-key","fixture-key"],
                      nativeArgs+["--host","::1"],nativeArgs+["--port","11235"],
                      ["--serve","--host","localhost","--port","11234","--api-key","fixture-key"],
                      ["--serve","--host=127.0.0.1","--port","11234","--api-key","fixture-key"]] {
        do {_=try NativeServingLaunchInputs(arguments:arguments,environment:nativeEnv,workingDirectory:"/");fatalError("Missing/ambiguous binding accepted")}
        catch RuntimeError.invalid {}
    }
    for port in ["0","65536","-1","+11234","011234","11234.0"] {
        do {_=try NativeServingLaunchInputs(arguments:["--serve","--host","127.0.0.1","--port",port,"--api-key","fixture-key"],environment:[:],workingDirectory:"/");fatalError("Invalid reviewed port accepted")}
        catch RuntimeError.invalid {}
    }
    let launchDocument:[String:Any]=[
        "version":1,"purpose":"reviewed_native_serving_launch","host":"fios-edge-a.lab","uid":501,
        "review_sha256":hash,"manager_sha256":hash,"supervisor_sha256":hash,"server_sha256":hash,"application_sha256":hash,
        "revision":UUID().uuidString.lowercased(),"state_path":"/Users/fixture/state","working_directory":"/",
        "arguments":nativeArgs,"environment":["HOME":"/Users/fixture","PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C"],
        "credential_channel":"environment"]
    func decodeLaunch(_ document:[String:Any])throws->NativeServingLaunchDocument {
        try NativeServingLaunchDocument(JSONSerialization.data(withJSONObject:document,options:[.sortedKeys]))
    }
    guard try NativeServingReviewedConfiguration.load(directory:directory)==nil else {fatalError("Development binary loaded installed native configuration")}
    guard try NativeServingReviewedConfiguration.load(directory:directory,role:.supervisor)==nil else {fatalError("Development binary acquired supervisor configuration")}
    let decoded=try decodeLaunch(launchDocument)
    let resolved=try decoded.resolvingCredential("fixture-resolved-key")
    guard resolved.arguments==nativeArgs,resolved.environment["FIOS_MLX_SERVING_API_KEY"]=="fixture-resolved-key",
          resolved.workingDirectory=="/",decoded.host=="fios-edge-a.lab" else {fatalError("Reviewed launch inputs changed")}
    guard try decoded.recoveryProfileHash(base:base,reviewedConfigurationSHA256:hash) == ServiceLaunchProfile.nativeDigest(base:base,arguments:resolved.arguments,environment:resolved.environment,workingDirectory:resolved.workingDirectory,reviewedConfigurationSHA256:hash) else {fatalError("Credential-free manager profile differs from native runtime inputs")}
    var argumentDocument=launchDocument
    argumentDocument["credential_channel"]="argument"
    argumentDocument["arguments"]=["--serve"]+binding+["--api-key",NativeServingLaunchDocument.credentialSlot,"--model","fixture/Exact"]
    guard try decodeLaunch(argumentDocument).resolvingCredential("fixture-argument-key").arguments == ["--serve"]+binding+["--api-key","fixture-argument-key","--model","fixture/Exact"] else {fatalError("Argument credential slot not preserved")}
    let argumentDecoded=try decodeLaunch(argumentDocument),argumentResolved=try argumentDecoded.resolvingCredential("fixture-argument-key")
    guard try argumentDecoded.recoveryProfileHash(base:base,reviewedConfigurationSHA256:hash) == ServiceLaunchProfile.nativeDigest(base:base,arguments:argumentResolved.arguments,environment:argumentResolved.environment,workingDirectory:argumentResolved.workingDirectory,reviewedConfigurationSHA256:hash) else {fatalError("Argument-mode manager profile requires credential value")}
    let argumentFingerprint=try argumentDecoded.recoveryProfileHash(base:base,reviewedConfigurationSHA256:hash)
    for key in ["fixture-key","--api-key","--host","--api-key=literal"] {
        let inputs=try argumentDecoded.resolvingCredential(key)
        guard inputs.arguments == ["--serve"]+binding+["--api-key",key,"--model","fixture/Exact"],
              try ServiceLaunchProfile.nativeDigest(base:base,arguments:inputs.arguments,environment:inputs.environment,workingDirectory:inputs.workingDirectory,reviewedConfigurationSHA256:hash)==argumentFingerprint else {fatalError("Literal credential rotation changed native configuration or became a journal verifier")}
    }
    for (key,value):(String,Any) in [("host","fios-core.lab"),("uid",true),("version",2),("supervisor_sha256","missing"),
          ("state_path","/tmp/../state"),("working_directory","/tmp/../"),("arguments",["--serve","--api-key","literal-key"]),
          ("environment",["HOME":"/Users/fixture","PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C","FIOS_MLX_SERVING_API_KEY":"literal-key"]),
          ("extra","unknown"),("credential_channel","keychain")] {
        var invalid=launchDocument;invalid[key]=value
        do {_=try decodeLaunch(invalid);fatalError("Invalid reviewed launch document accepted")}
        catch RuntimeError.invalid {}
    }
    var literalArgument=argumentDocument;literalArgument["arguments"]=["--serve"]+binding+["--api-key","literal-key"]
    do {_=try decodeLaunch(literalArgument);fatalError("Literal argument credential entered durable profile")}
    catch RuntimeError.invalid {}
    for secret in ["",String(repeating:"x",count:4097),"invalid\0key"] {
        do {_=try decoded.resolvingCredential(secret);fatalError("Invalid credential resolution accepted")}
        catch RuntimeError.invalid {}
    }
    let reviewedFingerprint=try ServiceLaunchProfile.nativeDigest(base:base,arguments:nativeArgs,environment:nativeEnv,workingDirectory:"/",reviewedConfigurationSHA256:hash)
    guard reviewedFingerprint != fingerprint,
          reviewedFingerprint != (try ServiceLaunchProfile.nativeDigest(base:base,arguments:nativeArgs,environment:nativeEnv,workingDirectory:"/",reviewedConfigurationSHA256:String(repeating:"b",count:64))),
          reviewedFingerprint == (try ServiceLaunchProfile.nativeDigest(base:base,arguments:nativeArgs,environment:rotated,workingDirectory:"/",reviewedConfigurationSHA256:hash)) else {fatalError("Reviewed configuration identity not bound or credential entered fingerprint")}
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
    // Existing version1 state has no launch-identity receipt. Preserve its
    // unresolved operation and budget while upgrading future writes to v2.
    let legacyFile=directory.appendingPathComponent("service-recovery.json")
    var legacy=try JSONSerialization.jsonObject(with:Data(contentsOf:legacyFile)) as! [String:Any]
    legacy["version"]=1
    legacy["entries"]=(legacy["entries"] as! [[String:Any]]).map {entry in var old=entry;old.removeValue(forKey:"stops");return old}
    try AtomicState.write(JSONSerialization.data(withJSONObject:legacy),to:legacyFile)
    // New controller restores durable intent while the same single writer is
    // held. Fresh absence and elapsed time cannot retire unknown dispatch.
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard recovery.isPending(.mlx),recovery.recordedLaunch(.mlx)==nil else {fatalError("Legacy state invented a launch receipt or lost pending intent")}
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
    do {
        let target=directory.appendingPathComponent("service-recovery.json"),saved=directory.appendingPathComponent("retained-started-recovery.json")
        try FileManager.default.moveItem(at:target,to:saved)
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer {
            try? FileManager.default.removeItem(at:target)
            try? FileManager.default.moveItem(at:saved,to:target)
        }
        do {try recovery.started(service:.orbstack,id:independent.id,identity:ServiceIdentity(pid:42,start:1,sha256:hash));throw RuntimeError.identity}
        catch JournalError.storage {}
        guard recovery.isPending(.orbstack),recovery.recordedLaunch(.orbstack)==nil else {fatalError("Failed durable started acknowledgement published a receipt or cleared pending intent")}
    }
    try recovery.started(service:.orbstack,id:independent.id,identity:ServiceIdentity(pid:42,start:1,sha256:hash))
    let acknowledged=recovery.recordedLaunch(.orbstack)
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard let acknowledged,acknowledged.id==independent.id,acknowledged.identity==ServiceIdentity(pid:42,start:1,sha256:hash),
          recovery.recordedLaunch(.orbstack)==acknowledged,!recovery.isPending(.orbstack) else {fatalError("Manager reconstruction lost correlated launch identity")}
    let present=ServiceObservation(identity:ServiceIdentity(pid:42,start:1,sha256:hash),responding:true,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:730000)
    guard try recovery.plan(service:.orbstack,desired:.running,observation:present,now:730000,tick:730000)==nil else {fatalError("Existing verified service was launched again")}
    guard try recovery.plan(service:.orbstack,desired:.running,observation:absent(740000),now:740000,tick:729999)==nil,
          try recovery.plan(service:.orbstack,desired:.running,observation:absent(750000),now:750000,tick:750000)==nil else {fatalError("Monotonic rollback did not irreversibly fence launches")}
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard try recovery.plan(service:.orbstack,desired:.running,observation:absent(800000),now:800000,tick:800000)==nil else {fatalError("Restart erased clock fence")}
    do {_ = try ServiceRecoveryController(journal:journal,approvedHashes:[.mlx:String(repeating:"b",count:64),.orbstack:hash]);fatalError("Changed installed identity adopted prior launch state")}catch ServiceError.invalid {}
    let file=directory.appendingPathComponent("service-recovery.json"),original=try Data(contentsOf:file)
    var previous=try JSONSerialization.jsonObject(with:original) as! [String:Any]
    previous["version"]=2
    previous["entries"]=(previous["entries"] as! [[String:Any]]).map {entry in var old=entry;old.removeValue(forKey:"stops");return old}
    try AtomicState.write(JSONSerialization.data(withJSONObject:previous),to:file)
    let previousController=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard previousController.recordedLaunch(.orbstack)==acknowledged,!previousController.isStopPending() else {fatalError("Version2 launch history was lost or invented a stop")}
    let text=String(decoding:original,as:UTF8.self)
    let malformed=[text.replacingOccurrences(of:"\"version\":3",with:"\"version\":3.0"),String(text.dropLast())+",\"future_launch_authority\":true}",text.replacingOccurrences(of:"\"start\":\"1\"",with:"\"start\":\"01\"")]
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
