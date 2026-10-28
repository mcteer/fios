import Foundation
import CSQLite

private func precondition(_ condition: Bool) { Swift.precondition(condition) }

private func expectJournalError<T>(_ body: () throws -> T) {
    do { _ = try body() } catch { return }
    preconditionFailure("Journal operation must reject")
}

func runJournalTests() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    let first = UUID().uuidString.lowercased()
    let second = UUID().uuidString.lowercased()
    do {
        let journal = try Journal(directory: path)
        expectJournalError { try Journal(directory: path) }
        try journal.claim(job: first, attempt: 0, model: "exact-a")
        try journal.markUncertain(job: first, attempt: 0)
        expectJournalError { try journal.claim(job: first, attempt: 1, model: "exact-a") }
        try journal.claim(job: second, attempt: 0, model: "exact-a")
        expectJournalError { try journal.claim(job: UUID().uuidString.lowercased(), attempt: 0, model: "exact-a") }
        try journal.complete(job: second, attempt: 0)
        expectJournalError { try journal.claim(job: second, attempt: 0, model: "exact-a") }
        precondition(try journal.unresolvedCount() == 1)
        expectJournalError { try journal.claim(job: second, attempt: 1, model: "exact-b") }
        expectJournalError { try journal.claim(job: first, attempt: 0, model: "exact-a") }
    }
    do {
        let journal = try Journal(directory: path)
        precondition(try journal.unresolvedCount() == 1)
        precondition(try journal.uncertainCount() == 1)
        try journal.complete(job: first, attempt: 0)
        precondition(try journal.unresolvedCount() == 0)
        try journal.setDesired(service: "mlx", desired: "maintenance")
        precondition(try journal.desired(service: "mlx") == "maintenance")
        expectJournalError { try journal.setDesired(service: "shell", desired: "running") }
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: path.appendingPathComponent("state.sqlite").path)
    precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    // A version0/unmarked database can be the application's own SQLite file.
    // Never adopt it just because the operator supplied a private directory.
    for version in [0, 5, 7] {
        let foreign = path.appendingPathComponent("foreign-\(version)")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = foreign.appendingPathComponent("state.sqlite")
        var database: OpaquePointer?
        precondition(sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
        precondition(sqlite3_exec(database, "CREATE TABLE conversations(id TEXT PRIMARY KEY); PRAGMA user_version=\(version)", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let before = try Data(contentsOf: file)
        expectJournalError { try Journal(directory: foreign) }
        precondition(try Data(contentsOf: file) == before)
        precondition(!FileManager.default.fileExists(atPath: file.path + "-wal"))
        precondition(!FileManager.default.fileExists(atPath: file.path + "-shm"))
    }
    let ambiguous = path.appendingPathComponent("preexisting-empty")
    try FileManager.default.createDirectory(at: ambiguous, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let empty = ambiguous.appendingPathComponent("state.sqlite")
    try Data().write(to: empty)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: empty.path)
    expectJournalError { try Journal(directory: ambiguous) }
    precondition(try Data(contentsOf: empty).isEmpty)
    print("PASS: isolated SQLite ownership, restart, maintenance, permissions and foreign/ambiguous file refusal without adoption")
}
