import Foundation

func runServiceForceControllerTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),cache=ServiceDrainObservationCache(),epoch=UUID().uuidString.lowercased()
    let controller=try ServiceForceController(journal:journal,managerEpoch:epoch,observations:cache)
    let identity=ServiceIdentity(pid:42,start:100,sha256:String(repeating:"a",count:64))
    func snapshot(stamp:Int64=1000,external:Bool?=true)throws->ServiceDrainSnapshot {
        ServiceDrainSnapshot(scope:try ServiceAffectedScope(service:.mlx,identity:identity,managerEpoch:epoch,nativeEpoch:"force-fixture",
            nativeScopeDigest:String(repeating:"b",count:64),runtimeScopeDigest:nil,ownedJobs:[],unresolvedManagedRequests:[],sampledAt:stamp),
            nativeIdle:false,externalNativeWork:external,unmanagedRuntimeWork:nil)
    }
    cache.publish(try snapshot(),for:.mlx)
    for role:ControlRole in [.observer,.task,.sandbox] {
        do {_=try controller.prepare(service:.mlx,role:role,now:1000);throw RuntimeError.identity}catch ServiceError.invalid {}
    }
    guard try journal.recordedDesired(service:.mlx)==nil else {throw RuntimeError.identity}
    let initial=try controller.prepare(service:.mlx,role:.operator,now:1000)
    guard try journal.recordedDesired(service:.mlx) == .maintenance else {
        FileHandle.standardError.write(Data("FORCE_CONSENT_WITHOUT_DURABLE_MAINTENANCE\n".utf8));throw RuntimeError.identity
    }
    cache.publish(nil,for:.mlx)
    do {_=try controller.confirm(service:.mlx,role:.operator,token:initial.token,scopeDigest:initial.scopeDigest,now:1001);throw RuntimeError.identity}catch ServiceError.invalid {}
    cache.publish(try snapshot(stamp:1002),for:.mlx)
    do {
        _=try controller.confirm(service:.mlx,role:.operator,token:initial.token,scopeDigest:initial.scopeDigest,now:1002)
        FileHandle.standardError.write(Data("FORCE_REPLAYED_AFTER_SOURCE_LOSS\n".utf8));throw RuntimeError.identity
    }catch ServiceError.invalid {}
    let rejected=try controller.prepare(service:.mlx,role:.operator,now:1002)
    do {_=try controller.confirm(service:.mlx,role:.operator,token:rejected.token,scopeDigest:String(repeating:"f",count:64),now:1002);throw RuntimeError.identity}catch ServiceError.invalid {}
    do {
        _=try controller.confirm(service:.mlx,role:.operator,token:rejected.token,scopeDigest:rejected.scopeDigest,now:1002)
        FileHandle.standardError.write(Data("FORCE_REPLAYED_REJECTED_CONFIRMATION\n".utf8));throw RuntimeError.identity
    }catch ServiceError.invalid {}
    let gap=try controller.prepare(service:.mlx,role:.operator,now:1002)
    cache.publish(nil,for:.mlx)
    cache.publish(try snapshot(stamp:1002),for:.mlx)
    do {
        _=try controller.confirm(service:.mlx,role:.operator,token:gap.token,scopeDigest:gap.scopeDigest,now:1002)
        FileHandle.standardError.write(Data("FORCE_ACCEPTED_SCOPE_AFTER_GAP\n".utf8));throw RuntimeError.identity
    }catch ServiceError.invalid {}
    let changed=try controller.prepare(service:.mlx,role:.operator,now:1002)
    cache.publish(try snapshot(stamp:1002,external:false),for:.mlx)
    cache.publish(try snapshot(stamp:1002),for:.mlx)
    do {_=try controller.confirm(service:.mlx,role:.operator,token:changed.token,scopeDigest:changed.scopeDigest,now:1002);throw RuntimeError.identity}catch ServiceError.invalid {}
    let resumed=try controller.prepare(service:.mlx,role:.operator,now:1002)
    try journal.setDesired(service:"mlx",desired:"running")
    do {_=try controller.confirm(service:.mlx,role:.operator,token:resumed.token,scopeDigest:resumed.scopeDigest,now:1002);throw RuntimeError.identity}catch ServiceError.invalid {}
    try journal.setDesired(service:"mlx",desired:"maintenance")
    do {_=try controller.confirm(service:.mlx,role:.operator,token:resumed.token,scopeDigest:resumed.scopeDigest,now:1002);throw RuntimeError.identity}catch ServiceError.invalid {}
    let good=try controller.prepare(service:.mlx,role:.operator,now:1002)
    guard try controller.confirm(service:.mlx,role:.operator,token:good.token,scopeDigest:good.scopeDigest,now:1002) == .forceQuit(identity) else {throw RuntimeError.identity}
    do {_=try controller.confirm(service:.mlx,role:.operator,token:good.token,scopeDigest:good.scopeDigest,now:1002);throw RuntimeError.identity}catch ServiceError.invalid {}
    cache.publish(try snapshot(stamp:1002,external:nil),for:.mlx)
    do {_=try controller.prepare(service:.mlx,role:.operator,now:1002);throw RuntimeError.identity}catch ServiceError.invalid {}
    print("PASS: durable-maintenance-bound force consent, source/intent-loss consumption and one-use exact scope; synthetic metadata only, no actuator")
}
