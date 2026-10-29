import Foundation
import Darwin
import CryptoKit

// Decoded review metadata, never a capability, executable or task-image grant.
struct VMResourceEnrollmentDocument {
    let runtimePolicySHA256:String
    let orbstackInfoSHA256:String
    let reviewSHA256:String
    let metadataImages:Set<String>
    init(_ bytes:Data)throws {
        do {
            try StrictJSON.validate(bytes,maximum:4096)
            guard let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  Set(value.keys)==Set(["version","purpose","architecture_contract","runtime_policy_sha256","orbstack_info_sha256","review_sha256","metadata_images"]),
                  WireScalar.integer(value["version"],maximum:1)==1,
                  value["purpose"] as? String=="reviewed_vm_resource_observation",
                  value["architecture_contract"] as? String=="orbstack-shared-kernel-2.2.5",
                  let runtime=value["runtime_policy_sha256"] as? String,WireScalar.sha256(runtime),
                  let info=value["orbstack_info_sha256"] as? String,WireScalar.sha256(info),
                  let review=value["review_sha256"] as? String,WireScalar.sha256(review),
                  let images=value["metadata_images"] as? [String],(1...8).contains(images.count),Set(images).count==images.count,
                  images.allSatisfy({$0.hasPrefix("sha256:") && $0.utf8.count==71 && WireScalar.sha256(String($0.dropFirst(7)))}) else {throw ControlError.unauthorized}
            runtimePolicySHA256=runtime;orbstackInfoSHA256=info;reviewSHA256=review;metadataImages=Set(images)
        } catch {throw ControlError.unauthorized}
    }
    // Pure metadata validation, returning no authority-bearing object.
    func validateContext(runtimePolicySHA256:String,applicationInfo:Data)throws {
        do {
            guard runtimePolicySHA256==self.runtimePolicySHA256,(1...65536).contains(applicationInfo.count),
                  SHA256.hash(data:applicationInfo).map({String(format:"%02x",$0)}).joined()==orbstackInfoSHA256,
                  let plist=try PropertyListSerialization.propertyList(from:applicationInfo,format:nil) as? [String:Any],
                  plist["CFBundleIdentifier"] as? String=="dev.kdrag0n.MacVirt",
                  plist["CFBundleShortVersionString"] as? String=="2.2.5" else {throw ControlError.unauthorized}
        } catch {throw ControlError.unauthorized}
    }
}

// Fixed installed manager + root-protected policy + opaque runtime enrollment.
// Construction sends no daemon/CLI request and starts no process or container.
// Images authorize only the fixed existing owned-target metadata reader, never
// ordinary task execution, bootstrap creation, MLX admission or lifecycle work.
struct VMResourceEnrolledPolicy {
    static let policyPath="/Library/Application Support/Fios/Studio/resource-enrollment.json"
    private let runtime:RuntimeEnrolledPolicy
    private let document:VMResourceEnrollmentDocument
    private let profileSHA256:String
    private init(runtime:RuntimeEnrolledPolicy,document:VMResourceEnrollmentDocument,policySHA256:String) {
        self.runtime=runtime;self.document=document
        profileSHA256=SHA256.hash(data:Data(("fios-vm-resource-profile-v1\0"+runtime.policySHA256+"\0"+policySHA256).utf8)).map {String(format:"%02x",$0)}.joined()
    }
    static func load(directory:URL)throws->VMResourceEnrolledPolicy? {
        guard let runtime=try RuntimeEnrolledPolicy.load(directory:directory) else {return nil}
        var entry=stat()
        if lstat(policyPath,&entry) != 0 {
            guard errno==ENOENT else {throw ControlError.unauthorized};return nil
        }
        let bytes=try RootPolicyFile.read(path:policyPath,maximum:4096)
        let document=try VMResourceEnrollmentDocument(bytes)
        guard document.runtimePolicySHA256==runtime.policySHA256 else {throw ControlError.unauthorized}
        let info=try RootPolicyFile.read(path:"/Applications/OrbStack.app/Contents/Info.plist",maximum:65536,expectedSHA256:document.orbstackInfoSHA256)
        try document.validateContext(runtimePolicySHA256:runtime.policySHA256,applicationInfo:info)
        let digest=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        return VMResourceEnrolledPolicy(runtime:runtime,document:document,policySHA256:digest)
    }
    func makeReader()throws->any VMResourceReading {
        let kernel=try OwnedVMResourceReader(runtime:runtime.runtime,approvedImages:document.metadataImages,directMetadata:true)
        return VMResourceProfileReader(kernel:kernel,cap:runtime.capacity,profileHash:profileSHA256,reviewDigest:document.reviewSHA256,
            physical:ProcessInfo.processInfo.physicalMemory)
    }
}
