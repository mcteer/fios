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
    print("PASS: ordinary service recovery status reports pending, per-service budget wait and expiry")
}
