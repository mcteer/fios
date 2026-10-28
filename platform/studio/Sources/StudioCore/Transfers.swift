import Foundation
import CryptoKit

enum TransferError: Error { case invalid, expired, hash }
enum TransferKind { case input, artifact }

// A failed stream is permanently consumed. Admission owns the surrounding job
// lease; successful framing alone grants no filesystem or model authority.
struct ChunkTransfer {
    private let length:Int
    private let sha256:String
    private let deadline:Int64
    private var previous:Int64
    private var next=0
    private var ended=false
    private var data=Data()

    init(length:Int,sha256:String,created:Int64,kind:TransferKind) throws {
        let limit=kind == .input ? 4<<20 : 16<<20
        let duration:Int64=kind == .input ? 10_000 : 30_000
        guard (0...limit).contains(length),created>=0,created<=ActivityPolicy.maximumTimestamp-duration,
              sha256.utf8.count==64,sha256.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}) else { throw TransferError.invalid }
        self.length=length;self.sha256=sha256;deadline=created+duration;previous=created
    }
    private mutating func check(now:Int64) throws {
        guard !ended else { throw TransferError.invalid }
        guard now>=previous,now<deadline else { ended=true;data.removeAll();throw TransferError.expired }
        previous=now
    }
    mutating func validate(now:Int64) throws { try check(now:now) }
    mutating func append(index:Int,base64:String,now:Int64) throws {
        try check(now:now)
        guard index==next,base64.utf8.count<=43_692,
              let bytes=Data(base64Encoded:base64),!bytes.isEmpty,bytes.count<=32_768,
              bytes.base64EncodedString()==base64,bytes.count<=length-data.count else {
            ended=true;data.removeAll();throw TransferError.invalid
        }
        data.append(bytes);next+=1
    }
    mutating func finish(now:Int64) throws -> Data {
        try check(now:now);ended=true
        defer { data.removeAll() }
        guard data.count==length else { throw TransferError.invalid }
        let digest=SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        guard digest==sha256 else { throw TransferError.hash }
        return data
    }
}

struct TransferBudget {
    private(set) var output=0
    // Charge the declaration BEFORE accepting a new export; failed transfers
    // never refund the job's finite output allowance.
    mutating func chargeOutput(_ bytes:Int) throws {
        guard bytes>=0,bytes<=(16<<20)-output else { throw TransferError.invalid }
        output+=bytes
    }
}
