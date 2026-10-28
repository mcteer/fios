import Foundation
import Darwin

// Parsing is deliberately separate from issuing an installed enrollment.
// A valid document in user/task/session metadata grants no authority. The
// review hash identifies the operator's review receipt, not a whole-repository
// or native-capability attestation reconstructed by this decoder.
struct SessionEnrollmentDocument {
    let uid:uid_t
    let host:String
    let statePath:String
    let reviewSHA256:String
    let managerSHA256:String
    let sessionSHA256:String
    let applicationHashes:[ManagedService:String]
    init(_ bytes:Data)throws {
        do {
            try StrictJSON.validate(bytes,maximum:4096)
            guard let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  Set(value.keys)==Set(["version","purpose","uid","host","state_path","review_sha256",
                      "manager_sha256","session_sha256","mlx_application_sha256","orbstack_application_sha256"]),
                  WireScalar.integer(value["version"],maximum:1)==1,
                  value["purpose"] as? String=="reviewed_session_launch",
                  let uid=WireScalar.integer(value["uid"],maximum:Int64(UInt32.max)),uid>0,
                  let host=value["host"] as? String,["fios-edge-a.lab","fios-edge-b.lab"].contains(host),
                  let state=value["state_path"] as? String,state.hasPrefix("/"),!state.hasSuffix("/"),
                  !state.contains("\0"),!state.contains("//"),state.utf8.count<Int(MAXPATHLEN),
                  state.dropFirst().split(separator:"/").allSatisfy({$0 != "." && $0 != ".."}),
                  let review=value["review_sha256"] as? String,WireScalar.sha256(review),
                  let manager=value["manager_sha256"] as? String,WireScalar.sha256(manager),
                  let session=value["session_sha256"] as? String,WireScalar.sha256(session),
                  let mlx=value["mlx_application_sha256"] as? String,WireScalar.sha256(mlx),
                  let orb=value["orbstack_application_sha256"] as? String,WireScalar.sha256(orb) else {throw ControlError.unauthorized}
            self.uid=uid_t(uid);self.host=host;statePath=state;reviewSHA256=review
            managerSHA256=manager;sessionSHA256=session;applicationHashes=[.mlx:mlx,.orbstack:orb]
        } catch {throw ControlError.unauthorized}
    }
}
