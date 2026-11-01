import Foundation
import Darwin

// Fixed process-role inputs for read-only monitoring, not an installation,
// absence/start lease, native activity claim or lifecycle authority issuer.
// A future installed factory must obtain both hashes/review from protected
// reviewed policy; task/operator payloads cannot choose paths or commands.
struct MLXServingProcessProfile:Sendable {
    static let bundle="/Applications/MLX-Serve.app"
    let server:VerifiedExecutable
    let application:VerifiedExecutable
    private let reviewDigest:String
    private let uid:uid_t
    init(serverSHA256:String,applicationSHA256:String,reviewDigest:String,uid:uid_t)throws {
        guard uid>0,uid==geteuid(),getuid()==geteuid(),WireScalar.sha256(reviewDigest) else {throw ServiceError.invalid}
        server=try VerifiedExecutable(path:Self.bundle+"/Contents/MacOS/mlx-serve",sha256:serverSHA256)
        application=try VerifiedExecutable(path:Self.bundle+"/Contents/MacOS/MLXCore",sha256:applicationSHA256)
        self.reviewDigest=reviewDigest;self.uid=uid
    }
    func makeCensus()throws->ServiceProcessCensus {
        try ServiceProcessCensus(executable:server,relatedRoots:[Self.bundle],reviewDigest:reviewDigest,uid:uid,companion:application)
    }
}
