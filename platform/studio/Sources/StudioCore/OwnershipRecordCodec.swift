import Foundation

// Persistent ownership is a versioned protocol too. Codable alone silently
// ignores future fields and duplicate keys; recovery must not rewrite them.
enum OwnershipRecordCodec {
    private static func object(_ data:Data,maximum:Int,allowed:Set<String>,required:Set<String>)throws->[String:Any] {
        do {
            try StrictJSON.validate(data,maximum:maximum)
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  Set(object.keys).isSubset(of:allowed),required.isSubset(of:Set(object.keys)) else {throw JournalError.invalid}
            return object
        } catch {throw JournalError.invalid}
    }
    static func job(_ data:Data)throws->DurableJob {
        do {
            let root=try object(data,maximum:4096,allowed:["id","idempotency","ownerHash","requestHash","state","closedAt","lease"],required:["id","idempotency","ownerHash","requestHash","state","lease"])
            guard let lease=root["lease"] as? [String:Any],Set(lease.keys)==Set(["created","deadline","expires","revoked","previous"]) else {throw JournalError.invalid}
            let record=try JSONDecoder().decode(DurableJob.self,from:data)
            _=try DurableJob(id:record.id,idempotency:record.idempotency,ownerHash:record.ownerHash,requestHash:record.requestHash,created:record.lease.created,lifetime:1)
            try record.lease.validateRestored()
            if let closed=record.closedAt {guard closed>=0,closed<=ActivityPolicy.maximumTimestamp else {throw JournalError.invalid}}
            return record
        } catch {throw JournalError.invalid}
    }
    static func sandbox(_ data:Data)throws->SandboxRecord {
        do {
            let root=try object(data,maximum:4096,allowed:["configuration","runtimeID","createIssued","startIssued","removalProven"],required:["configuration","createIssued","startIssued","removalProven"])
            guard let configuration=root["configuration"] as? [String:Any],Set(configuration.keys)==Set(["job","nonce","image","memory","cpus"]) else {throw JournalError.invalid}
            let record=try JSONDecoder().decode(SandboxRecord.self,from:data),c=record.configuration
            _=try SandboxConfiguration(job:c.job,nonce:c.nonce,image:c.image,memory:c.memory,cpus:c.cpus)
            if let id=record.runtimeID {guard id.utf8.count==64,id.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else {throw JournalError.invalid}}
            return record
        } catch {throw JournalError.invalid}
    }
    static func worker(_ data:Data)throws->WorkerGrant {
        do {
            _=try object(data,maximum:512,allowed:["pid","start","boot"],required:["pid","start","boot"])
            let record=try JSONDecoder().decode(WorkerGrant.self,from:data)
            try record.validate();return record
        } catch {throw JournalError.invalid}
    }
}
