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
    let second=try store!.publish(job:UUID().uuidString.lowercased(),ownerHash:owner,data:Data("second export".utf8),now:1004)
    let survivor=try store!.publish(job:UUID().uuidString.lowercased(),ownerHash:owner,data:Data("retained export".utf8),now:1005)
    let retention=1000+Int64(86_400_000)
    var nearRetention=try store!.download(id:id,ownerHash:owner,now:retention-2)
    guard case .begin=try nearRetention.next(now:retention-1) else {fatalError("Valid final retention tick lost artifact begin")}
    do { _=try nearRetention.next(now:retention);fatalError("New stream extended the original artifact retention") } catch ArtifactError.unavailable {}
    do { _=try nearRetention.next(now:retention-1);fatalError("Artifact stream revived after retention expiry") } catch ArtifactError.unavailable {}
    try store!.expire(now:retention)
    do { _=try store!.retrieve(id:id,ownerHash:owner,now:1000+86_400_000);fatalError("Expired artifact readable") } catch ArtifactError.unavailable {}
    store=nil
    store=try ArtifactStore(directory:directory)
    do {_=try store!.download(id:id,ownerHash:owner,now:retention);fatalError("Pruned export returned after reopen")}
    catch ArtifactError.unavailable {}
    guard try store!.retrieve(id:second,ownerHash:owner,now:retention+3)==Data("second export".utf8) else {
        fatalError("Another export's original retention was shortened")
    }
    do {_=try store!.download(id:second,ownerHash:owner,now:retention+4);fatalError("Reopen extended independent artifact retention")}
    catch ArtifactError.unavailable {}
    // Reopen after the durable deletion marker but before the owned unlink.
    store=nil
    index=try JSONSerialization.jsonObject(with:Data(contentsOf:indexURL)) as! [String:Any]
    metadata=index["records"] as! [[String:Any]]
    guard let deletion=metadata.firstIndex(where:{$0["id"] as? String==second}) else {throw ArtifactError.invalid}
    metadata[deletion]["state"]="deleting";index["records"]=metadata
    try AtomicState.write(JSONSerialization.data(withJSONObject:index),to:indexURL)
    store=try ArtifactStore(directory:directory)
    guard !FileManager.default.fileExists(atPath:directory.appendingPathComponent(second+".blob").path),
          try store!.retrieve(id:survivor,ownerHash:owner,now:retention+4)==Data("retained export".utf8) else {
        fatalError("Deletion recovery left marked blob or changed independent export")
    }
    // Model interruption after unlink but before clearing the durable marker.
    store=nil
    try AtomicState.write(JSONSerialization.data(withJSONObject:index),to:indexURL)
    store=try ArtifactStore(directory:directory)
    let cleaned=try JSONSerialization.jsonObject(with:Data(contentsOf:indexURL)) as! [String:Any]
    let remaining=cleaned["records"] as! [[String:Any]]
    guard remaining.count==1,remaining.first?["id"] as? String==survivor,
          try store!.retrieve(id:survivor,ownerHash:owner,now:retention+4)==Data("retained export".utf8) else {
        fatalError("Already-unlinked deletion replay changed independent artifact state")
    }
    let incompleteJob=UUID().uuidString.lowercased()
    let incomplete=try store!.publish(job:incompleteJob,ownerHash:owner,data:Data("incomplete export".utf8),now:retention+4)
    store=nil
    let incompleteBlob=directory.appendingPathComponent(incomplete+".blob")
    let incompleteWriter=try FileHandle(forWritingTo:incompleteBlob)
    try incompleteWriter.truncate(atOffset:1);try incompleteWriter.close()
    index=try JSONSerialization.jsonObject(with:Data(contentsOf:indexURL)) as! [String:Any]
    metadata=index["records"] as! [[String:Any]]
    guard let incompleteRow=metadata.firstIndex(where:{$0["id"] as? String==incomplete}) else {throw ArtifactError.invalid}
    metadata[incompleteRow]["state"]="pending";index["records"]=metadata
    try AtomicState.write(JSONSerialization.data(withJSONObject:index),to:indexURL)
    store=try ArtifactStore(directory:directory,availableBytes:{disk})
    do {_=try store!.download(id:incomplete,ownerHash:owner,now:retention+4);fatalError("Interrupted artifact became readable")}
    catch ArtifactError.unavailable {}
    let afterRecovery=try JSONSerialization.jsonObject(with:Data(contentsOf:indexURL)) as! [String:Any]
    let failedRows=afterRecovery["records"] as! [[String:Any]]
    guard failedRows.first(where:{$0["id"] as? String==incomplete})?["state"] as? String=="failed",
          try Data(contentsOf:incompleteBlob)==Data("i".utf8),
          try store!.retrieve(id:survivor,ownerHash:owner,now:retention+4)==Data("retained export".utf8) else {
        fatalError("Incomplete publication recovery removed diagnostic bytes or changed independent export")
    }
    disk=(UInt64(10)<<30)+1
    do {_=try store!.publish(job:incompleteJob,ownerHash:owner,data:Data([1]),now:retention+4);fatalError("Failed publication refunded original disk commitment")}
    catch ArtifactError.capacity {}
    guard try Data(contentsOf:incompleteBlob)==Data("i".utf8) else {fatalError("Capacity refusal changed failed export")}
    let survivorBlob=directory.appendingPathComponent(survivor+".blob")
    let parked=directory.appendingPathComponent(UUID().uuidString.lowercased())
    try FileManager.default.moveItem(at:survivorBlob,to:parked)
    do {
        defer {try? FileManager.default.removeItem(at:survivorBlob);try? FileManager.default.moveItem(at:parked,to:survivorBlob)}
        guard mkfifo(survivorBlob.path,0o600)==0 else {throw ArtifactError.storage}
        do {_=try store!.download(id:survivor,ownerHash:owner,now:retention+4);fatalError("Nonregular artifact was readable")}
        catch ArtifactError.invalid {}
    }
    guard try store!.retrieve(id:survivor,ownerHash:owner,now:retention+4)==Data("retained export".utf8) else {
        fatalError("Nonregular read refusal changed owner export")
    }
    // A forged storage object cannot redirect writes or retrieval into a host file.
    let foreign=directory.appendingPathComponent("forged")
    try FileManager.default.createSymbolicLink(atPath:foreign.path,withDestinationPath:"/etc/hosts")
    store=nil
    do { _=try ArtifactStore(directory:directory);fatalError("Unexpected storage symlink accepted") } catch ArtifactError.invalid {}
    print("PASS: private generated artifacts, owner/hash/length checks, restart, finite quotas, expiry and traversal/symlink refusal")
}
