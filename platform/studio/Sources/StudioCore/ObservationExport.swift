import Foundation
import CoreFoundation

enum ObservationError:Error { case invalid, identity, replay, trackingLimit }

// Lives with one enrolled consumer. Both expected generations come from
// separate trusted fresh enrollment, NEVER from the frame being checked.
// Reconnect/health/new timestamps cannot mint a binding or clear old ownership.
// Generation/transport proof and persistence remain separate integration.
struct ObservationValidator {
    let host:String
    let endpointHash:String
    let profileHash:String
    let managerEpoch:String
    let nativeEpoch:String
    private var fenced=false
    private var sequence:UInt64=0
    private var sampled:Int64 = -1
    private var previousNow:Int64 = -1
    init(host:String,endpointHash:String,profileHash:String,managerEpoch:String,nativeEpoch:String) {
        self.host=host;self.endpointHash=endpointHash;self.profileHash=profileHash
        self.managerEpoch=managerEpoch;self.nativeEpoch=nativeEpoch
    }
    mutating func accept(_ data:Data,now:Int64) throws -> HostActivity {
        guard !fenced,WireScalar.host(host),WireScalar.sha256(endpointHash),WireScalar.sha256(profileHash),
              WireScalar.uuid(managerEpoch),!nativeEpoch.isEmpty,nativeEpoch.utf8.count<=128 else {throw ObservationError.identity}
        try StrictJSON.validate(data,maximum:64<<10)
        let fields:Set<String>=["version","host","endpoint_hash","profile_hash","manager_epoch","native_epoch","sequence","sampled_at","coverage","resident_model","outstanding_owners","loading"]
        guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(value.keys)==fields else { throw ObservationError.invalid }
        func integer(_ field:String)->Int64? {WireScalar.integer(value[field])}
        guard let coverage=value["coverage"] as? String,["all_clients","unsupported","unknown"].contains(coverage) else { throw ObservationError.invalid }
        let ownerCount=integer("outstanding_owners") ?? (coverage != "all_clients" && value["outstanding_owners"] is NSNull ? 0 : nil)
        let loadingValue=(value["loading"] as? NSNumber) ?? (coverage != "all_clients" && value["loading"] is NSNull ? NSNumber(value:false) : nil)
        guard integer("version")==1,let seq=integer("sequence"),seq>0,let time=integer("sampled_at"),
              let owners=ownerCount,owners<=Int32.max,
              let manager=value["manager_epoch"] as? String,WireScalar.uuid(manager),
              let epoch=value["native_epoch"] as? String,!epoch.isEmpty,epoch.utf8.count<=128,
              let loading=loadingValue,CFGetTypeID(loading)==CFBooleanGetTypeID(),
              value["resident_model"] is NSNull || value["resident_model"] is String else { throw ObservationError.invalid }
        guard value["host"] as? String==host,value["endpoint_hash"] as? String==endpointHash,
              value["profile_hash"] as? String==profileHash else {
            // An authenticated source changing its enrolled identity is not a
            // transient stale sample. Returning the old tuple cannot re-enroll it.
            fenced=true
            throw ObservationError.identity
        }
        guard epoch==nativeEpoch,manager==managerEpoch else {
            fenced=true
            throw ObservationError.identity
        }
        guard now>=previousNow,time>=sampled else { throw ObservationError.replay }
        guard UInt64(seq)>sequence else {throw ObservationError.replay}
        let snapshot=NativeSnapshot(host:host,endpointHash:endpointHash,nativeEpoch:epoch,sequence:UInt64(seq),sampledAt:time,
            allClientLifecycleCoverage:coverage=="all_clients",residentModel:value["resident_model"] as? String,
            outstandingOwners:Int(owners),loading:loading.boolValue)
        let activity=try ActivityPolicy.evaluate(snapshot,now:now)
        sequence=UInt64(seq);sampled=time;previousNow=now
        return activity
    }
}
