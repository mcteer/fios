import Foundation
import CryptoKit

// Trusted ledger/validated native-adapter input, NEVER a client-submitted
// digest or model JSON. Nil source digests/epoch mean incomplete coverage.
// This type is deliberately not Codable; no production source issuer is wired.
struct ServiceAffectedScope {
    let service:ManagedService
    let identity:ServiceIdentity
    let managerEpoch:String
    let nativeEpoch:String?
    let ownedJobs:[String]
    let unresolvedManagedRequests:[String]
    let sampledAt:Int64
    let complete:Bool
    let digest:String
    init(service:ManagedService,identity:ServiceIdentity,managerEpoch:String,nativeEpoch:String?,nativeScopeDigest:String?,runtimeScopeDigest:String?,
         ownedJobs:[String],unresolvedManagedRequests:[String],sampledAt:Int64)throws {
        func hash(_ text:String)->Bool {text.utf8.count==64 && text.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})}
        func uuid(_ text:String)->Bool {UUID(uuidString:text)?.uuidString.lowercased()==text}
        guard identity.valid,uuid(managerEpoch),sampledAt>=0,sampledAt<=ActivityPolicy.maximumTimestamp,
              ownedJobs.count<=4,unresolvedManagedRequests.count<=32,
              Set(ownedJobs).count==ownedJobs.count,Set(unresolvedManagedRequests).count==unresolvedManagedRequests.count,
              ownedJobs.allSatisfy(uuid),unresolvedManagedRequests.allSatisfy(uuid),
              nativeEpoch.map({!$0.isEmpty && $0.utf8.count<=128 && !$0.contains("\0")}) ?? true,
              [nativeScopeDigest,runtimeScopeDigest].allSatisfy({$0.map(hash) ?? true}) else {throw ServiceError.invalid}
        self.service=service;self.identity=identity;self.managerEpoch=managerEpoch;self.nativeEpoch=nativeEpoch
        self.ownedJobs=ownedJobs.sorted();self.unresolvedManagedRequests=unresolvedManagedRequests.sorted();self.sampledAt=sampledAt
        complete=nativeEpoch != nil && nativeScopeDigest != nil && (service == .mlx || runtimeScopeDigest != nil)
        let fields=["fios-service-affected-scope-v1",service.rawValue,String(identity.pid),String(identity.start),identity.sha256,managerEpoch,nativeEpoch ?? "unknown",
            nativeScopeDigest ?? "unknown",runtimeScopeDigest ?? "unknown",self.ownedJobs.joined(separator:","),self.unresolvedManagedRequests.joined(separator:",")]
        digest=SHA256.hash(data:Data(fields.joined(separator:"\0").utf8)).map {String(format:"%02x",$0)}.joined()
    }
    func fresh(now:Int64)->Bool {now>=0 && now<=ActivityPolicy.maximumTimestamp && (-1000...5000).contains(now-sampledAt)}
}
struct ServiceDrainSnapshot {
    let scope:ServiceAffectedScope
    let nativeIdle:Bool?
    let externalNativeWork:Bool?
    let unmanagedRuntimeWork:Bool?
}
enum ServiceDrainRefusal:Equatable {case activityUnknown,activeWork,deadline,scopeChanged}
enum ServiceDrainState:Equatable {case draining,ready(ServiceIdentity),refused(ServiceDrainRefusal)}
struct ServiceDrainProgress {
    let state:ServiceDrainState
    let revokeOwned:[String]
    let admissionClosed=true
}
// Serialized policy only. Caller must persist maintenance BEFORE beginning;
// ready is a fresh decision, NOT native quiescence/stop authority or completion.
// No action here signals, starts/stops services, clears claims or opens a runtime.
struct ServiceDrainPolicy {
    private struct Pending {
        let identity:ServiceIdentity
        let managerEpoch:String
        let nativeEpoch:String?
        let expires:Int64
        let beganUptime:TimeInterval
        let ownedJobs:Set<String>
        var previous:Int64
        var previousUptime:TimeInterval
        var state:ServiceDrainState
    }
    private var pending:[ManagedService:Pending]=[:]
    private let uptime:@Sendable()->TimeInterval
    init(uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {self.uptime=uptime}
    private func evaluate(_ snapshot:ServiceDrainSnapshot)->ServiceDrainState {
        guard snapshot.scope.complete,let idle=snapshot.nativeIdle,let external=snapshot.externalNativeWork else {return .refused(.activityUnknown)}
        if external {return .refused(.activeWork)}
        if snapshot.scope.service == .orbstack {
            guard let unmanaged=snapshot.unmanagedRuntimeWork else {return .refused(.activityUnknown)}
            if unmanaged {return .refused(.activeWork)}
        }
        if !snapshot.scope.ownedJobs.isEmpty || !snapshot.scope.unresolvedManagedRequests.isEmpty {return .draining}
        guard idle else {return .refused(.activityUnknown)}
        return .ready(snapshot.scope.identity)
    }
    mutating func begin(snapshot:ServiceDrainSnapshot,role:ControlRole,now:Int64)throws->ServiceDrainProgress {
        let tick=uptime()
        guard role == .operator,snapshot.scope.fresh(now:now),now<=ActivityPolicy.maximumTimestamp-60000,tick.isFinite,tick>=0 else {throw ServiceError.invalid}
        let state=evaluate(snapshot),scope=snapshot.scope
        pending[scope.service]=Pending(identity:scope.identity,managerEpoch:scope.managerEpoch,nativeEpoch:scope.nativeEpoch,expires:now+60000,
            beganUptime:tick,ownedJobs:Set(scope.ownedJobs),previous:now,previousUptime:tick,state:state)
        return ServiceDrainProgress(state:state,revokeOwned:scope.ownedJobs)
    }
    // Source/ledger loss is sticky for this attempt. Only a new explicit
    // operator begin can replace it; absence is never native quiescence.
    mutating func invalidate(service:ManagedService)throws->ServiceDrainProgress {
        guard var record=pending[service] else {throw ServiceError.invalid}
        if case .refused=record.state {}else {record.state = .refused(.activityUnknown)}
        pending[service]=record
        return ServiceDrainProgress(state:record.state,revokeOwned:[])
    }
    mutating func poll(snapshot:ServiceDrainSnapshot,now:Int64)throws->ServiceDrainProgress {
        let scope=snapshot.scope
        guard var record=pending[scope.service] else {throw ServiceError.invalid}
        if case .refused=record.state {return ServiceDrainProgress(state:record.state,revokeOwned:[])}
        let tick=uptime()
        if now<record.previous || now>=record.expires || !tick.isFinite || tick<record.previousUptime || tick-record.beganUptime>=60 {record.state = .refused(.deadline)}
        else if !scope.fresh(now:now) || record.identity != scope.identity || record.managerEpoch != scope.managerEpoch || record.nativeEpoch.map({Data($0.utf8)}) != scope.nativeEpoch.map({Data($0.utf8)}) || !Set(scope.ownedJobs).isSubset(of:record.ownedJobs) {record.state = .refused(.scopeChanged)}
        else {record.state=evaluate(snapshot)}
        record.previous=max(record.previous,now);if tick.isFinite {record.previousUptime=max(record.previousUptime,tick)};pending[scope.service]=record
        return ServiceDrainProgress(state:record.state,revokeOwned:scope.ownedJobs.filter {record.ownedJobs.contains($0)})
    }
}
