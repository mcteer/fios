import Foundation
import Darwin
import CSQLite
import CryptoKit

// Corrupt only disposable stopped journals. Startup must reject before its
// restart UPDATE can hide an invalid flag or truncate an ownership identity.
func runJournalRowTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let id=UUID().uuidString.lowercased(),boot=UUID().uuidString.lowercased()
    let cases:[String]=[
        "UPDATE inference SET job='not-a-uuid'",
        "UPDATE inference SET model=''",
        "UPDATE inference SET model=replace(hex(zeroblob(513)),'0','a')",
        "PRAGMA ignore_check_constraints=ON; UPDATE inference SET uncertain=2",
        "INSERT INTO request_history VALUES('invalid',0,'exact',NULL)",
        "INSERT INTO request_history VALUES('\(id)',1,'exact','invalid')",
        "INSERT INTO worker_launches VALUES('\(id)',0,'invalid','\(boot)',1)",
        "INSERT INTO worker_launches VALUES('\(id)',0,'\(boot)','invalid',1)"
    ]
    var failures:[String]=[]
    for (index,sql) in cases.enumerated() {
        let directory=root.appendingPathComponent(String(index))
        do {let journal=try Journal(directory:directory);try journal.claim(job:id,attempt:0,model:"exact")}
        let file=directory.appendingPathComponent("state.sqlite")
        var db:OpaquePointer?
        guard sqlite3_open(file.path,&db)==SQLITE_OK else {throw JournalError.storage}
        let result=sqlite3_exec(db,sql,nil,nil,nil);sqlite3_close(db)
        guard result==SQLITE_OK else {throw JournalError.storage}
        let before=SHA256.hash(data:try Data(contentsOf:file))
        do {_ = try Journal(directory:directory);failures.append("Accepted malformed journal row \(index)")}
        catch JournalError.invalid {}
        catch {failures.append("Unexpected refusal \(index)")}
        if SHA256.hash(data:try Data(contentsOf:file)) != before {failures.append("Rewrote malformed journal \(index)")}
    }
    guard failures.isEmpty else {fatalError(failures.joined(separator:"; "))}
    // Model IDs are exact UTF-8 byte strings, so binding through C's implicit
    // NUL terminator must not silently alias two otherwise distinct IDs.
    let exact=root.appendingPathComponent("exact-model-bytes")
    do {
        let journal=try Journal(directory:exact)
        try journal.claim(job:id,attempt:0,model:"exact\0suffix")
        do {
            try journal.claim(job:UUID().uuidString.lowercased(),attempt:0,model:"exact")
            fatalError("NUL-truncated model identity admitted a conflicting model")
        } catch JournalError.conflict {}
    }
    let reopened=try Journal(directory:exact)
    guard try reopened.uncertainCount()==1 else {fatalError("Exact UTF-8 ownership lost on restart")}
    // Seatbelt strips set-ID bits from chmod in this child. Use an actually
    // observable executable mode; do not claim a synthetic set-ID witness.
    for mode:mode_t in [0o700] {
        let directory=root.appendingPathComponent("mode-\(mode)")
        do {_ = try Journal(directory:directory)}
        guard chmod(directory.appendingPathComponent("state.sqlite").path,mode)==0 else {throw JournalError.storage}
        do {_ = try Journal(directory:directory);fatalError("Non-0600 journal mode accepted")}
        catch JournalError.invalid {}
    }
    print("PASS: malformed inference/history and reaped launch identities refused before recovery writes")
}
