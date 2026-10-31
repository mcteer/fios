import Foundation

func runContractTests() throws {
    struct Vector:Decodable {let name:String;let accept:Bool;let json:String}
    struct Clock:Decodable {let name:String;let now:Int64;let sampled:Int64;let accept:Bool}
    struct Fixture:Decodable {
        let version:Int;let control:[Vector];let limits:[String:Int]
        let roles:[String:[String]];let operations:[String];let states:[String:[String]];let fake_clock:[Clock]
    }
    let path=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/platform/contracts.json")
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:path))
    guard fixture.version==1,!fixture.control.isEmpty else {fatalError("Unsupported contract fixture")}
    for vector in fixture.control {
        var accepted=false
        do {_=try ControlRequest.decode(Data(vector.json.utf8));accepted=true} catch {}
        guard accepted==vector.accept else {fatalError("Contract fixture mismatch: \(vector.name)")}
    }
    let roles:[String:ControlRole] = ["observer":.observer,"task":.task,"operator":.operator,"sandbox":.sandbox]
    guard Set(fixture.roles.keys)==Set(roles.keys),Set(fixture.operations).count==13,fixture.operations.count==13 else {fatalError("Role/operation fixture incomplete")}
    for (name,role) in roles {
        let allowed=Set(fixture.roles[name]!)
        guard allowed.count==fixture.roles[name]!.count,allowed.isSubset(of:Set(fixture.operations)) else {fatalError("Unknown fixture permission")}
        for raw in fixture.operations {
            guard let operation=ControlOperation(rawValue:raw),role.allows(operation)==allowed.contains(raw) else {fatalError("Role matrix diverged")}
        }
    }
    func states<T:RawRepresentable & CaseIterable & Decodable>(_ type:T.Type,_ key:String) throws where T.RawValue==String {
        guard let expected=fixture.states[key],Set(expected)==Set(T.allCases.map(\.rawValue)),expected.count==T.allCases.count else {fatalError("State fixture incomplete")}
        for text in expected {
            let encoded=try JSONSerialization.data(withJSONObject:text,options:.fragmentsAllowed)
            guard try JSONDecoder().decode(T.self,from:encoded).rawValue==text else {fatalError("State fixture did not round trip")}
        }
        for text in ["\"UNKNOWN\"","true","0","null"] {
            do {_=try JSONDecoder().decode(T.self,from:Data(text.utf8));fatalError("Coerced/unknown state accepted")}catch is DecodingError {}
        }
    }
    guard fixture.states.count==11 else {fatalError("State fixture vocabulary changed")}
    try states(ManagedService.self,"service");try states(ServiceDesired.self,"desired");try states(ServiceObserved.self,"observed")
    try states(ReservationState.self,"reservation");try states(NativeCoverage.self,"coverage");try states(NativeActivityState.self,"activity")
    try states(InferenceState.self,"inference");try states(JobKind.self,"job_kind");try states(JobState.self,"job")
    try states(MemoryPressure.self,"pressure");try states(ThermalState.self,"thermal")
    let limits=["control_bytes":65536,"native_raw_bytes":1048576,"utc_max":9007199254740991,"chunk_bytes":32768,"input_bytes":4194304,"upload_ms":10000,"artifact_ms":30000,"lease_ms":30000,"model_chunk_utf16":8192,"model_request_input_utf16":128000,"model_request_output_utf16":64000,"model_job_requests":4,"worker_bytes":536870912,"output_events":64,"output_queue_bytes":1048576,"output_backpressure_ms":2000]
    guard fixture.limits==limits,fixture.limits["control_bytes"]==WireLimits.controlJSON,
          fixture.limits["native_raw_bytes"]==WireLimits.nativeRawObservation,
          Int64(fixture.limits["utc_max"]!)==WireScalar.maximumTimestamp else {fatalError("Unexpected contract limits")}
    let valid=fixture.control.first(where:{$0.accept})!
    var exact=Data(valid.json.utf8)
    exact.append(Data(repeating:32,count:fixture.limits["control_bytes"]!-exact.count))
    _=try ControlRequest.decode(exact)
    exact.append(32)
    do {_=try ControlRequest.decode(exact);fatalError("Oversize fixture accepted")}catch ControlError.invalid_request {}
    guard fixture.fake_clock.count==7 else {fatalError("Clock fixture incomplete")}
    for vector in fixture.fake_clock {
        // Pure synthetic authority for policy boundaries, NEVER an enrolled
        // production native profile or claim of real device idle.
        let sample=NativeSnapshot(host:"edge-a",endpointHash:String(repeating:"a",count:64),nativeEpoch:"fixture",sequence:1,
                                  sampledAt:vector.sampled,allClientLifecycleCoverage:true,residentModel:"fixture",outstandingOwners:0,loading:false)
        var accepted=false
        do {_=try ActivityPolicy.evaluate(sample,now:vector.now);accepted=true}catch{}
        guard accepted==vector.accept else {fatalError("Fake-clock fixture mismatch: \(vector.name)")}
    }
    print("PASS: shared schema/role/state/limit vectors, exact64KiB boundary, unknown/coerced rejection and fake-clock age/future boundaries")
}
