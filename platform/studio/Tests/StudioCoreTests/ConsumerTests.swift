import Foundation

// Future consumer contract only. No Spec008 import, model selection, network,
// SSH execution, generation enrollment or native serving acceptance.
func runConsumerTests() throws {
    let host="fios-edge-a.lab",endpoint=String(repeating:"a",count:64),profile=String(repeating:"b",count:64)
    let manager=UUID().uuidString.lowercased(),native="separately-reviewed-fixture-native"
    func consumer()->ObservationValidator {
        ObservationValidator(host:host,endpointHash:endpoint,profileHash:profile,managerEpoch:manager,nativeEpoch:native,sourceCoverage:.all_clients)
    }
    func frame(coverage:String="unsupported",sequence:Int=1,managerEpoch:String?=nil)->[String:Any] {
        ["version":1,"host":host,"endpoint_hash":endpoint,"profile_hash":profile,"manager_epoch":managerEpoch ?? manager,
         "native_epoch":native,"sequence":sequence,"sampled_at":1000,"coverage":coverage,
         "resident_model":NSNull(),"outstanding_owners":coverage=="all_clients" ? 0 : NSNull(),
         "loading":coverage=="all_clients" ? false : NSNull()]
    }
    func encode(_ value:[String:Any]) throws -> Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])}
    func refuses(_ bytes:Data) throws {
        var validator=consumer()
        do {_=try validator.accept(bytes,now:1000);fatalError("Consumer accepted a non-contract export")}
        catch { /* Any parse/schema rejection is sufficient; never normalize malformed SSH stdout. */ }
    }
    var validator=consumer()
    guard try validator.accept(encode(frame()),now:1000) == .unknown else {fatalError("Unsupported authenticated export became idle")}
    var unknown=consumer()
    guard try unknown.accept(encode(frame(coverage:"unknown")),now:1000) == .unknown else {fatalError("Unknown coverage became idle")}
    try refuses(encode(["version":1,"ok":true,"observation":frame()]))
    let bytes=try encode(frame())
    try refuses(Data("notice: connected\n".utf8)+bytes)
    try refuses(bytes+Data("\n{}".utf8))
    try refuses(Data("{\"version\":1,\"version\":1}".utf8))
    try refuses(Data(repeating:32,count:(64<<10)+1))
    try refuses(encode(["schema_version":1,"coverage":"unknown","reason":"native_ownership_audit_incomplete","observer_included":true,"owned_requests":0]))
    var rebound=consumer()
    do {_=try rebound.accept(encode(frame(managerEpoch:UUID().uuidString.lowercased())),now:1000);fatalError("Reconnect enrolled a manager generation")}
    catch ObservationError.identity {}
    do {_=try rebound.accept(bytes,now:1000);fatalError("Reconnect cleared generation fence")}
    catch ObservationError.identity {}
    for field in ["host","endpoint_hash","profile_hash"] {
        var altered=frame()
        altered[field] = field == "host" ? "fios-edge-b.lab" : String(repeating:"c",count:64)
        var drifted=consumer()
        do {_=try drifted.accept(encode(altered),now:1000);fatalError("Consumer accepted identity drift")}
        catch ObservationError.identity {}
        do {_=try drifted.accept(bytes,now:1000);fatalError("Identity drift revived without separate enrollment")}
        catch ObservationError.identity {}
    }
    var owners=InferenceOwnership()
    try owners.claim(request:"prior-managed-attempt",model:"org/exact-model")
    try owners.markUncertain(request:"prior-managed-attempt")
    var idle=consumer()
    guard try idle.accept(encode(frame(coverage:"all_clients")),now:1000) == .idle else {fatalError("Synthetic authoritative fixture rejected")}
    guard owners.uncertainCount==1,owners.unresolvedCount==1 else {fatalError("Idle export cleared independent managed uncertainty")}
    print("PASS: future consumer raw-only bounded exports, unsupported/unknown coverage, contamination/diagnostic/envelope/duplicate rejection, permanent generation fences and independent uncertainty (synthetic enrollment; no008 integration)")
}
