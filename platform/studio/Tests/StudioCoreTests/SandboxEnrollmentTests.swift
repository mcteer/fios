import Foundation

func runSandboxEnrollmentTests()throws {
    let runtimeHash=String(repeating:"a",count:64),image="sha256:"+String(repeating:"b",count:64)
    let value:[String:Any]=["version":1,"purpose":"reviewed_platform_sandbox_images",
        "runtime_policy_sha256":runtimeHash,"review_sha256":String(repeating:"c",count:64),"images":[image]]
    let document=try SandboxEnrollmentDocument(JSONSerialization.data(withJSONObject:value))
    guard document.images==[image],document.matches(runtimePolicySHA256:runtimeHash),
          !document.matches(runtimePolicySHA256:String(repeating:"d",count:64)) else {throw RuntimeError.identity}
    var empty=value;empty["images"]=[] as [String]
    do {_=try SandboxEnrollmentDocument(JSONSerialization.data(withJSONObject:empty));throw RuntimeError.identity}
    catch ControlError.unauthorized {}
    // This is the actual development executable, not a substituted root reader
    // or a positive installed policy fixture. Construction starts no child.
    guard try SandboxEnrolledPolicy.load(directory:FileManager.default.temporaryDirectory)==nil else {throw RuntimeError.identity}
    print("PASS: sandbox image metadata binds one exact runtime policy; development binary cannot obtain installed executor policy; no runtime action")
}
