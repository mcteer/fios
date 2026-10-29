import Foundation
import Darwin

func runRuntimeEnrollmentTests()throws {
    let hash=String(repeating:"a",count:64)
    let base:[String:Any]=["version":1,"purpose":"reviewed_platform_runtime","uid":geteuid(),"host":"fios-edge-a.lab",
        "state_path":"/Users/operator/Library/Application Support/Fios/Studio","home_path":"/Users/operator","review_sha256":hash,
        "manager_sha256":hash,"docker_sha256":hash,"orbctl_sha256":hash]
    func packet(_ overrides:[String:Any]=[:])throws->Data {
        var value=base;for (key,item) in overrides {value[key]=item};return try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
    }
    let document=try RuntimeEnrollmentDocument(packet())
    guard document.uid==geteuid(),document.host=="fios-edge-a.lab",document.reviewSHA256==hash,
          document.dockerSHA256==hash,document.orbctlSHA256==hash,document.homePath=="/Users/operator" else {fatalError("Runtime enrollment lost its exact binding")}
    for changes:[String:Any] in [["version":2],["version":true],["uid":0],["uid":1.5],
        ["purpose":"reviewed_session_launch"],["host":"foreign.lab"],["review_sha256":"unknown"],
        ["docker_sha256":String(repeating:"A",count:64)],["orbctl_sha256":NSNull()],
        ["state_path":"relative"],["state_path":"/Users/operator/../other"],["state_path":"/Users//operator"],
        ["state_path":"/tmp/state\0suffix"],["home_path":"/tmp/foreign"],["home_path":"/Users/../operator"],
        ["home_path":"/Users/.."],["home_path":"/Users/operator\0ignored"],["socket":"tcp://127.0.0.1:1"],["docker_path":"/bin/sh"],
        ["environment":["PATH":"/tmp"]],["activation":true],["all_client_coverage":"complete"]] {
        do {_=try RuntimeEnrollmentDocument(packet(changes));fatalError("Malformed or widened runtime enrollment accepted")}catch ControlError.unauthorized {}
    }
    let text=String(decoding:try packet(),as:UTF8.self)
    for bytes in [Data(text.replacingOccurrences(of:"\"version\":1",with:"\"version\":1.0").utf8),
                  Data(("{\"version\":1,"+text.dropFirst()).utf8),Data(repeating:32,count:4097)] {
        do {_=try RuntimeEnrollmentDocument(bytes);fatalError("Ambiguous/oversized runtime enrollment accepted")}catch ControlError.unauthorized {}
    }
    // Ordinary source-test images cannot obtain installed runtime authority,
    // even when their caller supplies a plausible private state directory.
    guard try RuntimeEnrolledPolicy.load(directory:FileManager.default.temporaryDirectory)==nil else {fatalError("Development binary obtained installed runtime policy")}
    print("PASS: strict code-only runtime enrollment document; fixed installed-manager entry and no caller path/socket/environment/native-coverage grant; no runtime action")
}
