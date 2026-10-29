import Foundation

enum ActivityCoherenceTests {
    private struct Counts:Decodable {
        let ingress:Int;let preparing:Int;let queued:Int;let active:Int;let responding:Int
        var value:NativePhaseCounts {NativePhaseCounts(ingress:ingress,preparing:preparing,queued:queued,active:active,responding:responding)}
    }
    private struct Model:Decodable {let model:String;let resident:Bool;let phases:Counts}
    private struct Expected:Decodable {let coverage:NativeCoverage;let state:NativeActivityState;let model:String?;let owners:Int?}
    private struct Permit:Decodable {let target:String;let allowed:Bool}
    private struct Case:Decodable {
        let id:String;let coverage:NativeCoverage;let source_coverage:NativeCoverage
        let totals:Counts;let unattributed:Counts;let models:[Model];let transitioning:Bool
        let expected:Expected;let permits:[Permit]
    }
    private struct Fixture:Decodable {let version:Int;let scope:String;let native_authority:Bool;let cases:[Case]}
    static func run()throws {
        let path=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/platform/activity.json")
        let data=try Data(contentsOf:path)
        try StrictJSON.validate(data,maximum:1<<20)
        func exact(_ value:Any?,_ fields:[String])->[String:Any] {
            guard let object=value as? [String:Any],Set(object.keys)==Set(fields) else {preconditionFailure("Activity fixture schema diverged")}
            return object
        }
        let raw=exact(try JSONSerialization.jsonObject(with:data),["version","scope","native_authority","cases"])
        guard let cases=raw["cases"] as? [[String:Any]] else {preconditionFailure("Missing activity fixture cases")}
        let phaseFields=["ingress","preparing","queued","active","responding"]
        for row in cases {
            _=exact(row,["id","coverage","source_coverage","totals","unattributed","models","transitioning","expected","permits"])
            _=exact(row["totals"],phaseFields);_=exact(row["unattributed"],phaseFields)
            _=exact(row["expected"],["coverage","state","model","owners"])
            guard let models=row["models"] as? [[String:Any]],let permits=row["permits"] as? [[String:Any]],!permits.isEmpty else {preconditionFailure("Incomplete activity fixture")}
            for model in models {_=exact(model,["model","resident","phases"]);_=exact(model["phases"],phaseFields)}
            for permit in permits {_=exact(permit,["target","allowed"])}
        }
        let fixture=try JSONDecoder().decode(Fixture.self,from:data)
        let required:Set<String>=["source-ceiling-unknown","source-ceiling-unsupported","claimed-coverage-unknown","claimed-coverage-unsupported",
            "idle-resident","idle-empty","phase-ingress","phase-preparing","phase-queued","phase-active","phase-responding","slow-response",
            "aggregate-mismatch","multiple-residents","duplicate-model","unattributed-active","transitioning","negative-counter","oversize-counter",
            "owner-sum-overflow","model-sum-overflow","model-capacity","model-capacity-overflow","empty-model","model-byte-boundary","model-byte-overflow",
            "busy-nonresident-conflict","multiple-busy-models","unicode-target-byte-identity","unicode-distinct-models","unicode-resident-conflict"]
        precondition(fixture.version==1 && fixture.scope=="normalized_activity_policy_only" && !fixture.native_authority)
        precondition(fixture.cases.count==required.count && Set(fixture.cases.map(\.id))==required,"Required activity cases disappeared or duplicated")
        for row in fixture.cases {
            let result=NativeActivityCoherence.evaluate(coverage:row.coverage,sourceCoverage:row.source_coverage,
                totals:row.totals.value,unattributed:row.unattributed.value,
                models:row.models.map {NativeModelActivity(model:$0.model,resident:$0.resident,counts:$0.phases.value)},transitioning:row.transitioning)
            let sameModel=result.model.map {Data($0.utf8)}==row.expected.model.map {Data($0.utf8)}
            guard result.coverage==row.expected.coverage,result.state==row.expected.state,sameModel,result.owners==row.expected.owners,
                  row.permits.allSatisfy({result.permits(target:$0.target)==$0.allowed}) else {
                FileHandle.standardError.write(Data("ACTIVITY_FIXTURE_MISMATCH: \(row.id)\n".utf8));throw PolicyError.invalidObservation
            }
        }
        print("PASS: 31 strict normalized activity vectors; no native/backend coverage or admission authority")
    }
}
