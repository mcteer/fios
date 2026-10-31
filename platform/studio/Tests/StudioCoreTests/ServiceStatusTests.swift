import Foundation

func runServiceStatusTests() throws {
    let identity=ServiceIdentity(pid:123,start:1,sha256:String(repeating:"a",count:64))
    func sample(_ identity:ServiceIdentity?,_ responding:Bool=false,_ session:Bool=true,_ credentials:Bool=true,_ sampled:Int64=1000)->ServiceObservation {
        ServiceObservation(identity:identity,responding:responding,sessionReady:session,credentialsReady:credentials,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:sampled)
    }
    let cases:[(ServiceDesired,ServiceObservation?,Bool,ServiceObserved)]=[
        (.running,nil,false,.unknown),(.running,sample(nil,false,false),false,.waiting_session),
        (.running,sample(nil,false,true,false),false,.waiting_credentials),
        (.running,sample(nil),false,.stopped),(.running,sample(nil),true,.starting),
        (.running,sample(identity,true),false,.ready),(.maintenance,sample(identity,true),false,.ready),
        (.running,sample(identity,true,false,true),false,.ready),
        (.running,sample(identity,true,true,false),false,.waiting_credentials),
        (.stopped,sample(identity,true),false,.ready), // intent is not observation
        (.running,sample(identity),false,.degraded),(.running,sample(identity),true,.starting),
        (.maintenance,sample(nil,false,false,false),false,.stopped),(.stopped,sample(nil),false,.stopped),
        (.running,sample(nil,true),false,.unknown),(.running,sample(identity,true,true,true,6001),false,.unknown)]
    for (desired,observation,pending,expected) in cases {
        guard ServiceStatusPolicy.observed(desired:desired,observation:observation,launchPending:pending,now:1000)==expected else {fatalError("Service intent/observation/session/credential state confused")}
    }
    var boundaryFailures:[String]=[]
    if ServiceIdentity(pid:42,start:0,sha256:identity.sha256).valid {boundaryFailures.append("Zero kernel process-start identity accepted")}
    if !ServiceIdentity(pid:42,start:9_007_199_254_740_992,sha256:identity.sha256).valid {boundaryFailures.append("Opaque process-start token was treated as a UTC/JSON timestamp")}
    let policy=ServicePolicy()
    for service in ManagedService.allCases {
        for desired in ServiceDesired.allCases {
            do {
                _ = try policy.action(service:service,desired:desired,observation:sample(nil,true),now:1000)
                boundaryFailures.append("Responding-with-proven-absence contradiction permitted a lifecycle decision")
            } catch ServiceError.invalid {}
        }
    }
    guard boundaryFailures.isEmpty else {fatalError(boundaryFailures.joined(separator:"; "))}
    func opaqueScope(_ token:UInt64) throws -> ServiceAffectedScope {
        try ServiceAffectedScope(service:.mlx,identity:ServiceIdentity(pid:42,start:token,sha256:identity.sha256),
            managerEpoch:"00000000-0000-4000-8000-000000000001",nativeEpoch:String(repeating:"b",count:64),nativeScopeDigest:String(repeating:"c",count:64),
            runtimeScopeDigest:nil,ownedJobs:[],unresolvedManagedRequests:[],sampledAt:1000)
    }
    guard ServiceIdentity(pid:42,start:UInt64.max,sha256:identity.sha256).valid,
          try opaqueScope(UInt64.max).digest != opaqueScope(UInt64.max-1).digest else {fatalError("Opaque process-start tokens truncated or collided in force scope")}
    guard try policy.action(service:.mlx,desired:.running,observation:sample(nil,false,false),now:1000) == .waitForSession,
          try policy.action(service:.mlx,desired:.running,observation:sample(nil,false,true,false),now:1000) == .waitForCredentials else {fatalError("Recovery bypassed missing session/credentials")}
    for time:Int64 in [0,6000] {
        guard ServiceStatusPolicy.observed(desired:.running,observation:sample(identity,true,true,true,time),launchPending:false,now:5000) == .ready else {fatalError("Inclusive source age/future boundary rejected")}
    }
    let cache=ServiceObservationCache()
    guard cache.snapshot(for:.mlx)==nil,cache.snapshot(for:.orbstack)==nil else {fatalError("New manager cache adopted prior observations")}
    cache.publish(sample(identity,true),for:.mlx)
    guard cache.snapshot(for:.orbstack)==nil,
          ServiceStatusPolicy.observed(desired:.running,observation:cache.snapshot(for:.mlx),launchPending:false,now:6001) == .unknown else {fatalError("Stale cached observation or cross-service evidence trusted")}
    cache.publish(nil,for:.mlx)
    guard cache.snapshot(for:.mlx)==nil else {fatalError("Lost source retained known service state")}
    print("PASS: desired vs observed service states, missing session/credentials, pending launch and unknown/stale/incoherent evidence")
}

func runServiceStatusSummaryTests() throws {
    let sample=ServiceObservation(identity:nil,responding:false,sessionReady:false,credentialsReady:true,
                                  nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:1000)
    let waiting=ServiceStatusPolicy.summary(desired:.running,observation:sample,launchPending:false,now:1200)
    precondition(waiting["observed"] as? String == "waiting_session")
    precondition(waiting["sampled_at"] as? Int64 == 1000 && waiting["age_ms"] as? Int64 == 200)
    precondition(waiting["launch_pending"] as? Bool == false)
    let missing=ServiceStatusPolicy.summary(desired:.maintenance,observation:nil,launchPending:false,now:1200)
    precondition(missing["desired"] as? String == "maintenance" && missing["observed"] as? String == "unknown")
    precondition(missing["sampled_at"] is NSNull && missing["age_ms"] is NSNull)
    let pending=ServiceStatusPolicy.summary(desired:.running,observation:ServiceObservation(identity:nil,responding:false,
        sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:1000),launchPending:true,now:1200)
    precondition(pending["observed"] as? String == "starting" && pending["launch_pending"] as? Bool == true)
}
