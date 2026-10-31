import Foundation

private final class DrainTestClock:@unchecked Sendable {var time:TimeInterval=1}

func runDrainTests()throws {
    let identity=ServiceIdentity(pid:42,start:100,sha256:String(repeating:"a",count:64))
    let manager="12345678-1234-4234-8234-123456789abc",job="12345678-1234-4234-8234-123456789abd"
    func scope(service:ManagedService = .mlx,native:String?=String(repeating:"b",count:64),jobs:[String]=[],requests:[String]=[],stamp:Int64=1000,start:UInt64=100,epoch:String=String(repeating:"c",count:64))throws->ServiceAffectedScope {
        try ServiceAffectedScope(service:service,identity:ServiceIdentity(pid:42,start:start,sha256:identity.sha256),managerEpoch:manager,
            nativeEpoch:epoch,nativeScopeDigest:native,runtimeScopeDigest:service == .orbstack ? String(repeating:"d",count:64):nil,
            ownedJobs:jobs,unresolvedManagedRequests:requests,sampledAt:stamp)
    }
    // A native source epoch is an opaque bounded identity, not its SHA256.
    // Digests remain exact lowercase64-hex values.
    for epoch in ["native-fixture-one",UUID().uuidString.lowercased(),String(repeating:"e",count:32)] {
        do {
            _=try ServiceAffectedScope(service:.mlx,identity:identity,managerEpoch:manager,nativeEpoch:epoch,
                nativeScopeDigest:String(repeating:"b",count:64),runtimeScopeDigest:nil,ownedJobs:[],unresolvedManagedRequests:[],sampledAt:1000)
        }catch {
            FileHandle.standardError.write(Data("OPAQUE_NATIVE_EPOCH_REFUSED\n".utf8));throw error
        }
    }
    for epoch in ["",String(repeating:"e",count:129),String(repeating:"é",count:65),"native\0epoch"] {
        do {_=try scope(epoch:epoch);fatalError("Invalid native epoch accepted")}catch ServiceError.invalid {}
    }
    for digest in ["short",String(repeating:"B",count:64),String(repeating:"x",count:64)] {
        do {_=try scope(native:digest);fatalError("Invalid native scope digest accepted")}catch ServiceError.invalid {}
    }
    var epochDrain=ServiceDrainPolicy()
    let composed=ServiceDrainSnapshot(scope:try scope(epoch:"native/é"),nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:false)
    let decomposed=ServiceDrainSnapshot(scope:try scope(stamp:1001,epoch:"native/e\u{301}"),nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:false)
    _=try epochDrain.begin(snapshot:composed,role:.operator,now:1000)
    guard try epochDrain.poll(snapshot:decomposed,now:1001).state == .refused(.scopeChanged) else {
        FileHandle.standardError.write(Data("DRAIN_NORMALIZED_NATIVE_EPOCH\n".utf8));throw ServiceError.invalid
    }
    var force=ServicePolicy()
    let initial=try scope(),changed=try scope(native:String(repeating:"e",count:64),stamp:1001)
    let token=try force.prepareForce(scope:initial,role:.operator,now:1000)
    do {_=try force.confirmForce(scope:changed,role:.operator,token:token,now:1001);fatalError("Changed affected work accepted force confirmation")}catch ServiceError.invalid {}
    do {_=try force.confirmForce(scope:initial,role:.operator,token:token,now:1001);fatalError("Rejected force token revived")}catch ServiceError.invalid {}
    let valid=try force.prepareForce(scope:initial,role:.operator,now:1000)
    guard try force.confirmForce(scope:scope(stamp:1001),role:.operator,token:valid,now:1001) == .forceQuit(identity) else {fatalError("Fresh equivalent scope confirmation refused")}
    let reused=try force.prepareForce(scope:initial,role:.operator,now:1000)
    do {_=try force.confirmForce(scope:scope(start:101),role:.operator,token:reused,now:1001);fatalError("PID start change accepted force")}catch ServiceError.invalid {}
    do {_=try force.prepareForce(scope:scope(native:nil),role:.operator,now:1000);fatalError("Unknown affected scope minted force authority")}catch ServiceError.invalid {}
    do {_=try force.prepareForce(scope:initial,role:.task,now:1000);fatalError("Task minted management authority")}catch ServiceError.invalid {}
    do {_=try force.confirmForce(scope:initial,role:.operator,token:valid,now:1001);fatalError("Successful force confirmation replayed")}catch ServiceError.invalid {}
    let wrongRole=try force.prepareForce(scope:initial,role:.operator,now:1000)
    do {_=try force.confirmForce(scope:initial,role:.task,token:wrongRole,now:1001);fatalError("Task consumed force authority")}catch ServiceError.invalid {}
    do {_=try force.confirmForce(scope:initial,role:.operator,token:wrongRole,now:1001);fatalError("Rejected task confirmation revived")}catch ServiceError.invalid {}
    let forceClock=DrainTestClock()
    var timedForce=ServicePolicy(uptime:{forceClock.time})
    let timed=try timedForce.prepareForce(scope:initial,role:.operator,now:1000)
    forceClock.time=31
    do {_=try timedForce.confirmForce(scope:initial,role:.operator,token:timed,now:1001);fatalError("Slow wall clock extended30s force consent")}catch ServiceError.invalid {}
    let expiry=try force.prepareForce(scope:initial,role:.operator,now:1000)
    do {_=try force.confirmForce(scope:scope(stamp:31000),role:.operator,token:expiry,now:31000);fatalError("Expired confirmation accepted")}catch ServiceError.invalid {}
    var drain=ServiceDrainPolicy()
    let busy=ServiceDrainSnapshot(scope:try scope(jobs:[job],requests:[job]),nativeIdle:false,externalNativeWork:false,unmanagedRuntimeWork:false)
    let began=try drain.begin(snapshot:busy,role:.operator,now:1000)
    guard began.state == .draining,began.revokeOwned==[job],began.admissionClosed else {fatalError("Owned drain did not close admission/revoke only owned jobs")}
    let ready=ServiceDrainSnapshot(scope:try scope(stamp:2000),nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:false)
    guard try drain.poll(snapshot:ready,now:2000).state == .ready(identity) else {fatalError("Proof-complete empty drain did not become ready")}
    _=try drain.begin(snapshot:busy,role:.operator,now:1000)
    let late=ServiceDrainSnapshot(scope:try scope(stamp:61000),nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:false)
    guard try drain.poll(snapshot:late,now:61000).state == .refused(.deadline) else {fatalError("Drain timeout escalated to native force/quit")}
    guard try drain.poll(snapshot:ready,now:62000).state == .refused(.deadline) else {fatalError("Expired drain revived")}
    for (native,external,unmanaged,expected):(Bool?,Bool?,Bool?,ServiceDrainRefusal) in [(nil,false,false,.activityUnknown),(true,true,false,.activeWork),(true,false,true,.activeWork)] {
        let service:ManagedService=unmanaged == true ? .orbstack:.mlx
        let snapshot=ServiceDrainSnapshot(scope:try scope(service:service),nativeIdle:native,externalNativeWork:external,unmanagedRuntimeWork:unmanaged)
        guard try drain.begin(snapshot:snapshot,role:.operator,now:1000).state == .refused(expected) else {fatalError("External/unknown/unmanaged drain was not refused")}
    }
    _=try drain.begin(snapshot:busy,role:.operator,now:1000)
    let replacement=ServiceDrainSnapshot(scope:try scope(stamp:2000,start:101),nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:false)
    guard try drain.poll(snapshot:replacement,now:2000).state == .refused(.scopeChanged) else {fatalError("Drain followed a replaced service PID")}
    let secondJob="12345678-1234-4234-8234-123456789abe"
    _=try drain.begin(snapshot:busy,role:.operator,now:1000)
    let newJobs=ServiceDrainSnapshot(scope:try scope(jobs:[secondJob],stamp:1001),nativeIdle:false,externalNativeWork:false,unmanagedRuntimeWork:false)
    let refused=try drain.poll(snapshot:newJobs,now:1001)
    guard refused.state == .refused(.scopeChanged),refused.revokeOwned.isEmpty else {fatalError("Old drain revoked newly scoped jobs")}
    _=try drain.begin(snapshot:ready,role:.operator,now:2000)
    let external=ServiceDrainSnapshot(scope:try scope(stamp:2001),nativeIdle:false,externalNativeWork:true,unmanagedRuntimeWork:false)
    guard try drain.poll(snapshot:external,now:2001).state == .refused(.activeWork) else {fatalError("Cached ready decision ignored new external work")}
    _=try drain.begin(snapshot:busy,role:.operator,now:1000)
    guard try drain.poll(snapshot:busy,now:999).state == .refused(.deadline) else {fatalError("Rollback did not fence drain")}
    let drainClock=DrainTestClock();var timedDrain=ServiceDrainPolicy(uptime:{drainClock.time})
    _=try timedDrain.begin(snapshot:busy,role:.operator,now:1000)
    drainClock.time=61
    guard try timedDrain.poll(snapshot:ready,now:2000).state == .refused(.deadline) else {fatalError("Slow wall clock extended60s drain")}
    for role:ControlRole in [.observer,.task,.sandbox] {
        do {_ = try drain.begin(snapshot:busy,role:role,now:1000);fatalError("Non-operator began service drain")}catch ServiceError.invalid {}
        do {_ = try force.prepareForce(scope:initial,role:role,now:1000);fatalError("Non-operator prepared force")}catch ServiceError.invalid {}
        let consent=try force.prepareForce(scope:initial,role:.operator,now:1000)
        do {_ = try force.confirmForce(scope:initial,role:role,token:consent,now:1001);fatalError("Non-operator confirmed force")}catch ServiceError.invalid {}
        do {_ = try force.confirmForce(scope:initial,role:.operator,token:consent,now:1001);fatalError("Wrong-role confirmation did not consume consent")}catch ServiceError.invalid {}
    }
    for stamp:Int64 in [0,7002] {
        let stale=try scope(stamp:stamp)
        do {_ = try force.prepareForce(scope:stale,role:.operator,now:6001);fatalError("Stale/future scope minted force")}catch ServiceError.invalid {}
        do {_ = try drain.begin(snapshot:ServiceDrainSnapshot(scope:stale,nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:false),role:.operator,now:6001);fatalError("Stale/future scope began drain")}catch ServiceError.invalid {}
    }
    let unknownRuntime=ServiceDrainSnapshot(scope:try scope(service:.orbstack),nativeIdle:true,externalNativeWork:false,unmanagedRuntimeWork:nil)
    guard try drain.begin(snapshot:unknownRuntime,role:.operator,now:1000).state == .refused(.activityUnknown) else {fatalError("Unknown runtime inventory authorized drain")}
    print("PASS: operator-only affected-scope force binding/freshness/one-use/expiry, owned drain/admission closure, proof-complete readiness, external/unknown/unmanaged refusal and irreversible60s timeout/identity fence (pure policy only)")
}
