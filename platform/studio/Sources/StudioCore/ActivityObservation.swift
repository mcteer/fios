import Foundation
import CoreFoundation

enum ActivityObservationReason:String,Sendable {
    case none,source_unknown,source_unsupported,source_unavailable,incoherent,local_ownership,observation_too_large,legacy_unsupported
}

struct ActivityObservationMetadata:Sendable {
    let host:String
    let endpointHash:String
    let profileHash:String
    let managerEpoch:String
    let nativeEpoch:String
    let sequence:Int64
    let sampledAt:Int64
    let nativeSequence:Int64?
    let nativeSampledAt:Int64?
    func validate()throws {
        guard WireScalar.host(host),WireScalar.sha256(endpointHash),WireScalar.sha256(profileHash),WireScalar.uuid(managerEpoch),
              !nativeEpoch.isEmpty,nativeEpoch.utf8.count<=128,!nativeEpoch.contains("\0"),
              (1...WireScalar.maximumTimestamp).contains(sequence),(0...WireScalar.maximumTimestamp).contains(sampledAt),
              (nativeSequence==nil)==(nativeSampledAt==nil) else {throw ObservationError.invalid}
        if let nativeSequence,let nativeSampledAt {
            guard (1...WireScalar.maximumTimestamp).contains(nativeSequence),(0...WireScalar.maximumTimestamp).contains(nativeSampledAt),
                  sampledAt-nativeSampledAt >= -1000 else {throw ObservationError.invalid}
        }
    }
}

struct ActivityObservationContext:Sendable {
    var sampledAt:Int64?=nil
    var pressure:MemoryPressure = .unknown
    var thermal:ThermalState = .unknown
    var mlx:ServiceObserved = .unknown
    var orbstack:ServiceObserved = .unknown
}

struct DecodedActivityObservation:Sendable {
    let metadata:ActivityObservationMetadata
    let view:CoherentNativeActivity
    let reason:ActivityObservationReason
    let resourceSampledAt:Int64?
    let legacy:Bool
}

// Bounded readonly evidence only. Independent enrollment supplies a source
// coverage ceiling; no wire frame supplies an admission lease or native proof.
enum ActivityObservationExport {
    // Leave room for the fixed activity control envelope as well as raw SSH
    // export; both transports retain their original64KiB wire limit.
    static let maximumFrameBytes=WireLimits.controlJSON-512
    static let legacyFields:Set<String>=["version","host","endpoint_hash","profile_hash","manager_epoch","native_epoch","sequence","sampled_at","coverage","resident_model","outstanding_owners","loading"]
    static let fields=legacyFields.union(["native_sequence","native_sampled_at","source_age_ms","activity","counts","unattributed_counts","models","transitioning","reason","resources","services","local_ownership"])
    private static let phaseFields:Set<String>=["ingress","preparing","queued","active","responding"]
    private static func number(_ value:Any?,maximum:Int64=WireScalar.maximumTimestamp)->Int64? {WireScalar.integer(value,maximum:maximum)}
    private static func boolean(_ value:Any?)->Bool? {
        guard let value=value as? NSNumber,CFGetTypeID(value)==CFBooleanGetTypeID() else {return nil}
        return value.boolValue
    }
    private static func phases(_ value:Any?)throws->NativePhaseCounts {
        guard let object=value as? [String:Any],Set(object.keys)==phaseFields,
              let ingress=number(object["ingress"],maximum:Int64(Int32.max)),let preparing=number(object["preparing"],maximum:Int64(Int32.max)),
              let queued=number(object["queued"],maximum:Int64(Int32.max)),let active=number(object["active"],maximum:Int64(Int32.max)),
              let responding=number(object["responding"],maximum:Int64(Int32.max)) else {throw ObservationError.invalid}
        return NativePhaseCounts(ingress:Int(ingress),preparing:Int(preparing),queued:Int(queued),active:Int(active),responding:Int(responding))
    }
    private static func object(_ value:NativePhaseCounts)->[String:Int] {
        ["ingress":value.ingress,"preparing":value.preparing,"queued":value.queued,"active":value.active,"responding":value.responding]
    }
    static func encode(metadata:ActivityObservationMetadata,coverage:NativeCoverage,sourceCoverage:NativeCoverage,
                       totals:NativePhaseCounts = .zero,unattributed:NativePhaseCounts = .zero,models:[NativeModelActivity]=[],
                       transitioning:Bool=false,localModels:[String]=[],localUncertain:Bool=false,
                       context:ActivityObservationContext=ActivityObservationContext())throws->Data {
        try metadata.validate()
        if let time=context.sampledAt {guard (0...WireScalar.maximumTimestamp).contains(time) else {throw ObservationError.invalid}}
        else {guard context.pressure == .unknown,context.thermal == .unknown else {throw ObservationError.invalid}}
        var view=NativeActivityCoherence.evaluate(coverage:coverage,sourceCoverage:sourceCoverage,totals:totals,unattributed:unattributed,models:models,transitioning:transitioning)
        var reason:ActivityObservationReason=view.coverage == .unsupported ? .source_unsupported:view.coverage == .unknown ? .source_unknown:view.state == .unknown ? .incoherent:.none
        let localValid=localModels.count<=32 && localModels.allSatisfy(WireScalar.model) && (!localUncertain || !localModels.isEmpty)
        let compatible=localModels.isEmpty || (view.state != .idle && view.model.map { target in localModels.allSatisfy {WireScalar.exactModel($0,target)} } == true)
        let localBlocked = !localValid || localUncertain || !compatible
        if view.state != .unknown,metadata.nativeSequence==nil {
            view=CoherentNativeActivity(coverage:.unknown,state:.unknown,model:nil,owners:nil);reason = .source_unavailable
        }
        if localBlocked,view.state != .unknown {
            view=CoherentNativeActivity(coverage:view.coverage,state:.unknown,model:nil,owners:nil);reason = .local_ownership
        }
        let unknown=view.state == .unknown
        let empty=NSNull()
        var value:[String:Any]=["version":2,"host":metadata.host,"endpoint_hash":metadata.endpointHash,"profile_hash":metadata.profileHash,
            "manager_epoch":metadata.managerEpoch,"native_epoch":metadata.nativeEpoch,"sequence":metadata.sequence,"sampled_at":metadata.sampledAt,
            "native_sequence":metadata.nativeSequence.map {$0 as Any} ?? empty,"native_sampled_at":metadata.nativeSampledAt.map {$0 as Any} ?? empty,
            "source_age_ms":metadata.nativeSampledAt.map {(metadata.sampledAt-$0) as Any} ?? empty,
            "coverage":view.coverage.rawValue,"activity":view.state.rawValue,"resident_model":unknown ? empty as Any:models.first(where:{$0.resident}).map {$0.model as Any} ?? empty,
            "outstanding_owners":view.owners.map {$0 as Any} ?? empty,"loading":unknown ? empty as Any:view.state == .preparing,
            "transitioning":unknown ? empty as Any:false,"counts":unknown ? empty as Any:object(totals),
            "unattributed_counts":unknown ? empty as Any:object(unattributed),"models":unknown ? []:models.map {["model":$0.model,"resident":$0.resident,"counts":object($0.counts)] as [String:Any]},
            "reason":reason.rawValue,"resources":["sampled_at":context.sampledAt.map {$0 as Any} ?? empty,"pressure":context.pressure.rawValue,"thermal":context.thermal.rawValue],
            "services":["mlx":context.mlx.rawValue,"orbstack":context.orbstack.rawValue],
            "local_ownership":["unresolved_count":localValid ? localModels.count as Any:empty,"uncertain":localValid ? localUncertain as Any:empty,"blocked":localBlocked]]
        var data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        if data.count>maximumFrameBytes {
            value["coverage"]="unknown";value["activity"]="unknown";value["reason"]=ActivityObservationReason.observation_too_large.rawValue
            for key in ["resident_model","outstanding_owners","loading","transitioning","counts","unattributed_counts"] {value[key]=empty}
            value["models"]=[]
            data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        }
        guard data.count<=maximumFrameBytes else {throw ObservationError.trackingLimit}
        return data
    }
    static func decode(_ data:Data,allowLegacyUnsupported:Bool=false)throws->DecodedActivityObservation {
        try StrictJSON.validate(data,maximum:WireLimits.controlJSON)
        guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],let version=number(value["version"]),
              Set(value.keys)==(version==1 && allowLegacyUnsupported ? legacyFields:fields),
              let host=value["host"] as? String,let endpoint=value["endpoint_hash"] as? String,let profile=value["profile_hash"] as? String,
              let manager=value["manager_epoch"] as? String,let native=value["native_epoch"] as? String,
              let sequence=number(value["sequence"]),let time=number(value["sampled_at"]),
              let rawCoverage=value["coverage"] as? String,let coverage=NativeCoverage(rawValue:rawCoverage) else {throw ObservationError.invalid}
        func optionalNumber(_ key:String)throws->Int64? {
            if value[key] is NSNull {return nil}
            guard let result=number(value[key]) else {throw ObservationError.invalid};return result
        }
        let metadata=ActivityObservationMetadata(host:host,endpointHash:endpoint,profileHash:profile,managerEpoch:manager,nativeEpoch:native,
            sequence:sequence,sampledAt:time,nativeSequence:version==1 ? nil:try optionalNumber("native_sequence"),nativeSampledAt:version==1 ? nil:try optionalNumber("native_sampled_at"))
        try metadata.validate()
        let unknown=CoherentNativeActivity(coverage:coverage,state:.unknown,model:nil,owners:nil)
        if version==1 {
            guard allowLegacyUnsupported,coverage != .all_clients,
                  value["resident_model"] is NSNull || (value["resident_model"] as? String).map(WireScalar.model)==true,
                  value["outstanding_owners"] is NSNull || number(value["outstanding_owners"],maximum:Int64(Int32.max)) != nil,
                  value["loading"] is NSNull || boolean(value["loading"]) != nil else {throw ObservationError.invalid}
            return DecodedActivityObservation(metadata:metadata,view:unknown,reason:.legacy_unsupported,resourceSampledAt:nil,legacy:true)
        }
        guard version==2,let rawState=value["activity"] as? String,let state=NativeActivityState(rawValue:rawState),
              let rawReason=value["reason"] as? String,let reason=ActivityObservationReason(rawValue:rawReason),
              let resources=value["resources"] as? [String:Any],Set(resources.keys)==Set(["sampled_at","pressure","thermal"]),
              let pressure=resources["pressure"] as? String,MemoryPressure(rawValue:pressure) != nil,
              let thermal=resources["thermal"] as? String,ThermalState(rawValue:thermal) != nil,
              let services=value["services"] as? [String:Any],Set(services.keys)==Set(["mlx","orbstack"]),
              services.values.allSatisfy({($0 as? String).flatMap(ServiceObserved.init(rawValue:)) != nil}),
              let local=value["local_ownership"] as? [String:Any],Set(local.keys)==Set(["unresolved_count","uncertain","blocked"]),
              let blocked=boolean(local["blocked"]),let models=value["models"] as? [[String:Any]],models.count<=64 else {throw ObservationError.invalid}
        let resourceTime:Int64?
        if resources["sampled_at"] is NSNull {
            guard pressure=="unknown",thermal=="unknown" else {throw ObservationError.invalid};resourceTime=nil
        }else {guard let time=number(resources["sampled_at"]) else {throw ObservationError.invalid};resourceTime=time}
        if local["unresolved_count"] is NSNull {
            guard blocked,local["uncertain"] is NSNull,state == .unknown else {throw ObservationError.invalid}
        }else {
            guard let count=number(local["unresolved_count"],maximum:32),let uncertain=boolean(local["uncertain"]),
                  !uncertain || (count>0 && blocked),count>0 || !blocked,count==0 || state != .idle else {throw ObservationError.invalid}
        }
        if let sample=metadata.nativeSampledAt {
            guard let age=value["source_age_ms"] as? NSNumber,CFGetTypeID(age) != CFBooleanGetTypeID(),
                  !["d","f"].contains(String(cString:age.objCType)),Int64(age.stringValue)==metadata.sampledAt-sample else {throw ObservationError.invalid}
        }else {guard value["source_age_ms"] is NSNull else {throw ObservationError.invalid}}
        if state == .unknown {
            guard reason != .none,reason != .legacy_unsupported,models.isEmpty,
                  ["resident_model","outstanding_owners","loading","transitioning","counts","unattributed_counts"].allSatisfy({value[$0] is NSNull}) else {throw ObservationError.invalid}
            return DecodedActivityObservation(metadata:metadata,view:unknown,reason:reason,resourceSampledAt:resourceTime,legacy:false)
        }
        guard coverage == .all_clients,metadata.nativeSequence != nil,reason == .none,!blocked,
              let loading=boolean(value["loading"]),let transition=boolean(value["transitioning"]),!transition else {throw ObservationError.invalid}
        let totals=try phases(value["counts"]),unattributed=try phases(value["unattributed_counts"])
        let entries=try models.map { object -> NativeModelActivity in
            guard Set(object.keys)==Set(["model","resident","counts"]),let model=object["model"] as? String,
                  let resident=boolean(object["resident"]) else {throw ObservationError.invalid}
            return NativeModelActivity(model:model,resident:resident,counts:try phases(object["counts"]))
        }
        let view=NativeActivityCoherence.evaluate(coverage:coverage,sourceCoverage:.all_clients,totals:totals,unattributed:unattributed,models:entries,transitioning:transition)
        let resident=value["resident_model"] as? String,expectedResident=entries.first(where:{$0.resident})?.model
        guard view.state==state,view.owners.map({Int64($0)})==number(value["outstanding_owners"],maximum:Int64(Int32.max)),
              (expectedResident==nil && value["resident_model"] is NSNull) || WireScalar.exactModel(expectedResident,resident),
              loading==(state == .preparing) else {throw ObservationError.invalid}
        return DecodedActivityObservation(metadata:metadata,view:view,reason:reason,resourceSampledAt:resourceTime,legacy:false)
    }
}

public enum ReadonlyObservationFrame {
    // Structural validation for the fixed CLI relay. Consumer enrollment,
    // freshness/replay and independent coverage checks remain mandatory.
    public static func validateStructure(_ data:Data)throws {
        _=try ActivityObservationExport.decode(data,allowLegacyUnsupported:true)
    }
}
