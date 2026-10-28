import Foundation
import Darwin
import CSQLite
import CryptoKit

func runJournalSchemaTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)}
    func mutate(_ directory:URL,_ sql:String)throws {
        let file=directory.appendingPathComponent("state.sqlite")
        var db:OpaquePointer?
        guard sqlite3_open(file.path,&db)==SQLITE_OK else {throw JournalError.storage}
        defer {sqlite3_close(db)}
        guard sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK else {throw JournalError.storage}
        guard chmod(file.path,0o600)==0 else {throw JournalError.storage}
    }
    let cases:[(String,String,Bool)]=[
        ("missing-all","PRAGMA application_id=0x46495339; PRAGMA user_version=7;",false),
        ("missing-inference","DROP TABLE inference;",true),
        ("unknown-column","ALTER TABLE jobs ADD COLUMN foreign_state TEXT;",true),
        ("unknown-table","CREATE TABLE future_actions(id TEXT PRIMARY KEY);",true),
        ("missing-request-index","DROP INDEX request_identity;",true),
        ("weakened-service-check","DROP TABLE services; CREATE TABLE services(service TEXT PRIMARY KEY,desired TEXT NOT NULL);",true),
        ("unknown-older-layout","PRAGMA user_version=6;",true),
        ("sqlite-lookalike-table","CREATE TABLE sqliteX_future_actions(id TEXT PRIMARY KEY);",true),
        ("quoted-check-whitespace","DROP TABLE services; CREATE TABLE services(service TEXT PRIMARY KEY CHECK(service IN('m lx','orbstack')),desired TEXT NOT NULL CHECK(desired IN('running','maintenance','stopped')));",true)
    ]
    var failures:[String]=[]
    for (name,sql,seeded) in cases {
        let directory=root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        if seeded {var journal:Journal?=try Journal(directory:directory);journal=nil;_ = journal}
        try mutate(directory,sql)
        let file=directory.appendingPathComponent("state.sqlite")
        let before=SHA256.hash(data:try Data(contentsOf:file))
        do {_ = try Journal(directory:directory);failures.append("Accepted incompatible marked schema: "+name)}
        catch JournalError.invalid {}
        let after=SHA256.hash(data:try Data(contentsOf:file))
        if before != after {failures.append("Changed rejected schema: "+name)}
    }
    guard failures.isEmpty else {fatalError(failures.joined(separator:"; "))}
    // Exact current layout still reopens and preserves desired/uncertain rows.
    let valid=root.appendingPathComponent("valid"),job=UUID().uuidString.lowercased()
    do {
        let journal=try Journal(directory:valid)
        try journal.claim(job:job,attempt:0,model:"fixture/exact")
        try journal.setDesired(service:"mlx",desired:"maintenance")
    }
    let reopened=try Journal(directory:valid)
    guard try reopened.uncertainCount()==1,try reopened.desired(service:"mlx")=="maintenance" else {fatalError("Current schema lost protected state")}
    print("PASS: incompatible marked schema refused without repair/write; exact current desired and independent uncertainty preserved")
}
