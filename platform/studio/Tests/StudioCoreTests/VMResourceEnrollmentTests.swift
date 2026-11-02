import Foundation
import CryptoKit

func runVMResourceEnrollmentTests() throws {
    let hash=String(repeating:"a",count:64),image="sha256:"+String(repeating:"b",count:64)
    let base:[String:Any]=["version":1,"purpose":"reviewed_vm_resource_observation","architecture_contract":"orbstack-shared-kernel-2.2.5",
        "runtime_policy_sha256":hash,"orbstack_info_sha256":hash,"review_sha256":hash,"metadata_images":[image]]
    func packet(_ changes:[String:Any]=[:])throws->Data {try JSONSerialization.data(withJSONObject:base.merging(changes){_,new in new},options:[.sortedKeys])}
    let document=try VMResourceEnrollmentDocument(packet())
    guard document.runtimePolicySHA256==hash,document.metadataImages==[image] else {fatalError("Resource policy binding lost")}
    for changes:[String:Any] in [["version":true],["version":2],["purpose":"task_execution"],["architecture_contract":"unknown"],
        ["runtime_policy_sha256":"unknown"],["orbstack_info_sha256":String(repeating:"A",count:64)],["review_sha256":NSNull()],
        ["metadata_images":[]],["metadata_images":[image,image]],["metadata_images":["latest"]],
        ["metadata_images":(0..<9).map {"sha256:"+String(repeating:String($0),count:64)}],
        ["command":["/bin/sh"]],["native_coverage":"all_clients"],["task_execution":true],["image_path":"/tmp/image"]] {
        do {_=try VMResourceEnrollmentDocument(packet(changes));fatalError("Widened/invalid resource policy accepted")}catch ControlError.unauthorized {}
    }
    let bytes=try packet(),text=String(decoding:bytes,as:UTF8.self)
    for value in [Data(("{\"version\":1,"+text.dropFirst()).utf8),Data(text.replacingOccurrences(of:"\"version\":1",with:"\"version\":1.0").utf8),Data(repeating:32,count:4097)] {
        do {_=try VMResourceEnrollmentDocument(value);fatalError("Ambiguous resource policy accepted")}catch ControlError.unauthorized {}
    }
    func info(_ bundle:String="dev.kdrag0n.MacVirt",_ version:String="2.2.5")throws->Data {
        try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":bundle,"CFBundleShortVersionString":version],format:.xml,options:0)
    }
    let validInfo=try info(),infoHash=SHA256.hash(data:validInfo).map {String(format:"%02x",$0)}.joined()
    let bound=try VMResourceEnrollmentDocument(packet(["orbstack_info_sha256":infoHash]))
    try bound.validateContext(runtimePolicySHA256:hash,applicationInfo:validInfo)
    do {try bound.validateContext(runtimePolicySHA256:String(repeating:"c",count:64),applicationInfo:validInfo);fatalError("Foreign runtime metadata accepted")}catch ControlError.unauthorized {}
    do {try bound.validateContext(runtimePolicySHA256:hash,applicationInfo:validInfo+Data([10]));fatalError("Changed Info bytes accepted")}catch ControlError.unauthorized {}
    for raw in [try info("foreign.bundle"),try info("dev.kdrag0n.MacVirt","2.2.6"),Data("{}".utf8),Data(repeating:32,count:65537)] {
        let digest=SHA256.hash(data:raw).map {String(format:"%02x",$0)}.joined()
        let changed=try VMResourceEnrollmentDocument(packet(["orbstack_info_sha256":digest]))
        do {try changed.validateContext(runtimePolicySHA256:hash,applicationInfo:raw);fatalError("Unreviewed application contract accepted")}catch ControlError.unauthorized {}
    }
    guard try VMResourceEnrolledPolicy.load(directory:FileManager.default.temporaryDirectory)==nil else {fatalError("Development image obtained installed resource authority")}
    print("PASS: strict resource policy metadata, exact architecture/runtime/image binding, no command/task/native grant and development issuer refusal; no installed policy or runtime action")
}
