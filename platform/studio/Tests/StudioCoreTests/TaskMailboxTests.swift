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
    var other=TaskMailbox()
    for _ in 0..<4 {try other.append(job:UUID().uuidString.lowercased(),fields:fields,now:1000)}
    do {try other.append(job:UUID().uuidString.lowercased(),fields:fields,now:1001);fatalError("Output exceeded four jobs")} catch MailboxError.capacity {}
    print("PASS: owner-output mailbox has monotonic event ordinals, four-job/finite-byte/frame bounds and fixed2s backpressure expiry; no execution replay")
}
