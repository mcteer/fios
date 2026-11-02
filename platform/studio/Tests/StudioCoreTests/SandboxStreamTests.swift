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
    let receipt=try JSONSerialization.jsonObject(with:stream.saved(id:id,artifactID:saved)) as! [String:Any]
    guard receipt["artifact_id"] as? String==saved else {fatalError("Generated artifact identity lost")}
    do {_=try stream.saved(id:id,artifactID:saved);fatalError("Artifact receipt replayed")} catch ControlError.invalid_request {}
    guard case .done(true)=try stream.accept(frame("done",["status":"complete","exit_code":0,"output_bytes":text.count+data.count]),now:1005) else {fatalError("Correlated completion not accepted")}
    do {_=try stream.accept(frame("output",["stream":"stdout","index":1,"data":text.base64EncodedString()]),now:1006);fatalError("Terminal stream revived")} catch ControlError.invalid_request {}
    var stalled=try SandboxStream(now:1000)
    _=try stalled.accept(frame("artifact.begin",["id":id,"length":data.count,"sha256":hash]),now:1001)
    do {try stalled.validate(now:31001);fatalError("Silent artifact deadline not enforced")} catch TransferError.expired {}
    var excessive=try SandboxStream(now:1000)
    do {_=try excessive.accept(frame("artifact.begin",["id":id,"length":(16<<20)+1,"sha256":hash]),now:1001);fatalError("Artifact declaration exceeded shared budget")} catch TransferError.invalid {}
    var forged=try SandboxStream(now:1000)
    do {_=try forged.accept(frame("done",["status":"complete","exit_code":true,"output_bytes":0]),now:1001);fatalError("Boolean exit code accepted")} catch ControlError.invalid_request {}
    print("PASS: stdout remains data, finite shared output/artifact budget, ordered hash-verified export, once-only receipt, silent deadline and exact terminal accounting")
}
