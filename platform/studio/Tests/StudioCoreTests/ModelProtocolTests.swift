import Foundation

func runModelProtocolTests() throws {
    let job=UUID().uuidString.lowercased()
    func frame(_ type:String,_ fields:[String:Any]=[:]) throws -> Data {
        try JSONSerialization.data(withJSONObject:["v":1,"type":type,"job_id":job].merging(fields){_,new in new})
    }
    var parser=ModelWorkerProtocol(job:job,attempt:0)
    _=try parser.accept(frame("dispatched",["attempt":0]))
    _=try parser.accept(frame("delta",["content":"answer"]))
    _=try parser.accept(frame("usage",["attempt":0,"posts":1,"output_units":6]))
    guard case .complete=try parser.accept(frame("done",["status":"complete"])) else { fatalError("Correlated completion rejected") }
    do { _=try parser.accept(frame("done",["status":"complete"]));fatalError("Terminal replay accepted") } catch ModelProtocolError.invalid {}
    var missing=ModelWorkerProtocol(job:job,attempt:0)
    do { _=try missing.accept(frame("done",["status":"complete"]));fatalError("Unproved completion accepted") } catch ModelProtocolError.invalid {}
    var units=ModelWorkerProtocol(job:job,attempt:0)
    _=try units.accept(frame("dispatched",["attempt":0]))
    _=try units.accept(frame("delta",["content":"answer"]))
    do { _=try units.accept(frame("usage",["attempt":0,"posts":1,"output_units":5]));fatalError("Underreported usage accepted") } catch ModelProtocolError.invalid {}
    var cancelled=ModelWorkerProtocol(job:job,attempt:0)
    _=try cancelled.accept(frame("dispatched",["attempt":0]))
    _=try cancelled.accept(frame("usage",["attempt":0,"posts":0,"output_units":0]))
    guard case .interrupted=try cancelled.accept(frame("done",["status":"interrupted"])) else { fatalError("Zero-POST revocation rejected") }
    print("PASS: strict correlated model events, exact attempt/usage/output accounting and once-only completion proof")
}
