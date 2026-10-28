import Foundation

func runObservationTests() throws {
    let endpoint=String(repeating:"a",count:64),profile=String(repeating:"b",count:64)
    let manager=UUID().uuidString.lowercased()
    // Synthetic trusted enrollment only; never derive these expected epochs
    // from the observation under validation. No native acceptance claimed.
    func enrolled(_ epoch:String)->ObservationValidator {
        ObservationValidator(host:"fios-edge-a.lab",endpointHash:endpoint,profileHash:profile,managerEpoch:manager,nativeEpoch:epoch)
    }
    var validator=enrolled("native-one")
    func data(epoch:String,sequence:Int,sampled:Int=1000,host:String="fios-edge-a.lab",coverage:String="all_clients",frameManager:String?=nil) throws -> Data {
        try JSONSerialization.data(withJSONObject:["version":1,"host":host,"endpoint_hash":endpoint,"profile_hash":profile,
            "manager_epoch":frameManager ?? manager,"native_epoch":epoch,"sequence":sequence,"sampled_at":sampled,
            "coverage":coverage,"resident_model":NSNull(),"outstanding_owners":0,"loading":false])
    }
    do {_=try validator.accept(data(epoch:"native-one",sequence:1,coverage:"supported"),now:1000);fatalError("Non-contract coverage token accepted")}catch ObservationError.invalid {}
    guard try validator.accept(data(epoch:"native-one",sequence:1),now:1000) == .idle else { fatalError("Authoritative idle rejected") }
    do { _=try validator.accept(data(epoch:"native-one",sequence:1),now:1001);fatalError("Snapshot replay accepted") } catch ObservationError.replay {}
    do { _=try validator.accept(data(epoch:"native-one",sequence:2,host:"other"),now:1001);fatalError("Cross-host snapshot accepted") } catch ObservationError.identity {}
    do { _=try validator.accept(data(epoch:"native-two",sequence:1,sampled:1001),now:1001);fatalError("Unenrolled native generation was accepted as authoritative idle") } catch ObservationError.identity {}
    do { _=try validator.accept(data(epoch:"native-one",sequence:2,sampled:1002),now:1002);fatalError("Generation-fenced validator revived its old idle binding") } catch ObservationError.identity {}
    validator=enrolled("native-two") // Separate synthetic fresh generation proof.
    guard try validator.accept(data(epoch:"native-two",sequence:1,sampled:1001),now:1001) == .idle else { fatalError("Separately enrolled native epoch rejected") }
    do { _=try validator.accept(data(epoch:"native-two",sequence:2,sampled:1001),now:7000);fatalError("Stale observation accepted") } catch PolicyError.staleObservation {}
    do { _=try validator.accept(data(epoch:"native-one",sequence:3,sampled:1002),now:1002);fatalError("Retired native epoch replay accepted") } catch ObservationError.identity {}
    var managerFence=enrolled("native-two")
    _=try managerFence.accept(data(epoch:"native-two",sequence:1),now:1000)
    do {_=try managerFence.accept(data(epoch:"native-two",sequence:2,sampled:1001,frameManager:UUID().uuidString.lowercased()),now:1001);fatalError("Unenrolled manager generation accepted")}catch ObservationError.identity {}
    do {_=try managerFence.accept(data(epoch:"native-two",sequence:3,sampled:1002),now:1002);fatalError("Old manager binding revived after generation fence")}catch ObservationError.identity {}
    print("PASS: host/endpoint/profile and separately enrolled manager/native generations; freshness, canonical all_clients coverage, sequence replay and permanent generation fences (synthetic enrollment only)")
}
