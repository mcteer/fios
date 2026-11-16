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
        ("missing-native-scopes","DROP TABLE inference_scopes;",true),
        ("unknown-native-scope-column","ALTER TABLE inference_scopes ADD COLUMN future_proof TEXT;",true),
        ("orphan-native-scope","INSERT INTO inference_scopes VALUES('00000000-0000-0000-0000-000000000001',0,'{}','reserved');",true),
        ("unknown-column","ALTER TABLE jobs ADD COLUMN foreign_state TEXT;",true),
        ("unknown-table","CREATE TABLE future_actions(id TEXT PRIMARY KEY);",true),
        ("missing-request-index","DROP INDEX request_identity;",true),
        ("weakened-service-check","DROP TABLE services; CREATE TABLE services(service TEXT PRIMARY KEY,desired TEXT NOT NULL);",true),
        ("previous-unmigrated-layout","PRAGMA user_version=7;",true),
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
    // A syntactically valid decision cannot be adopted without its original
    // durable local producer. This fixture has no worker launch at all.
    let forged=root.appendingPathComponent("orphan-native-decision"),proofJob=UUID().uuidString.lowercased()
    let proofScope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:String(repeating:"1",count:32),canonicalModel:"fixture/exact",nativeModel:"fixture/exact",sequence:1,sampledAt:10000)
    let proofPeer=NativeControlPeer(pid:42,start:9,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"c",count:64)))
    let proofID=try proofScope.nativeRequestCorrelationID(job:proofJob,attempt:0)
    var consumer=try NativeRequestLineageConsumer(scope:proofScope,job:proofJob,attempt:0,peer:proofPeer)
    let live=NativeRequestLineageSample(peer:proofPeer,sampledAt:10000,lineage:NativeRequestLineage(instance:proofScope.nativeEpoch,correlationID:proofID,sampleSequence:1,rootSequence:UInt64.max,found:true,uncertain:false,references:1,owners:1,ingress:1,preparing:0,active:0,responding:0))
    _=consumer.accept(live,now:10000)
    let cancel=NativeHandoffSample(peer:proofPeer,sampledAt:10001,result:NativeHandoffResult(operation:.cancel,instance:proofScope.nativeEpoch,correlationID:proofID,rootSequence:UInt64.max,sampleSequence:2,state:.cancelled,uncertain:false))
    _=consumer.acceptHandoffCancellation(cancel,now:10001)
    try consumer.recordHandoffClosure(NativeHandoffClosureCheckpoint(version:1,localProducer:"never_spawned",workerMetadataVersion:2,handoffVersion:1,launchNonce:UUID().uuidString.lowercased(),grantSHA256:nil))
    let payload=String(decoding:try consumer.checkpoint(scope:proofScope),as:UTF8.self).replacingOccurrences(of:"'",with:"''")
    do {
        let journal=try Journal(directory:forged)
        try journal.claim(job:proofJob,attempt:0,model:proofScope.canonicalModel,scope:proofScope)
        try journal.markDispatched(job:proofJob,attempt:0)
        _=try journal.observeLineage(job:proofJob,attempt:0,scope:proofScope,peer:proofPeer,sample:live,now:10000)
        try journal.resolveInference(job:proofJob,attempt:0,scope:proofScope,outcome:.not_sent)
    }
    try mutate(forged,"UPDATE native_lineages SET payload='"+payload+"';")
    let proofBefore=SHA256.hash(data:try Data(contentsOf:forged.appendingPathComponent("state.sqlite")))
    do {_=try Journal(directory:forged);fatalError("Orphan native decision adopted without original local producer")}catch JournalError.invalid {}
    guard SHA256.hash(data:try Data(contentsOf:forged.appendingPathComponent("state.sqlite")))==proofBefore else {fatalError("Rejected decision rewrote original state")}
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
