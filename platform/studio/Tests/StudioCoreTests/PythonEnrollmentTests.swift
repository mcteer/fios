import Foundation
import Darwin

func runPythonEnrollmentTests()throws {
    let state="/Users/mcteer/Library/Application Support/Fios/Studio"
    let value:[String:Any]=["version":1,"purpose":"reviewed_platform_python_worker","uid":Int(geteuid()),"host":"fios-edge-a.lab","state_path":state,
        "review_sha256":String(repeating:"a",count:64),"manager_sha256":String(repeating:"b",count:64),"manifest_sha256":String(repeating:"c",count:64),
        "python_sha256":String(repeating:"d",count:64),"uv_lock_sha256":String(repeating:"e",count:64),"producer_sha256":String(repeating:"f",count:64),
        "release_template_sha256":String(repeating:"8",count:64),"policy_sha256":String(repeating:"9",count:64),"python_version":"3.11.17","package_version":"0.1.0"]
    let bytes=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
    let document=try PythonRuntimeEnrollmentDocument(bytes)
    guard document.matches(uid:geteuid(),host:"fios-edge-a.lab",statePath:state),
          !document.matches(uid:geteuid(),host:"fios-edge-b.lab",statePath:state),
          !document.matches(uid:geteuid(),host:"fios-edge-a.lab",statePath:state+"-other") else {throw RuntimeError.identity}
    for (key,replacement) in [("host","fios-core.lab"),("python_version","3.15.0"),("package_version","unknown")] {
        var changed=value;changed[key]=replacement
        do {_=try PythonRuntimeEnrollmentDocument(JSONSerialization.data(withJSONObject:changed));throw RuntimeError.identity}
        catch ControlError.unauthorized {}
    }
    guard try PythonRuntimeEnrolledPolicy.load(directory:URL(fileURLWithPath:state))==nil else {throw RuntimeError.identity}
    print("PASS: fixed Python policy metadata binds Studio/user/state and development image cannot construct installed factory policy; no root writes or child execution")
}
