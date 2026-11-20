import Foundation

func runTaskMailboxTests() throws {
    var mailbox=TaskMailbox()
    let job=UUID().uuidString.lowercased()
    let fields:[String:Any]=["type":"output","stream":"stdout","data":Data("{\"type\":\"service.force\"}".utf8).base64EncodedString()]
    try mailbox.append(job:job,fields:fields,now:1000)
    guard try mailbox.pop(job:job,now:1001)?["event_index"] as? Int==0 else {fatalError("Mailbox lost first event")}
    _=mailbox.expire(now:1002,retained:[job])
    try mailbox.append(job:job,fields:fields,now:1003)
    guard try mailbox.pop(job:job,now:1004)?["event_index"] as? Int==1 else {fatalError("Draining mailbox reset event ordinal")}
    for _ in 0..<64 {try mailbox.append(job:job,fields:fields,now:1005)}
    do {try mailbox.append(job:job,fields:fields,now:1006);fatalError("Unbounded output queue")} catch MailboxError.capacity {}
    guard mailbox.expire(now:3005,retained:[job])==[job] else {fatalError("Output activity extended fixed backpressure deadline")}
    var partial=TaskMailbox()
    try partial.append(job:job,fields:fields,now:1000)
    try partial.append(job:job,fields:fields,now:1100)
    guard try partial.pop(job:job,now:2999)?["event_index"] as? Int==0,
          partial.expire(now:3099,retained:[job]).isEmpty,
          partial.expire(now:3100,retained:[job])==[job] else {
        fatalError("Polling renewed the remaining mailbox frame's deadline")
    }
    var rewound=TaskMailbox()
    try rewound.append(job:job,fields:fields,now:1000)
    try rewound.append(job:job,fields:fields,now:1100)
    do {try rewound.append(job:job,fields:fields,now:1099);fatalError("Mailbox appended after its queued clock rewound")}catch MailboxError.capacity {}
    do {_=try rewound.pop(job:job,now:1099);fatalError("Mailbox emitted output across a queued clock rollback")}catch MailboxError.capacity {}
    var isolated=TaskMailbox()
    let another=UUID().uuidString.lowercased()
    try isolated.append(job:job,fields:fields,now:1000)
    try isolated.append(job:another,fields:fields,now:2000)
    guard isolated.expire(now:3000,retained:[job,another])==[job],
          try isolated.pop(job:job,now:3000)==nil,
          try isolated.pop(job:another,now:3000)?["event_index"] as? Int==0 else {
        fatalError("Mailbox expiry changed another job's valid output")
    }
    try isolated.append(job:job,fields:fields,now:3001)
    try isolated.append(job:another,fields:fields,now:3001)
    isolated.discard(job:job)
    try isolated.append(job:job,fields:fields,now:3002)
    guard try isolated.pop(job:job,now:3002)?["event_index"] as? Int==2,
          try isolated.pop(job:job,now:3002)==nil,
          try isolated.pop(job:another,now:3002)?["event_index"] as? Int==1 else {
        fatalError("Discard replayed owner output, reset ordinals, or disturbed another job")
    }
    var byteBound=TaskMailbox()
    let large:[String:Any]=["type":"output","data":String(repeating:"a",count:59000)]
    for _ in 0..<17 {try byteBound.append(job:job,fields:large,now:1000)}
    do {try byteBound.append(job:job,fields:large,now:1000);fatalError("Mailbox bypassed aggregate byte bound")}
    catch MailboxError.capacity {}
    guard try byteBound.pop(job:job,now:1001)?["event_index"] as? Int==0 else {fatalError("Byte refusal displaced existing output")}
    try byteBound.append(job:job,fields:large,now:1001)
    for index in 1...17 {
        guard try byteBound.pop(job:job,now:1002)?["event_index"] as? Int==index else {
            fatalError("Mailbox byte refusal consumed an event ordinal")
        }
    }
    var frameBound=TaskMailbox()
    let overhead=try JSONSerialization.data(withJSONObject:["type":"output","data":"","event_index":0]).count
    let exactSize=60000-overhead
    do {
        try frameBound.append(job:job,fields:["type":"output","data":String(repeating:"a",count:exactSize+1)],now:1000)
        fatalError("Mailbox accepted an oversized serialized frame")
    } catch MailboxError.capacity {}
    let exactData=String(repeating:"a",count:exactSize)
    try frameBound.append(job:job,fields:["type":"output","data":exactData],now:1000)
    let exactFrame=try frameBound.pop(job:job,now:1001)
    guard exactFrame?["event_index"] as? Int==0,exactFrame?["data"] as? String==exactData else {
        fatalError("Mailbox frame limit altered valid data or consumed its ordinal")
    }
    var other=TaskMailbox()
    for _ in 0..<4 {try other.append(job:UUID().uuidString.lowercased(),fields:fields,now:1000)}
    do {try other.append(job:UUID().uuidString.lowercased(),fields:fields,now:1001);fatalError("Output exceeded four jobs")} catch MailboxError.capacity {}
    print("PASS: owner-output mailbox has monotonic event ordinals, four-job/finite-byte/frame bounds and fixed2s backpressure expiry; no execution replay")
}
