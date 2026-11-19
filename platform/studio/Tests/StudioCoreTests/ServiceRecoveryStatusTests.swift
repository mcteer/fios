import Foundation

func runServiceRecoveryStatusTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),hash=String(repeating:"a",count:64)
    let recovery=try ServiceRecoveryController(journal:journal,approvedHashes:[.mlx:hash,.orbstack:hash])
    func status(_ tick:Int64)->[String:Any] {recovery.summary(service:.mlx,tick:tick)}
    guard status(1000)["budget_state"] as? String == "available" else {throw ServiceError.invalid}
    for tick:Int64 in [1000,11000,21000] {
        let observation=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,
            nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:tick)
        guard let command=try recovery.plan(service:.mlx,desired:.running,observation:observation,now:tick,tick:tick),
              status(tick)["budget_state"] as? String == "pending" else {throw ServiceError.invalid}
        try recovery.notSent(service:.mlx,id:command.id)
    }
    let waiting=status(22000)
    guard waiting["budget_state"] as? String == "rate_limited",
          waiting["starts_in_window"] as? Int == 3,
          waiting["budget_wait_ms"] as? Int64 == 579000,
          recovery.summary(service:.orbstack,tick:22000)["budget_state"] as? String == "available",
          status(601000)["budget_state"] as? String == "available" else {throw ServiceError.invalid}
    let absent=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,
        nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:22000)
    let held=ServiceStatusPolicy.summary(desired:.running,observation:absent,launchPending:false,now:22000,restartWaiting:recovery.isWaitingForRestartWindow(service:.mlx,tick:22000))
    guard held["observed"] as? String == "degraded" else {
        throw NSError(domain:"ServiceRestartStatus",code:1,userInfo:[NSLocalizedDescriptionKey:"Restart-window wait is displayed as stopped instead of degraded"])
    }
    guard held["message"] as? String == "Service is stopped; automatic startup is waiting for the restart limit to reset.",
          !recovery.isWaitingForRestartWindow(service:.orbstack,tick:22000),
          !recovery.isWaitingForRestartWindow(service:.mlx,tick:601000) else {throw ServiceError.invalid}
    let healthy=ServiceObservation(identity:ServiceIdentity(pid:42,start:1,sha256:hash),responding:true,
        sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:22000)
    guard ServiceStatusPolicy.observed(desired:.running,observation:healthy,launchPending:false,now:22000,restartWaiting:true) == .ready,
          ServiceStatusPolicy.observed(desired:.stopped,observation:absent,launchPending:false,now:22000,restartWaiting:true) == .stopped else {throw ServiceError.invalid}
    let current=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,
        nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:601000)
    guard ServiceStatusPolicy.observed(desired:.running,observation:current,launchPending:false,now:601000,
        restartWaiting:recovery.isWaitingForRestartWindow(service:.mlx,tick:601000)) == .stopped else {throw ServiceError.invalid}
    let cache=ServiceObservationCache();cache.publish(absent,for:.mlx)
    let telemetry=ServiceTelemetry.sample(journal:journal,observations:cache,recovery:recovery,now:22000,uptimeTick:22000)
    guard telemetry.first(where:{$0.service == .mlx})?.observed == .degraded else {throw ServiceError.invalid}
    // Budget expiry must not make a cached absent sample launchable.
    guard ServiceStatusPolicy.observed(desired:.running,observation:absent,launchPending:false,now:601000,restartWaiting:false) == .unknown,
          try recovery.plan(service:.mlx,desired:.running,observation:absent,now:601000,tick:601000)==nil,
          status(601000)["budget_state"] as? String=="available" else {throw ServiceError.invalid}
    let future=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,
        nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:602001)
    guard ServiceStatusPolicy.observed(desired:.running,observation:future,launchPending:false,now:601000) == .unknown,
          try recovery.plan(service:.mlx,desired:.running,observation:future,now:601000,tick:601000)==nil,
          status(601000)["budget_state"] as? String=="available" else {throw ServiceError.invalid}
    guard let renewed=try recovery.plan(service:.mlx,desired:.running,observation:current,now:601000,tick:601000),
          status(601000)["budget_state"] as? String=="pending",
          try recovery.plan(service:.mlx,desired:.running,observation:current,now:601000,tick:601000)==nil else {throw ServiceError.invalid}
    try recovery.notSent(service:.mlx,id:renewed.id)
    guard try recovery.plan(service:.mlx,desired:.running,observation:current,now:600999,tick:600999)==nil,
          status(601000)["budget_state"] as? String=="clock_fenced",
          status(601000)["budget_wait_ms"] is NSNull,
          try recovery.plan(service:.mlx,desired:.running,observation:current,now:601000,tick:601000)==nil else {throw ServiceError.invalid}
    let freshHealthy=ServiceObservation(identity:healthy.identity,responding:true,sessionReady:true,credentialsReady:true,
        nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:601000)
    guard ServiceStatusPolicy.observed(desired:.running,observation:freshHealthy,launchPending:false,now:601000) == .ready,
          status(601000)["budget_state"] as? String=="clock_fenced" else {throw ServiceError.invalid}
    let persisted=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("service-recovery.json"))) as? [String:Any]
    guard persisted?["fenced"] as? Bool==true else {throw ServiceError.invalid}
    try checkRecoveryClockFenceReopen(directory:directory.appendingPathComponent("reopen"),hash:hash)
    print("PASS: ordinary service recovery status reports pending, per-service budget wait and expiry independently of the persisted clock fence")
}

private func checkRecoveryClockFenceReopen(directory:URL,hash:String)throws {
    let pins:[ManagedService:String]=[.mlx:hash,.orbstack:hash]
    let absent=ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,
        nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:2000)
    let original:ServiceLaunchCommand
    do {
        let journal=try Journal(directory:directory)
        let recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
        guard let planned=try recovery.plan(service:.mlx,desired:.running,observation:absent,now:2000,tick:2000) else {throw ServiceError.invalid}
        original=planned
        guard try recovery.plan(service:.orbstack,desired:.running,observation:absent,now:1999,tick:1999)==nil else {throw ServiceError.invalid}
    }
    let journal=try Journal(directory:directory)
    let recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard let lookup=try recovery.next(service:.mlx,desired:.running,observation:absent,now:2000,tick:2000),
          lookup.operation == .lookup,lookup.command.id==original.id else {throw ServiceError.invalid}
    try recovery.receive(lookup,result:.uncertain)
    guard let cancel=try recovery.next(service:.mlx,desired:.maintenance,observation:absent,now:2000,tick:2000),
          cancel.operation == .cancel,cancel.command.id==original.id,
          try recovery.next(service:.orbstack,desired:.running,observation:absent,now:2000,tick:2000)==nil,
          recovery.summary(service:.mlx,tick:2000)["budget_state"] as? String=="clock_fenced" else {throw ServiceError.invalid}
}
