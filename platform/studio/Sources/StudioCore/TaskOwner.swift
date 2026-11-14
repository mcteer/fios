import Foundation
import CryptoKit
import Darwin

// Client-generated256-bit secret lives outside the sandbox. Only its scoped
// digest is durable; no role is read from a request and no token enters code,
// artifacts, worker argv/environment or routine logs.
struct TaskOwner {
    let hash:String
    static func newToken()->String {
        SymmetricKey(size:.bits256).withUnsafeBytes {Data($0).base64EncodedString()}
    }
    init(token:String,peerUID:uid_t) throws {
        guard token.utf8.count==44,let bytes=Data(base64Encoded:token),bytes.count==32,bytes.base64EncodedString()==token else {throw ControlError.unauthorized}
        let prefix=Data(("fios009-owner-v1:"+String(peerUID)+":").utf8)
        hash=SHA256.hash(data:prefix+bytes).map {String(format:"%02x",$0)}.joined()
    }
}
