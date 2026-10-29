import Foundation

enum ActivityCoherenceTests {
    static func run() {
        func counts(_ ingress:Int=0,_ preparing:Int=0,_ queued:Int=0,_ active:Int=0,_ responding:Int=0) -> NativePhaseCounts {
            NativePhaseCounts(ingress:ingress,preparing:preparing,queued:queued,active:active,responding:responding)
        }
        func model(_ name:String="model-a",_ value:NativePhaseCounts = .zero,_ resident:Bool=true) -> NativeModelActivity {
            NativeModelActivity(model:name,resident:resident,counts:value)
        }
        func evaluate(_ totals:NativePhaseCounts = .zero,_ models:[NativeModelActivity] = [],
                      unattributed:NativePhaseCounts = .zero,coverage:NativeCoverage = .all_clients,
                      ceiling:NativeCoverage = .all_clients,transitioning:Bool=false) -> CoherentNativeActivity {
            NativeActivityCoherence.evaluate(coverage:coverage,sourceCoverage:ceiling,totals:totals,
                unattributed:unattributed,models:models,transitioning:transitioning)
        }
        func unknown(_ result:CoherentNativeActivity) {
            precondition(result.state == .unknown && result.model == nil && result.owners == nil,
                         "Uncertain activity became attributed or eligible")
            precondition(!result.permits(target:"model-a"))
        }
        let idle = evaluate(.zero,[model()])
        precondition(idle.state == .idle && idle.owners == 0 && idle.permits(target:"model-b"))
        precondition(evaluate().state == .idle)
        for (value,state) in [(counts(1),NativeActivityState.preparing),(counts(0,1),.preparing),
                              (counts(0,0,1),.queued),(counts(0,0,0,1),.active),(counts(0,0,0,0,1),.active)] {
            let view = evaluate(value,[model("model-a",value)])
            precondition(view.state == state && view.owners == 1 && view.model == "model-a")
            precondition(!view.permits(target:"model-b"))
            precondition(view.permits(target:"model-a") == (state != .preparing))
        }
        // A slow response remains owned even with no compute or queued work.
        let response = counts(0,0,0,0,2)
        precondition(evaluate(response,[model("model-a",response)]).owners == 2)
        unknown(evaluate(response,[model()])) // Contradictory aggregate.
        unknown(evaluate(.zero,[model("a"),model("b")])) // Multiple residents.
        unknown(evaluate(.zero,[model(),model()])) // Duplicate byte identity.
        unknown(evaluate(counts(0,0,0,1),[],unattributed:counts(0,0,0,1)))
        unknown(evaluate(.zero,[],transitioning:true))
        unknown(evaluate(.zero,[],ceiling:.unknown))
        unknown(evaluate(.zero,[],coverage:.unknown))
        precondition(evaluate(.zero,[],ceiling:.unsupported).coverage == .unsupported)
        unknown(evaluate(counts(-1),[model("a",counts(-1))]))
        unknown(evaluate(counts(Int(Int32.max)+1),[model("a",counts(Int(Int32.max)+1))]))
        // Individual counters fit but aggregate owners do not.
        let overflow = counts(Int(Int32.max),1)
        unknown(evaluate(overflow,[model("a",overflow)]))
        unknown(evaluate(counts(Int(Int32.max)),[model("a",counts(Int(Int32.max)),false),model("b",counts(1),false)]))
        let sixtyFour = (0..<64).map { model("m\($0)",.zero,false) }
        precondition(evaluate(.zero,sixtyFour).state == .idle)
        unknown(evaluate(.zero,sixtyFour + [model("overflow",.zero,false)]))
        unknown(evaluate(.zero,[model("")]))
        unknown(evaluate(counts(0,0,1),[model("active",counts(0,0,1),false),model("other")]))
        unknown(evaluate(counts(0,0,2),[model("a",counts(0,0,1),false),model("b",counts(0,0,1),false)]))
        // Swift String equality folds canonical Unicode; exact model IDs must not.
        let composed = "caf\u{00e9}", decomposed = "cafe\u{0301}"
        precondition(composed == decomposed)
        let unicode = evaluate(counts(0,0,1),[model(composed,counts(0,0,1))])
        precondition(unicode.permits(target:composed) && !unicode.permits(target:decomposed))
        precondition(evaluate(.zero,[model(composed,.zero,false),model(decomposed,.zero,false)]).state == .idle)
        unknown(evaluate(counts(0,0,1),[model(composed,counts(0,0,1),false),model(decomposed)]))
    }
}
