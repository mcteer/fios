import Foundation
import Darwin
import CryptoKit

func runArtifactLimitTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("fios-artifact-limits-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let owner=String(repeating:"a",count:64)
    func index(_ directory:URL,count:Int,bytes:Int) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let records=(0..<count).map {_ in ["id":UUID().uuidString.lowercased(),"job":UUID().uuidString.lowercased(),"ownerHash":owner,"created":1000,"bytes":bytes,"sha256":String(repeating:"0",count:64),"state":"failed"] as [String:Any]}
        try AtomicState.write(JSONSerialization.data(withJSONObject:["version":1,"records":records]),to:directory.appendingPathComponent("index.json"))
    }
    do {
        let directory=root.appendingPathComponent("aggregate")
        // Durable failed publications consume quota without allocating4GiB.
        try index(directory,count:255,bytes:16<<20)
        let store=try ArtifactStore(directory:directory,availableBytes:{20<<30})
        _ = try store.publish(job:UUID().uuidString.lowercased(),ownerHash:owner,data:Data(repeating:7,count:16<<20),now:1001)
        guard store.retainedBytes==4<<30,store.retainedJobs==256 else {fatalError("Aggregate retention boundary changed")}
        do {_ = try store.publish(job:UUID().uuidString.lowercased(),ownerHash:owner,data:Data([1]),now:1001);fatalError("Aggregate quota overshot")}catch ArtifactError.capacity{}
        try store.expire(now:1000+86_400_000)
        guard store.retainedJobs==1,store.retainedBytes==16<<20 else {fatalError("Expired failed reservations leaked or fresh result removed")}
        try store.expire(now:1001+86_400_000)
        guard store.retainedJobs==0,store.retainedBytes==0 else {fatalError("Retention cleanup left owned artifacts")}
    }
    do {
        let directory=root.appendingPathComponent("entry-count")
        try index(directory,count:256,bytes:0)
        let store=try ArtifactStore(directory:directory,availableBytes:{20<<30})
        do {_ = try store.publish(job:UUID().uuidString.lowercased(),ownerHash:owner,data:Data(),now:1001);fatalError("Retained entry cap ignored")}catch ArtifactError.capacity{}
    }
    do {
        let directory=root.appendingPathComponent("opaque")
        let store=try ArtifactStore(directory:directory,availableBytes:{20<<30})
        let bytes=Data("PK\u{03}\u{04}../../outside/credential-do-not-extract".utf8)
        let id=try store.publish(job:UUID().uuidString.lowercased(),ownerHash:owner,data:bytes,now:1001)
        guard try store.retrieve(id:id,ownerHash:owner,now:1002)==bytes else {fatalError("Opaque archive-like bytes changed")}
        guard !FileManager.default.fileExists(atPath:root.appendingPathComponent("outside").path) else {fatalError("Artifact bytes were extracted")}
        let blob=directory.appendingPathComponent(id+".blob"),alias=root.appendingPathComponent("alias")
        guard link(blob.path,alias.path)==0 else {fatalError("Hardlink fixture unavailable")}
        do {_ = try store.retrieve(id:id,ownerHash:owner,now:1003);fatalError("Hardlinked artifact accepted")}catch ArtifactError.invalid{}
        guard unlink(alias.path)==0 else {fatalError("Owned hardlink fixture cleanup failed")}
    }
    let input=Data(repeating:7,count:4<<20)
    let digest=SHA256.hash(data:input).map {String(format:"%02x",$0)}.joined()
    var transfer=try ChunkTransfer(length:input.count,sha256:digest,created:1000,kind:.input)
    for (index,start) in stride(from:0,to:input.count,by:32768).enumerated() {
        try transfer.append(index:index,base64:input[start..<min(input.count,start+32768)].base64EncodedString(),now:1001)
    }
    guard try transfer.finish(now:1002)==input else {fatalError("Exact4MiB input failed")}
    do {_ = try ChunkTransfer(length:(4<<20)+1,sha256:digest,created:1000,kind:.input);fatalError("Oversized input admitted")}catch TransferError.invalid{}
    print("PASS: exact4MiB input/16MiB export/4GiB durable quota/256 retention bounds,24h cleanup, opaque bytes and hardlink refusal")
}
