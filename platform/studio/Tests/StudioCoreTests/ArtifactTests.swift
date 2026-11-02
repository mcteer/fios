import Foundation
import Darwin

func runArtifactTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let job=UUID().uuidString.lowercased(), owner=String(repeating:"a",count:64)
    var disk:UInt64?=20<<30
    var store:ArtifactStore?=try ArtifactStore(directory:directory,availableBytes:{disk})
    let id=try store!.publish(job:job,ownerHash:owner,data:Data("private result".utf8),now:1000)
    guard try store!.retrieve(id:id,ownerHash:owner,now:1001)==Data("private result".utf8) else { fatalError("Artifact mismatch") }
    do { _=try store!.retrieve(id:id,ownerHash:String(repeating:"b",count:64),now:1001);fatalError("Foreign owner read artifact") } catch ArtifactError.unauthorized {}
    do { _=try store!.retrieve(id:"../../outside",ownerHash:owner,now:1001);fatalError("Traversal accepted") } catch ArtifactError.invalid {}
    var download=try store!.download(id:id,ownerHash:owner,now:1001)
    guard case .begin(let exported,let bytes,_)=try download.next(now:1001),exported==id,bytes==14,
          case .chunk(let chunkIndex,let encoded)=try download.next(now:1002),chunkIndex==0,Data(base64Encoded:encoded)==Data("private result".utf8),
          case .end=try download.next(now:1003) else { fatalError("Owner-bound artifact framing failed") }
    do { _=try download.next(now:1003);fatalError("Completed download replayed") } catch ArtifactError.unavailable {}
    var expired=try store!.download(id:id,ownerHash:owner,now:1001)
    do { _=try expired.next(now:31001);fatalError("Expired download continued") } catch ArtifactError.unavailable {}
    do { _=try expired.next(now:1002);fatalError("Expired stream revived on clock rollback") } catch ArtifactError.unavailable {}
    let blob=directory.appendingPathComponent(id+".blob")
    let writer=try FileHandle(forWritingTo:blob)
    try writer.write(contentsOf:Data("PRIVATE result".utf8));try writer.close()
    do { _=try store!.retrieve(id:id,ownerHash:owner,now:1001);fatalError("Modified artifact accepted") } catch ArtifactError.invalid {}
    let restore=try FileHandle(forWritingTo:blob)
    try restore.write(contentsOf:Data("private result".utf8));try restore.close()
    disk=nil
    do { _=try store!.publish(job:UUID().uuidString.lowercased(),ownerHash:owner,data:Data([1]),now:1001);fatalError("Unknown disk headroom admitted export") } catch ArtifactError.capacity {}
    disk=20<<30
    store=nil
    // Crash after durable reservation/blob fsync but before ready publication.
    let indexURL=directory.appendingPathComponent("index.json")
    var index=try JSONSerialization.jsonObject(with:Data(contentsOf:indexURL)) as! [String:Any]
    var metadata=index["records"] as! [[String:Any]]
    metadata[0]["state"]="pending";index["records"]=metadata
    try AtomicState.write(JSONSerialization.data(withJSONObject:index),to:indexURL)
    store=try ArtifactStore(directory:directory)
    guard try store!.retrieve(id:id,ownerHash:owner,now:1002)==Data("private result".utf8) else { fatalError("Restart lost artifact") }
    do { _=try store!.publish(job:job,ownerHash:owner,data:Data(repeating:0,count:16<<20),now:1003);fatalError("Per-job export cap exceeded") } catch ArtifactError.capacity {}
    try store!.expire(now:1000+86_400_000)
    do { _=try store!.retrieve(id:id,ownerHash:owner,now:1000+86_400_000);fatalError("Expired artifact readable") } catch ArtifactError.unavailable {}
    // A forged storage object cannot redirect writes or retrieval into a host file.
    let foreign=directory.appendingPathComponent("forged")
    try FileManager.default.createSymbolicLink(atPath:foreign.path,withDestinationPath:"/etc/hosts")
    store=nil
    do { _=try ArtifactStore(directory:directory);fatalError("Unexpected storage symlink accepted") } catch ArtifactError.invalid {}
    print("PASS: private generated artifacts, owner/hash/length checks, restart, finite quotas, expiry and traversal/symlink refusal")
}
