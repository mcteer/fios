import Foundation

func runServiceTests() throws {
    let policy=ServicePolicy()
    let id=ServiceIdentity(pid:42,start:100,sha256:String(repeating:"a",count:64))
    let session=ServiceObservation(identity:id,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:false,runtimeUnmanaged:false,sampledAt:1000)
    guard try policy.action(service:.mlx,desired:.running,observation:session,now:1000) == .waitForIdle else { fatalError("Busy MLX restart permitted") }
    let unknown=ServiceObservation(identity:id,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:false,sampledAt:1000)
    guard try policy.action(service:.mlx,desired:.stopped,observation:unknown,now:1000) == .waitForIdle else { fatalError("Unknown activity allowed stop") }
    let idle=ServiceObservation(identity:id,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:true,runtimeUnmanaged:false,sampledAt:1000)
    guard try policy.action(service:.mlx,desired:.stopped,observation:idle,now:1000) == .waitForIdle else { fatalError("Sampled idle authorized stop without atomic quiescence") }
    let unmanaged=ServiceObservation(identity:id,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:true,runtimeUnmanaged:true,sampledAt:1000)
    guard try policy.action(service:.orbstack,desired:.stopped,observation:unmanaged,now:1000) == .waitForUnmanaged else { fatalError("Unmanaged runtime work displaced") }
    func absent(_ at:Int64)->ServiceObservation {
        ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:at)
    }
    // Invalid clocks must refuse before even an absent-service launch decision.
    // Status already rejects this domain; action eligibility must agree.
    let maximum=ActivityPolicy.maximumTimestamp
    for service in [ManagedService.mlx,.orbstack] {
        for (now,at) in [(maximum,maximum+1),(maximum,maximum+1000),
                         (10000,11001),(10000,4999),(-1,0),(1000,-1)] {
            do {
                _ = try policy.action(service:service,desired:.running,observation:absent(at),now:now)
                fatalError("FIO_SERVICE_INVALID_OBSERVATION_ALLOWED_ACTION")
            } catch ServiceError.stale {}
        }
        for (now,at) in [(maximum,maximum),(10000,11000),(10000,5000)] {
            guard try policy.action(service:service,desired:.running,observation:absent(at),now:now) == .launch else {
                fatalError("Valid service freshness edge refused")
            }
        }
    }
    print("PASS: sampled idle is not quiescence authority; unknown/unmanaged drain and separate scope-bound force policy")
}
