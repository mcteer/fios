import Foundation

func runNativeControlDiagnosticsTests() throws {
    let absent=NativeControlDiagnostics(configured:false).summary(now:1200)
    precondition(absent["state"] as? String == "unconfigured" && absent["authoritative"] as? Bool == false)
    var diagnostics=NativeControlDiagnostics(configured:true)
    precondition(diagnostics.summary(now:1200)["state"] as? String == "waiting")
    let reply=NativeIngressStatus(operation:.observe,status:.ok,instance:String(repeating:"a",count:32),
        pauseSequence:0,owners:1,ingress:0,preparing:0,active:1,responding:0,modelIdentities:1,closed:false,uncertain:false)
    diagnostics.completed(reply,receivedAt:1000)
    let current=diagnostics.summary(now:1200)
    precondition(current["state"] as? String == "received")
    precondition(current["received_at"] as? Int64 == 1000 && current["receipt_age_ms"] as? Int64 == 200)
    precondition(current["source_sampled_at"] is NSNull && current["source_sequence"] is NSNull)
    let counts=current["reported_counts"] as! [String:Int]
    precondition(counts["owners"] == 1 && counts["active"] == 1)
    let old=diagnostics.summary(now:6200)
    precondition(old["state"] as? String == "stale" && old["reported_counts"] is NSNull)
    precondition(old["received_at"] as? Int64 == 1000)
    diagnostics.failed()
    precondition(diagnostics.summary(now:1300)["state"] as? String == "unavailable")
    diagnostics.begin()
    precondition(diagnostics.summary(now:1300)["state"] as? String == "waiting")
    print("PASS: native-control receipt diagnostics, original receipt time and ordinary source availability")
}
