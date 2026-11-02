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
    print("PASS: sampled idle is not quiescence authority; unknown/unmanaged drain and separate scope-bound force policy")
}
