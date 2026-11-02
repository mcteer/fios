import Foundation
import Darwin

func runSessionEnrollmentTests()throws {
    let hash=String(repeating:"a",count:64)
    let base:[String:Any]=["version":1,"purpose":"reviewed_session_launch","uid":geteuid(),"host":"fios-edge-a.lab",
        "state_path":"/Users/operator/Library/Application Support/Fios/Studio","review_sha256":hash,
        "manager_sha256":hash,"session_sha256":hash,"mlx_application_sha256":hash,"orbstack_application_sha256":hash]
    func packet(_ overrides:[String:Any]=[:])throws->Data {
        var value=base;for (key,item) in overrides {value[key]=item};return try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
    }
    let document=try SessionEnrollmentDocument(packet())
    guard document.uid==geteuid(),document.host=="fios-edge-a.lab",document.reviewSHA256==hash,
          document.statePath==base["state_path"] as? String else {fatalError("Enrollment metadata binding lost")}
    let bad:[[String:Any]]=[
        ["version":2],["uid":0],["uid":true],["uid":1.5],["purpose":"development_observation_only"],
        ["host":"foreign.lab"],["host":"FIOS-EDGE-A.LAB"],["review_sha256":"unreviewed"],
        ["manager_sha256":String(repeating:"A",count:64)],["session_sha256":NSNull()],
        ["state_path":"relative"],["state_path":"/Users/operator/../other"],["state_path":"/Users//operator"],
        ["state_path":"/tmp/state\0ignored"],["role":"operator"],["argv":["/bin/sh"]],
        ["mlx_path":"/tmp/foreign"],["activation":true],
    ]
    for changes in bad {
        do {_=try SessionEnrollmentDocument(packet(changes));fatalError("Malformed or widened enrollment accepted")}catch ControlError.unauthorized {}
    }
    let bytes=try packet(),text=String(decoding:bytes,as:UTF8.self)
    for invalid in [Data(text.replacingOccurrences(of:"\"version\":1",with:"\"version\":1.0").utf8),
                    Data(("{\"version\":1,"+text.dropFirst()).utf8),Data(repeating:32,count:4097)] {
        do {_=try SessionEnrollmentDocument(invalid);fatalError("Ambiguous/oversized enrollment accepted")}catch ControlError.unauthorized {}
    }
    print("PASS: strict launch-only enrollment metadata, exact user/host/state/review/hash fields, no caller paths/argv/roles or coerced/duplicate/oversized grants; decoder alone issues no authority")
}
