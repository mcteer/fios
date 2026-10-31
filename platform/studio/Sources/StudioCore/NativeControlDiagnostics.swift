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
    init(configured:Bool) {self.configured=configured}
    mutating func begin() {value=nil;receivedAt=nil;unavailable=false}
    mutating func completed(_ value:NativeIngressStatus,receivedAt:Int64) {
        self.value=value;self.receivedAt=receivedAt;unavailable=false
    }
    mutating func failed() {value=nil;receivedAt=nil;unavailable=true}
    private func fresh(_ time:Int64,now:Int64)->Bool {
        (0...ActivityPolicy.maximumTimestamp).contains(time) && (0...ActivityPolicy.maximumTimestamp).contains(now) &&
        (-1000...5000).contains(now-time)
    }
    func capture(now:Int64)->NativeCaptureMetadata? {
        guard configured,let value,let receivedAt,fresh(receivedAt,now:now),
              let sequence=value.nativeSampleSequence,sequence>0,sequence<=UInt64(ActivityPolicy.maximumTimestamp),
              let sampledAt=value.nativeSampledAt,fresh(sampledAt,now:now) else {return nil}
        return NativeCaptureMetadata(instance:value.instance,sequence:sequence,sampledAt:sampledAt)
    }
    func ingressSample(now:Int64)->PlatformNativeIngressSample? {
        guard configured,let value,let receivedAt,fresh(receivedAt,now:now),
              value.nativeSampledAt.map({fresh($0,now:now)}) ?? true else {return nil}
        return PlatformNativeIngressSample(receivedAt:receivedAt,sourceSampledAt:value.nativeSampledAt,
            owners:value.owners,ingress:value.ingress,preparing:value.preparing,active:value.active,
            responding:value.responding,modelIdentities:value.modelIdentities,closed:value.closed,trackerUncertain:value.uncertain)
    }
    func summary(now:Int64)->[String:Any] {
        var output:[String:Any]=["version":1,"scope":"native_ingress_tracker","authoritative":false,
            "state":configured ? (unavailable ? "unavailable":"waiting"):"unconfigured",
            "received_at":NSNull(),"receipt_age_ms":NSNull(),"source_sampled_at":NSNull(),
            "source_sequence":NSNull(),"source_age_ms":NSNull(),"source_instance":NSNull(),"reported_counts":NSNull(),
            "ingress_closed":NSNull(),"tracker_uncertain":NSNull()]
        guard configured,let value,let receivedAt,
              (0...ActivityPolicy.maximumTimestamp).contains(receivedAt),
              (0...ActivityPolicy.maximumTimestamp).contains(now) else {return output}
        let age=now-receivedAt
        output["received_at"]=receivedAt;output["receipt_age_ms"]=age
        if let sequence=value.nativeSampleSequence {output["source_sequence"]=sequence}
        if let stamp=value.nativeSampledAt,(0...ActivityPolicy.maximumTimestamp).contains(stamp) {
            output["source_sampled_at"]=stamp;output["source_age_ms"]=now-stamp
        }
        guard (-1000...5000).contains(age),value.nativeSampledAt.map({fresh($0,now:now)}) ?? true else {output["state"]="stale";return output}
        output["state"]="received";output["source_instance"]=value.instance
        output["ingress_closed"]=value.closed;output["tracker_uncertain"]=value.uncertain
        output["reported_counts"]=["owners":value.owners,"ingress":value.ingress,"preparing":value.preparing,
            "active":value.active,"responding":value.responding,"model_identities":value.modelIdentities]
        return output
    }
}
