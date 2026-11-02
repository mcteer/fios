import Foundation

func runEnumTests() throws {
    func check<T:RawRepresentable & CaseIterable & Codable>(_ type:T.Type,_ expected:Set<String>) throws where T.RawValue == String {
        let values=Array(T.allCases)
        guard Set(values.map(\.rawValue))==expected,values.count==expected.count else {fatalError("Shared wire enum diverged from the fixed data model")}
        for value in values {
            let data=try JSONEncoder().encode(value)
            guard try JSONDecoder().decode(T.self,from:data).rawValue==value.rawValue else {fatalError("Wire enum changed while decoding")}
        }
        for text in ["\"UNKNOWN\"","\"\"","0","true","null","{}","[]"] {
            do {_=try JSONDecoder().decode(T.self,from:Data(text.utf8));fatalError("Unknown or coerced wire enum accepted")}catch is DecodingError {}
        }
    }
    try check(ManagedService.self,["mlx","orbstack"])
    try check(ServiceDesired.self,["running","maintenance","stopped"])
    try check(ServiceObserved.self,["starting","ready","waiting_session","waiting_credentials","stopped","degraded","unknown"])
    try check(ReservationState.self,["reserved","committed","releasing","released"])
    try check(NativeCoverage.self,["all_clients","unknown","unsupported"])
    try check(NativeActivityState.self,["idle","preparing","queued","active","unknown"])
    try check(InferenceState.self,["reserved","dispatched","uncertain","complete","not_sent"])
    try check(JobKind.self,["sandbox","model_only"])
    try check(JobState.self,["reserved","creating","running","revoking","stopping","removing","removed","reconciling"])
    try check(MemoryPressure.self,["normal","warning","critical","unknown"])
    try check(ThermalState.self,["nominal","fair","serious","critical","unknown"])
    guard WireLimits.controlJSON==65_536,WireLimits.nativeRawObservation==1_048_576 else {fatalError("Shared wire bounds changed")}
    let raw=Data(("\""+String(repeating:"x",count:WireLimits.nativeRawObservation-2)+"\"").utf8)
    try StrictJSON.validate(raw,maximum:WireLimits.nativeRawObservation)
    var oversize=raw;oversize.append(32)
    do {try StrictJSON.validate(oversize,maximum:WireLimits.nativeRawObservation);fatalError("Oversize raw native observation accepted")}catch ControlError.invalid_request {}
    print("PASS: fixed shared wire enums, exact raw-observation bound and unknown/coerced state rejection")
}
