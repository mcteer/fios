import Foundation
import Darwin

struct WorkerGrant:Codable,Equatable {
    let pid:Int32
    let start:UInt64
    let boot:String
    static func capture(pid:Int32) throws -> WorkerGrant {
        WorkerGrant(pid:pid,start:try WorkerResources.startIdentifier(pid:pid),boot:try HostBoot.identity())
    }
    func validate() throws {
        guard pid>1,start>0,UUID(uuidString:boot)?.uuidString.lowercased()==boot else { throw JournalError.invalid }
    }
    // Proof of this local worker's absence is NOT native-inference completion.
    func provenGone() throws -> Bool {
        try validate()
        if try HostBoot.identity() != boot { return true }
        if let current=try? WorkerResources.startIdentifier(pid:pid) { return current != start }
        return kill(pid,0)<0 && errno==ESRCH
    }
}

// Trusted coordinator identity, never decoded from task/control frames.
struct WorkerLaunchKey:Hashable {
    let job:String
    let attempt:Int
    var reservationKey:String {"model:\(job):\(attempt)"}
}
