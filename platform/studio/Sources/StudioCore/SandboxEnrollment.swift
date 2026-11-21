import Foundation
import Darwin
import CryptoKit

// Review metadata only. Decoding does not approve an image or construct an
// executor; the installed-role/root-policy boundary below remains independent.
struct SandboxEnrollmentDocument {
    let runtimePolicySHA256:String
    let reviewSHA256:String
    let images:Set<String>
    init(_ bytes:Data)throws {
        do {
            try StrictJSON.validate(bytes,maximum:4096)
            guard let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  Set(value.keys)==Set(["version","purpose","runtime_policy_sha256","review_sha256","images"]),
                  WireScalar.integer(value["version"],maximum:1)==1,
                  value["purpose"] as? String=="reviewed_platform_sandbox_images",
                  let runtime=value["runtime_policy_sha256"] as? String,WireScalar.sha256(runtime),
                  let review=value["review_sha256"] as? String,WireScalar.sha256(review),
                  let images=value["images"] as? [String],(1...8).contains(images.count),Set(images).count==images.count,
                  images.allSatisfy({$0.hasPrefix("sha256:") && $0.utf8.count==71 && WireScalar.sha256(String($0.dropFirst(7)))}) else {throw ControlError.unauthorized}
            runtimePolicySHA256=runtime;reviewSHA256=review;self.images=Set(images)
        }catch {throw ControlError.unauthorized}
    }
    func matches(runtimePolicySHA256:String)->Bool {self.runtimePolicySHA256==runtimePolicySHA256}
}

// Code-only installed configuration. No public startup wiring, policy writer,
// image pull/import, runtime action or native admission issuer is provided.
struct SandboxEnrolledPolicy {
    static let policyPath="/Library/Application Support/Fios/Studio/sandbox-enrollment.json"
    private let directory:URL
    private let document:SandboxEnrollmentDocument
    private let policySHA256:String
    private init(directory:URL,document:SandboxEnrollmentDocument,policySHA256:String) {
        self.directory=directory;self.document=document;self.policySHA256=policySHA256
    }
    static func load(directory:URL)throws->SandboxEnrolledPolicy? {
        // The existing opaque runtime loader verifies the actual fixed manager,
        // host/account/state and protected CLI/daemon/application inputs first.
        guard let runtime=try RuntimeEnrolledPolicy.load(directory:directory) else {return nil}
        var entry=stat()
        if lstat(policyPath,&entry) != 0 {guard errno==ENOENT else {throw ControlError.unauthorized};return nil}
        let bytes=try RootPolicyFile.read(path:policyPath,maximum:4096)
        let document=try SandboxEnrollmentDocument(bytes)
        guard document.matches(runtimePolicySHA256:runtime.policySHA256) else {throw ControlError.unauthorized}
        return SandboxEnrolledPolicy(directory:directory,document:document,
            policySHA256:SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined())
    }
    // Run off the serialized loop. Constructors below perform no subprocess or
    // daemon request; later operations retain their existing bounds and checks.
    func makeExecutor()throws->SandboxExecutor {
        _=try RootPolicyFile.read(path:Self.policyPath,maximum:4096,expectedSHA256:policySHA256)
        guard let runtime=try RuntimeEnrolledPolicy.load(directory:directory),
              document.matches(runtimePolicySHA256:runtime.policySHA256),
              let resources=try VMResourceEnrolledPolicy.load(directory:directory),
              resources.supports(runtimePolicySHA256:runtime.policySHA256,images:document.images) else {throw ControlError.unauthorized}
        return try SandboxExecutor(runtime:runtime.runtime,allowedImages:document.images,resourceReader:resources.makeReader())
    }
}
