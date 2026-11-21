import Foundation

enum ArtifactServiceValue:Sendable { case published(String),download(ArtifactDownload),expired }
enum ArtifactServiceFailure:Error,Sendable {case unauthorized,unavailable,capacity,invalid}
struct ArtifactServiceResult:Sendable {
    let request:String
    let result:Result<ArtifactServiceValue,ArtifactServiceFailure>
}

// Exclusive ownership of the store transfers to this service. Durable blob
// write/fsync/hash/read never runs on the manager heartbeat/control thread.
// Two total operation/result slots; no unbounded filesystem work queue.
final class AsyncArtifacts:@unchecked Sendable {
    private let store:ArtifactStore
    private let lock=NSLock()
    private let queue=DispatchQueue(label:"fios.studio.exports")
    private var pending=Set<String>()
    private var completed:[ArtifactServiceResult]=[]
    private var retained:(bytes:Int64,jobs:Int)
    // Full retained bytes stay charged after ready publication: a host disk
    // sample may predate that write. Only proven store cleanup refunds them.
    private var committedDisk:UInt64
    private var queuedDisk:[String:UInt64]=[:]
    init(store:ArtifactStore) {self.store=store;retained=(store.retainedBytes,store.retainedJobs);committedDisk=UInt64(store.retainedBytes)}
    func reservingDisk(in sample:ResourceSample)->ResourceSample {
        lock.lock();defer {lock.unlock()}
        var result=sample
        result.diskCommitted=max(sample.diskCommitted,committedDisk+queuedDisk.values.reduce(0,+))
        return result
    }
    var statistics:(bytes:Int64,jobs:Int) {lock.lock();defer {lock.unlock()};return retained}
    private func reserve(_ request:String,diskBytes:UInt64=0) throws {
        guard UUID(uuidString:request)?.uuidString.lowercased()==request else {throw ArtifactServiceFailure.invalid}
        lock.lock();defer {lock.unlock()}
        guard pending.count+completed.count<2,!pending.contains(request),!completed.contains(where:{$0.request==request}) else {throw ArtifactServiceFailure.capacity}
        pending.insert(request);queuedDisk[request]=diskBytes
    }
    private func finish(_ request:String,_ work:()throws->ArtifactServiceValue) {
        let result:Result<ArtifactServiceValue,ArtifactServiceFailure>
        do {result = .success(try work())}
        catch ArtifactError.unauthorized {result = .failure(.unauthorized)}
        catch ArtifactError.capacity {result = .failure(.capacity)}
        catch ArtifactError.invalid {result = .failure(.invalid)}
        catch {result = .failure(.unavailable)}
        lock.lock();retained=(store.retainedBytes,store.retainedJobs);committedDisk=UInt64(store.retainedBytes);queuedDisk.removeValue(forKey:request);pending.remove(request);completed.append(ArtifactServiceResult(request:request,result:result));lock.unlock()
    }
    func publish(request:String,job:String,owner:String,data:Data,now:Int64) throws {
        guard data.count<=16<<20 else {throw ArtifactServiceFailure.capacity}
        try reserve(request,diskBytes:UInt64(data.count))
        queue.async { [self] in
            finish(request) {.published(try store.publish(job:job,ownerHash:owner,data:data,now:now))}
        }
    }
    func download(request:String,id:String,owner:String,now:Int64) throws {
        try reserve(request)
        queue.async { [self] in
            finish(request) {.download(try store.download(id:id,ownerHash:owner,now:now))}
        }
    }
    func expire(request:String,now:Int64) throws {
        try reserve(request)
        queue.async { [self] in finish(request) {try store.expire(now:now);return .expired} }
    }
    func drain()->[ArtifactServiceResult] {
        lock.lock();defer {lock.unlock()}
        let result=completed;completed.removeAll();return result
    }
}
