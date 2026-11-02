import Foundation

// Diagnostic only. Unknown gaps retain source continuity and sticky uncertainty;
// counts never become resident/idle/all-client or native lifecycle authority.
struct NativePrimaryActivityDiagnostics {
    let configured:Bool
    private var value:NativePrimaryActivitySample?,checkpoint:NativePrimaryActivitySample?
    private var unavailable=false,fenced=false,seenUncertainty=false
    private var previousNow:Int64=0
    init(configured:Bool) {self.configured=configured}
    private func fresh(_ time:Int64,now:Int64)->Bool {
        (0...ActivityPolicy.maximumTimestamp).contains(time) && (0...ActivityPolicy.maximumTimestamp).contains(now) && (-1000...5000).contains(now-time)
    }
    mutating func failed() {value=nil;unavailable=true}
    mutating func bind(instance:String) {
        if let checkpoint,checkpoint.activity.instance != instance {fenced=true;failed()}
    }
    mutating func completed(_ sample:NativePrimaryActivitySample,expectedInstance:String,now:Int64) {
        guard configured,!fenced else {failed();return}
        let activity=sample.activity
        do {try activity.validate()} catch {failed();return}
        guard activity.instance==expectedInstance,(try? NativeControlWire.instanceBytes(activity.instance)) != nil,
              activity.sampleSequence>0,activity.sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
              sample.peer.pid>1,sample.peer.start>0,let stamp=activity.sampledAt,
              fresh(stamp,now:now),fresh(sample.receivedAt,now:now) else {failed();return}
        if let old=checkpoint {
            guard sample.peer.pid==old.peer.pid,sample.peer.start==old.peer.start,
                  sample.peer.executable.path.utf8.elementsEqual(old.peer.executable.path.utf8),sample.peer.executable.sha256==old.peer.executable.sha256,
                  activity.instance==old.activity.instance,stamp>=old.activity.sampledAt!,now>=previousNow,
                  !(seenUncertainty && !activity.uncertain) else {fenced=true;failed();return}
            guard activity.sampleSequence>old.activity.sampleSequence else {failed();return}
        }
        seenUncertainty = seenUncertainty || activity.uncertain
        checkpoint=sample;value=sample;previousNow=now;unavailable=false
    }
    func summary(now:Int64)->[String:Any] {
        var result:[String:Any]=["version":1,"scope":"primary_request_ownership","coverage":"unknown","authority":false,
            "state":configured ? (fenced ? "fenced":unavailable ? "unavailable":"waiting"):"unconfigured",
            "source_instance":NSNull(),"source_sequence":NSNull(),"source_sampled_at":NSNull(),"source_age_ms":NSNull(),
            "received_at":NSNull(),"receipt_age_ms":NSNull(),"reported_counts":NSNull(),"model_identities":NSNull(),"tracker_uncertain":NSNull(),"retained_uncertainty":seenUncertainty]
        guard configured,!fenced,let sample=value,let stamp=sample.activity.sampledAt else {return result}
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else {result["state"]="stale";return result}
        result["source_sequence"]=sample.activity.sampleSequence;result["source_sampled_at"]=stamp;result["source_age_ms"]=now-stamp
        result["received_at"]=sample.receivedAt;result["receipt_age_ms"]=now-sample.receivedAt
        guard now>=previousNow,fresh(stamp,now:now),fresh(sample.receivedAt,now:now) else {result["state"]="stale";return result}
        let activity=sample.activity
        result["state"]="received";result["source_instance"]=activity.instance
        result["reported_counts"]=["owners":activity.owners,"ingress":activity.ingress,"preparing":activity.preparing,"active":activity.active,"responding":activity.responding]
        result["model_identities"]=activity.models.count;result["tracker_uncertain"]=activity.uncertain
        // IDs stay in the typed observation. Exporting all64x1024 bytes would
        // exceed the existing bounded status envelope; never truncate that set.
        return result
    }
}
