import Foundation
import CryptoKit

func runTransferTests() throws {
    let data=Data("bounded payload".utf8)
    let hash=SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    var stream=try ChunkTransfer(length:data.count,sha256:hash,created:1000,kind:.input)
    try stream.append(index:0,base64:data.base64EncodedString(),now:1001)
    guard try stream.finish(now:1002)==data else { fatalError("Transfer corrupted") }
    do { _=try stream.finish(now:1003);fatalError("Completion replay accepted") } catch TransferError.invalid {}
    var gap=try ChunkTransfer(length:data.count,sha256:hash,created:1000,kind:.input)
    do { try gap.append(index:1,base64:data.base64EncodedString(),now:1001);fatalError("Gap accepted") } catch TransferError.invalid {}
    do { try gap.append(index:0,base64:data.base64EncodedString(),now:1002);fatalError("Failed stream resurrected") } catch TransferError.invalid {}
    var expired=try ChunkTransfer(length:data.count,sha256:hash,created:1000,kind:.artifact)
    do { try expired.append(index:0,base64:data.base64EncodedString(),now:31000);fatalError("Expired stream accepted") } catch TransferError.expired {}
    var wrong=try ChunkTransfer(length:data.count,sha256:String(repeating:"0",count:64),created:1000,kind:.artifact)
    try wrong.append(index:0,base64:data.base64EncodedString(),now:1001)
    do { _=try wrong.finish(now:1002);fatalError("Hash mismatch accepted") } catch TransferError.hash {}
    var budget=TransferBudget()
    try budget.chargeOutput(16<<20)
    do { try budget.chargeOutput(1);fatalError("Output reservation exceeded") } catch TransferError.invalid {}
    let chunk=Data(repeating:97,count:32768)
    let chunkHash=SHA256.hash(data:chunk).map {String(format:"%02x",$0)}.joined()
    var exact=try ChunkTransfer(length:chunk.count,sha256:chunkHash,created:1000,kind:.input)
    try exact.append(index:0,base64:chunk.base64EncodedString(),now:1001)
    guard try exact.finish(now:1002)==chunk else {fatalError("Exact32KiB chunk refused")}
    for encoded in [Data(repeating:97,count:32769).base64EncodedString(),"","*","YR=="] {
        var malformed=try ChunkTransfer(length:chunk.count,sha256:chunkHash,created:1000,kind:.input)
        do {try malformed.append(index:0,base64:encoded,now:1001);fatalError("Oversized/invalid/noncanonical chunk accepted")}catch TransferError.invalid{}
        do {try malformed.validate(now:1002);fatalError("Invalid chunk stream resurrected")}catch TransferError.invalid{}
    }
    var duplicate=try ChunkTransfer(length:2*data.count,sha256:hash,created:1000,kind:.input)
    try duplicate.append(index:0,base64:data.base64EncodedString(),now:1001)
    do {try duplicate.append(index:0,base64:data.base64EncodedString(),now:1002);fatalError("Duplicate chunk accepted")}catch TransferError.invalid{}
    var rollback=try ChunkTransfer(length:data.count,sha256:hash,created:1000,kind:.input)
    try rollback.append(index:0,base64:data.base64EncodedString(),now:1002)
    do {_=try rollback.finish(now:1001);fatalError("Transfer clock rollback accepted")}catch TransferError.expired{}
    do {_=try rollback.finish(now:1003);fatalError("Rollback stream resurrected")}catch TransferError.invalid{}
    for (kind,duration) in [(TransferKind.input,Int64(10000)),(.artifact,Int64(30000))] {
        var boundary=try ChunkTransfer(length:data.count,sha256:hash,created:1000,kind:kind)
        try boundary.append(index:0,base64:data.base64EncodedString(),now:1000+duration-1)
        guard try boundary.finish(now:1000+duration-1)==data else {fatalError("Last valid transfer millisecond refused")}
        var timedOut=try ChunkTransfer(length:data.count,sha256:hash,created:1000,kind:kind)
        do {try timedOut.append(index:0,base64:data.base64EncodedString(),now:1000+duration);fatalError("Exact transfer deadline accepted")}catch TransferError.expired{}
    }
    print("PASS: exact32KiB/canonical chunks, gap/duplicate/replay/hash/timeout/rollback refusal, irreversible failure and cumulative output limit")
}
