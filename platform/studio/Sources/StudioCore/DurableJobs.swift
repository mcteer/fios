import Foundation

struct DurableJob: Codable {
    let id: String
    let idempotency: String
    let ownerHash: String
    let requestHash: String
    var state: JobState = .reserved
    var closedAt: Int64?
    var lease: JobLease

    init(id:String,idempotency:String,ownerHash:String,requestHash:String,created:Int64,lifetime:Int64 = 900_000) throws {
        func uuid(_ value:String)->Bool { UUID(uuidString:value)?.uuidString.lowercased()==value }
        func digest(_ value:String)->Bool { value.utf8.count==64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        guard uuid(id),uuid(idempotency),digest(ownerHash),digest(requestHash) else { throw JournalError.invalid }
        self.id=id;self.idempotency=idempotency;self.ownerHash=ownerHash;self.requestHash=requestHash
        lease=try JobLease(created:created,lifetime:lifetime)
    }
}
