import Foundation

// The time below is a transport receipt time, not a native capture timestamp.
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
    func summary(now:Int64)->[String:Any] {
        var output:[String:Any]=["version":1,"scope":"native_ingress_tracker","authoritative":false,
            "state":configured ? (unavailable ? "unavailable":"waiting"):"unconfigured",
            "received_at":NSNull(),"receipt_age_ms":NSNull(),"source_sampled_at":NSNull(),
            "source_sequence":NSNull(),"source_instance":NSNull(),"reported_counts":NSNull(),
            "ingress_closed":NSNull(),"tracker_uncertain":NSNull()]
        guard configured,let value,let receivedAt,
              (0...ActivityPolicy.maximumTimestamp).contains(receivedAt),
              (0...ActivityPolicy.maximumTimestamp).contains(now) else {return output}
        let age=now-receivedAt
        output["received_at"]=receivedAt;output["receipt_age_ms"]=age
        guard (-1000...5000).contains(age) else {output["state"]="stale";return output}
        output["state"]="received";output["source_instance"]=value.instance
        output["ingress_closed"]=value.closed;output["tracker_uncertain"]=value.uncertain
        output["reported_counts"]=["owners":value.owners,"ingress":value.ingress,"preparing":value.preparing,
            "active":value.active,"responding":value.responding,"model_identities":value.modelIdentities]
        return output
    }
}
