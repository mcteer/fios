import Foundation

struct NativeCaptureMetadata {
    let instance:String
    let sequence:UInt64
    let sampledAt:Int64
}

// Receipt time and optional source capture time remain distinct.
// This diagnostic view cannot create a NativeSnapshot or authorize an action.
struct NativeControlDiagnostics {
    let configured:Bool
    private var value:NativeIngressStatus?
    private var receivedAt:Int64?
    private var unavailable=false
    private var fenced=false
    private var instance:String?
    private var previousNow:Int64 = -1
    private var previousReceipt:Int64 = -1
    private var sourceSequence:UInt64=0
    private var sourceTime:Int64 = -1
    private var seenUncertainty=false
    private var backendObservations:NativeBackendFenceDiagnostics
    private var primaryObservations:NativePrimaryActivityDiagnostics
    init(configured:Bool,backendFencesConfigured:Bool=false,primaryActivityConfigured:Bool=false) {
        self.configured=configured;backendObservations=NativeBackendFenceDiagnostics(configured:backendFencesConfigured);primaryObservations=NativePrimaryActivityDiagnostics(configured:primaryActivityConfigured)
    }
    mutating func begin(retainingObservation:Bool=false) {
        if !retainingObservation {value=nil;receivedAt=nil;unavailable=false}
    }
    @discardableResult mutating func completed(_ value:NativeIngressStatus,receivedAt:Int64,backendFences:Result<NativeBackendFenceSample,NativeControlError>?=nil,primaryActivity:Result<NativePrimaryActivitySample,NativeControlError>?=nil,now:Int64?=nil)->Bool {
        let now=now ?? receivedAt
        guard configured,!fenced,(0...ActivityPolicy.maximumTimestamp).contains(now) else {failed();return false}
        guard now>=previousNow else {fenced=true;failed();return false}
        previousNow=now // Rejected replies cannot hide a later observed clock rollback.
        guard fresh(receivedAt,now:now),(try? NativeControlWire.instanceBytes(value.instance)) != nil,
              value.status == .ok || value.status == .maintenance else {failed();return false}
        guard instance==nil || instance==value.instance,receivedAt>=previousReceipt,
              !(seenUncertainty && !value.uncertain) else {fenced=true;failed();return false}
        if let sequence=value.nativeSampleSequence {
            guard sequence>sourceSequence,sequence<=UInt64(ActivityPolicy.maximumTimestamp),
                  let time=value.nativeSampledAt,fresh(time,now:now) else {failed();return false}
            guard time>=sourceTime else {fenced=true;failed();return false}
            sourceSequence=sequence;sourceTime=time
        } else {
            guard value.nativeSampledAt==nil else {failed();return false}
            // Legacy receipt-only diagnostics are not native captures. They
            // never reset the last accepted source counter/time checkpoint.
        }
        instance=value.instance;previousReceipt=receivedAt
        seenUncertainty = seenUncertainty || value.uncertain
        self.value=value;self.receivedAt=receivedAt;unavailable=false
        backendObservations.bind(instance:value.instance)
        primaryObservations.bind(instance:value.instance)
        if let primaryActivity {
            switch primaryActivity {
            case .success(let sample):primaryObservations.completed(sample,expectedInstance:value.instance,now:now)
            case .failure:primaryObservations.failed()
            }
        }
        if let backendFences {
            switch backendFences {
            case .success(let sample):backendObservations.completed(sample,expectedInstance:value.instance,now:now)
            case .failure:backendObservations.failed()
            }
        }
        return true
    }
    mutating func failed() {value=nil;receivedAt=nil;unavailable=true;backendObservations.failed();primaryObservations.failed()}
    private func fresh(_ time:Int64,now:Int64)->Bool {
        (0...ActivityPolicy.maximumTimestamp).contains(time) && (0...ActivityPolicy.maximumTimestamp).contains(now) &&
        (-1000...5000).contains(now-time)
    }
    func capture(now:Int64)->NativeCaptureMetadata? {
        guard configured,!fenced,now>=previousNow,let value,let receivedAt,fresh(receivedAt,now:now),
              let sequence=value.nativeSampleSequence,sequence>0,sequence<=UInt64(ActivityPolicy.maximumTimestamp),
              let sampledAt=value.nativeSampledAt,fresh(sampledAt,now:now) else {return nil}
        return NativeCaptureMetadata(instance:value.instance,sequence:sequence,sampledAt:sampledAt)
    }
    func ingressSample(now:Int64)->PlatformNativeIngressSample? {
        guard configured,!fenced,now>=previousNow,let value,let receivedAt,fresh(receivedAt,now:now),
              value.nativeSampledAt.map({fresh($0,now:now)}) ?? true else {return nil}
        return PlatformNativeIngressSample(receivedAt:receivedAt,sourceSampledAt:value.nativeSampledAt,
            owners:value.owners,ingress:value.ingress,preparing:value.preparing,active:value.active,
            responding:value.responding,modelIdentities:value.modelIdentities,closed:value.closed,trackerUncertain:value.uncertain)
    }
    func summary(now:Int64)->[String:Any] {
        var output:[String:Any]=["version":1,"scope":"native_ingress_tracker","authoritative":false,
            "state":configured ? (fenced ? "fenced":unavailable ? "unavailable":"waiting"):"unconfigured",
            "received_at":NSNull(),"receipt_age_ms":NSNull(),"source_sampled_at":NSNull(),
            "source_sequence":NSNull(),"source_age_ms":NSNull(),"source_instance":NSNull(),"reported_counts":NSNull(),
            "ingress_closed":NSNull(),"tracker_uncertain":NSNull()]
        if primaryObservations.configured {output["primary_activity"]=primaryObservations.summary(now:now)}
        if backendObservations.configured {output["backend_fences"]=backendObservations.summary(now:now)}
        guard configured,!fenced,let value,let receivedAt,
              (0...ActivityPolicy.maximumTimestamp).contains(receivedAt),
              (0...ActivityPolicy.maximumTimestamp).contains(now) else {return output}
        let age=now-receivedAt
        output["received_at"]=receivedAt;output["receipt_age_ms"]=age
        if let sequence=value.nativeSampleSequence {output["source_sequence"]=sequence}
        if let stamp=value.nativeSampledAt,(0...ActivityPolicy.maximumTimestamp).contains(stamp) {
            output["source_sampled_at"]=stamp;output["source_age_ms"]=now-stamp
        }
        guard now>=previousNow,(-1000...5000).contains(age),value.nativeSampledAt.map({fresh($0,now:now)}) ?? true else {output["state"]="stale";return output}
        output["state"]="received";output["source_instance"]=value.instance
        output["ingress_closed"]=value.closed;output["tracker_uncertain"]=value.uncertain
        output["reported_counts"]=["owners":value.owners,"ingress":value.ingress,"preparing":value.preparing,
            "active":value.active,"responding":value.responding,"model_identities":value.modelIdentities]
        return output
    }
}
