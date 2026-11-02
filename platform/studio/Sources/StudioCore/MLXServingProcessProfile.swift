import Foundation
import Darwin

// Fixed process-role inputs for read-only monitoring, not an installation,
// absence/start lease, native activity claim or lifecycle authority issuer.
// A future installed factory must obtain both hashes/review from protected
// reviewed policy; task/operator payloads cannot choose paths or commands.
struct MLXServingProcessProfile:Sendable {
    enum ServerArtifact:Sendable {case vendorBundle,reviewedFiosNative}
    static let bundle="/Applications/MLX-Serve.app"
    static let managedNativeRoot="/Library/Application Support/Fios/Studio/native"
    let artifact:ServerArtifact
    var relatedRoots:Set<String> {
        switch artifact {
        case .vendorBundle:return [Self.bundle]
        case .reviewedFiosNative:return [Self.bundle,Self.managedNativeRoot]
        }
    }
    let server:VerifiedExecutable
    let application:VerifiedExecutable
    private let reviewDigest:String
    private let uid:uid_t
    init(serverSHA256:String,applicationSHA256:String,reviewDigest:String,uid:uid_t,artifact:ServerArtifact = .vendorBundle)throws {
        guard uid>0,uid==geteuid(),getuid()==geteuid(),WireScalar.sha256(reviewDigest) else {throw ServiceError.invalid}
        self.artifact=artifact
        let serverPath:String
        switch artifact {
        case .vendorBundle:serverPath=Self.bundle+"/Contents/MacOS/mlx-serve"
        case .reviewedFiosNative:serverPath=Self.managedNativeRoot+"/bin/mlx-serve"
        }
        server=try VerifiedExecutable(path:serverPath,sha256:serverSHA256)
        application=try VerifiedExecutable(path:Self.bundle+"/Contents/MacOS/MLXCore",sha256:applicationSHA256)
        self.reviewDigest=reviewDigest;self.uid=uid
    }
    func makeCensus()throws->ServiceProcessCensus {
        try ServiceProcessCensus(executable:server,relatedRoots:relatedRoots,reviewDigest:reviewDigest,uid:uid,companion:application)
    }
}
