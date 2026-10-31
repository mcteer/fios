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

func runNativeTimestampedControlTests() throws {
    let now=HostResources.nowMilliseconds()
    let request=try NativeControlWire.request(operation:.observe,instance:nil,sequence:0,version:3)
    precondition(request.count==32 && request[4]==3)
    var reply=Data(repeating:0,count:80)
    reply.replaceSubrange(0..<4,with:Data("FIR9".utf8));reply[4]=3
    reply.replaceSubrange(8..<24,with:Array(repeating:UInt8(9),count:16))
    func write(_ value:UInt64,at:Int) {for index in 0..<8 {reply[at+index]=UInt8(truncatingIfNeeded:value >> (56-index*8))}}
    write(42,at:64);write(UInt64(now-50),at:72)
    let value=try NativeControlWire.reply(reply)
    precondition(value.nativeSampleSequence==42 && value.nativeSampledAt==now-50)
    var diagnostics=NativeControlDiagnostics(configured:true)
    diagnostics.completed(value,receivedAt:now)
    let summary=diagnostics.summary(now:now)
    precondition(summary["source_sequence"] as? UInt64 == 42 && summary["source_sampled_at"] as? Int64 == now-50)
    precondition(summary["source_age_ms"] as? Int64 == 50 && summary["receipt_age_ms"] as? Int64 == 0)
    let capture=diagnostics.capture(now:now)
    precondition(capture?.instance==value.instance && capture?.sequence==42 && capture?.sampledAt==now-50)
    print("PASS: timestamped native control decoding preserves source and receipt clocks separately")
}
