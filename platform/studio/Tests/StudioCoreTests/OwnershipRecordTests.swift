import Foundation
import Darwin
import CSQLite
import CryptoKit

func runOwnershipRecordTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)}
    let hash=String(repeating:"a",count:64)
    var failures:[String]=[]
    for name in ["job-field","lease-field","job-duplicate","job-nul-suffix","job-key","sandbox-field","configuration-field","sandbox-key","worker-field"] {
        let directory=root.appendingPathComponent(name),id=UUID().uuidString.lowercased()
        let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:hash,requestHash:hash,created:1000)
        do {
            let journal=try Journal(directory:directory)
            _=try journal.reserveJob(job)
            try journal.claim(job:id,attempt:0,model:"fixture/exact")
        }
        var table="jobs",payload=try JSONEncoder().encode(job)
        if name.hasPrefix("sandbox") || name=="configuration-field" {
            table="sandboxes"
            let configuration=try SandboxConfiguration(job:id,nonce:hash,image:"sha256:"+hash,memory:512<<20,cpus:1)
            payload=try JSONEncoder().encode(SandboxRecord(configuration:configuration))
        } else if name=="worker-field" {
            table="worker_grants"
            // Metadata only. Never bind, query or signal this synthetic PID.
            payload=try JSONEncoder().encode(WorkerGrant(pid:42,start:1,boot:UUID().uuidString.lowercased()))
        }
        var object=try JSONSerialization.jsonObject(with:payload) as! [String:Any]
        switch name {
        case "lease-field":
            var nested=object["lease"] as! [String:Any];nested["native_pending"]=true;object["lease"]=nested
        case "configuration-field":
            var nested=object["configuration"] as! [String:Any];nested["native_pending"]=true;object["configuration"]=nested
        case "job-key":object["idempotency"]=UUID().uuidString.lowercased()
        case "sandbox-key":
            var nested=object["configuration"] as! [String:Any];nested["job"]=UUID().uuidString.lowercased();object["configuration"]=nested
        case "job-duplicate","job-nul-suffix":break
        default:object["native_pending"]=true
        }
        var text=String(decoding:try JSONSerialization.data(withJSONObject:object),as:UTF8.self)
        if name=="job-duplicate" {text=String(text.dropLast())+",\"ownerHash\":\""+hash+"\"}"}
        if name=="job-nul-suffix" {text+="\0unreviewed ownership"}
        var db:OpaquePointer?
        guard sqlite3_open(directory.appendingPathComponent("state.sqlite").path,&db)==SQLITE_OK else {throw JournalError.storage}
        do {
            defer {sqlite3_close(db)}
            let sql=table=="jobs" ? "UPDATE jobs SET payload=? WHERE id=?" : table=="sandboxes" ? "INSERT INTO sandboxes(job,payload) VALUES(?,?)" : "INSERT INTO worker_grants(job,attempt,payload,reaped) VALUES(?,0,?,0)"
            var statement:OpaquePointer?
            guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK else {throw JournalError.storage}
            defer {sqlite3_finalize(statement)}
            let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
            let values=table=="jobs" ? [text,id]:[id,text]
            for (index,value) in values.enumerated() {guard sqlite3_bind_text(statement,Int32(index+1),value,Int32(value.utf8.count),transient)==SQLITE_OK else {throw JournalError.storage}}
            guard sqlite3_step(statement)==SQLITE_DONE else {throw JournalError.storage}
        }
        let file=directory.appendingPathComponent("state.sqlite"),before=SHA256.hash(data:try Data(contentsOf:directory.appendingPathComponent("state.sqlite")))
        do {_ = try Journal(directory:directory);failures.append("Unknown/mismatched ownership accepted: "+name)}
        catch JournalError.invalid {}
        catch {failures.append("Ownership failure was not a clean preflight refusal: "+name)}
        if SHA256.hash(data:try Data(contentsOf:file)) != before {failures.append("Rejected ownership was rewritten: "+name)}
    }
    guard failures.isEmpty else {fatalError(failures.joined(separator:"; "))}
    print("PASS: duplicate/unknown nested ownership fields and SQL/payload identity mismatch refused before recovery writes; synthetic worker metadata never acted on")
}
