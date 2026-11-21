import Foundation
import CryptoKit

func runSandboxStreamTests() throws {
    func frame(_ kind:String,_ fields:[String:Any]=[:]) throws -> Data {
        try JSONSerialization.data(withJSONObject:fields.merging(["version":1,"type":kind]){_,new in new})
    }
    let data=Data("fixture-export".utf8),id=UUID().uuidString.lowercased()
    let hash=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
    var stream=try SandboxStream(now:1000)
    let text=Data("{\"type\":\"service.force\"}".utf8)
    guard case .output(let name,let index,let received)=try stream.accept(frame("output",["stream":"stdout","index":0,"data":text.base64EncodedString()]),now:1001),name=="stdout",index==0,received==text else {fatalError("Stdout acquired control authority")}
    _=try stream.accept(frame("artifact.begin",["id":id,"length":data.count,"sha256":hash]),now:1002)
    _=try stream.accept(frame("artifact.chunk",["id":id,"index":0,"data":data.base64EncodedString()]),now:1003)
    guard case .artifact(let request,let bytes)=try stream.accept(frame("artifact.end",["id":id]),now:1004),request==id,bytes==data else {fatalError("Artifact transfer was not verified")}
    let saved=UUID().uuidString.lowercased()
    var terminalFirst=stream
    let sibling=UUID().uuidString.lowercased(),siblingSaved=UUID().uuidString.lowercased()
    _=try terminalFirst.accept(frame("artifact.begin",["id":sibling,"length":data.count,"sha256":hash]),now:1005)
    _=try terminalFirst.accept(frame("artifact.chunk",["id":sibling,"index":0,"data":data.base64EncodedString()]),now:1006)
    guard case .artifact(let siblingRequest,let siblingBytes)=try terminalFirst.accept(frame("artifact.end",["id":sibling]),now:1007),
          siblingRequest==sibling,siblingBytes==data else {fatalError("Sibling export lost its request identity")}
    guard case .done(true)=try terminalFirst.accept(frame("done",["status":"complete","exit_code":0,"output_bytes":text.count+2*data.count]),now:1008) else {
        fatalError("Completion could not precede a durable export receipt")
    }
    do {_=try terminalFirst.saved(id:id,artifactID:"invalid");fatalError("Malformed durable receipt accepted")}catch ControlError.invalid_request {}
    do {_=try terminalFirst.saved(id:UUID().uuidString.lowercased(),artifactID:siblingSaved);fatalError("Unrelated receipt accepted")}catch ControlError.invalid_request {}
    let siblingReceipt=try JSONSerialization.jsonObject(with:terminalFirst.saved(id:sibling,artifactID:siblingSaved)) as! [String:Any]
    guard siblingReceipt["id"] as? String==sibling,siblingReceipt["artifact_id"] as? String==siblingSaved else {
        fatalError("Malformed or unrelated receipt consumed sibling acknowledgement")
    }
    let lateReceipt=try JSONSerialization.jsonObject(with:terminalFirst.saved(id:id,artifactID:saved)) as! [String:Any]
    guard lateReceipt["id"] as? String==id,lateReceipt["artifact_id"] as? String==saved else {fatalError("Late receipt lost exact correlation")}
    do {_=try terminalFirst.saved(id:id,artifactID:saved);fatalError("Late receipt replayed")}catch ControlError.invalid_request {}
    let receipt=try JSONSerialization.jsonObject(with:stream.saved(id:id,artifactID:saved)) as! [String:Any]
    guard receipt["artifact_id"] as? String==saved else {fatalError("Generated artifact identity lost")}
    do {_=try stream.saved(id:id,artifactID:saved);fatalError("Artifact receipt replayed")} catch ControlError.invalid_request {}
    guard case .done(true)=try stream.accept(frame("done",["status":"complete","exit_code":0,"output_bytes":text.count+data.count]),now:1005) else {fatalError("Correlated completion not accepted")}
    do {_=try stream.accept(frame("output",["stream":"stdout","index":1,"data":text.base64EncodedString()]),now:1006);fatalError("Terminal stream revived")} catch ControlError.invalid_request {}
    let session=try SandboxTaskSession(source:Data(),deadline:2000,now:1000)
    _=try session.acceptRuntimeFrame(frame("artifact.begin",["id":id,"length":data.count,"sha256":hash]),now:1001)
    _=try session.acceptRuntimeFrame(frame("artifact.chunk",["id":id,"index":0,"data":data.base64EncodedString()]),now:1002)
    let exportEvent=try session.acceptRuntimeFrame(frame("artifact.end",["id":id]),now:1003)
    let terminalEvent=try session.acceptRuntimeFrame(frame("done",["status":"complete","exit_code":0,"output_bytes":data.count]),now:1003)
    guard case .artifact(let request,let bytes)=exportEvent,request==id,bytes==data,
          case .done(true)=terminalEvent,session.terminal,!session.revoked else {fatalError("Terminal batch lost verified export before publication")}
    try session.saved(id:id,artifactID:saved)
    do {try session.saved(id:id,artifactID:saved);fatalError("Terminal session accepted replayed durable receipt")}catch ControlError.invalid_request {}
    do {try session.renew();fatalError("Late durable receipt revived terminal byte session")}catch ControlError.invalid_request {}
    var stalled=try SandboxStream(now:1000)
    _=try stalled.accept(frame("artifact.begin",["id":id,"length":data.count,"sha256":hash]),now:1001)
    do {try stalled.validate(now:31001);fatalError("Silent artifact deadline not enforced")} catch TransferError.expired {}
    var excessive=try SandboxStream(now:1000)
    do {_=try excessive.accept(frame("artifact.begin",["id":id,"length":(16<<20)+1,"sha256":hash]),now:1001);fatalError("Artifact declaration exceeded shared budget")} catch TransferError.invalid {}
    var forged=try SandboxStream(now:1000)
    do {_=try forged.accept(frame("done",["status":"complete","exit_code":true,"output_bytes":0]),now:1001);fatalError("Boolean exit code accepted")} catch ControlError.invalid_request {}
    print("PASS: stdout remains data, finite shared output/artifact budget, ordered hash-verified export, once-only receipt, silent deadline and exact terminal accounting")
}
