import Foundation

enum MailboxError:Error {case capacity,invalid}

// Ephemeral at-most-once owner output, not a workload journal. Consumer reads
// cannot authorize operations or reset job/native/transfer leases. Undrained
// output has a fixed2s backpressure deadline; manager restart loses it rather
// than replaying execution to regenerate results.
struct TaskMailbox {
    private struct Message {let bytes:Data;let created:Int64}
    private struct Queue {var messages:[Message]=[];var bytes=0}
    private var queues:[String:Queue]=[:]
    private var counters:[String:Int]=[:]
    mutating func append(job:String,fields:[String:Any],now:Int64) throws {
        guard UUID(uuidString:job)?.uuidString.lowercased()==job,(0...ActivityPolicy.maximumTimestamp-2000).contains(now) else {throw MailboxError.invalid}
        var queue=queues[job] ?? Queue()
        guard queues[job] != nil || queues.count<4 else {throw MailboxError.capacity}
        guard counters[job] != nil || counters.count<260 else {throw MailboxError.capacity}
        let index=counters[job] ?? 0
        let bytes=try JSONSerialization.data(withJSONObject:fields.merging(["event_index":index]) {_,new in new})
        guard !bytes.isEmpty,bytes.count<=60000,queue.messages.count<64,queue.bytes+bytes.count<=1<<20 else {throw MailboxError.capacity}
        if let first=queue.messages.first,now<first.created || now-first.created>=2000 {throw MailboxError.capacity}
        queue.messages.append(Message(bytes:bytes,created:now));queue.bytes+=bytes.count;counters[job]=index+1;queues[job]=queue
    }
    mutating func pop(job:String,now:Int64) throws -> [String:Any]? {
        guard var queue=queues[job],let first=queue.messages.first else {return nil}
        guard now>=first.created,now-first.created<2000 else {queues.removeValue(forKey:job);throw MailboxError.capacity}
        queue.messages.removeFirst();queue.bytes-=first.bytes.count;queues[job]=queue
        return try JSONSerialization.jsonObject(with:first.bytes) as? [String:Any]
    }
    mutating func expire(now:Int64,retained:Set<String>)->[String] {
        var expired:[String]=[]
        counters=counters.filter {retained.contains($0.key)}
        for id in Array(queues.keys) {
            guard let queue=queues[id] else {continue}
            if !retained.contains(id) {queues.removeValue(forKey:id);continue}
            if let first=queue.messages.first,now<first.created || now-first.created>=2000 {expired.append(id);queues.removeValue(forKey:id)}
            else if queue.messages.isEmpty {queues.removeValue(forKey:id)}
        }
        return expired
    }
    mutating func discard(job:String) {queues.removeValue(forKey:job)}
}
