import Foundation
import Darwin
import CSQLite

public enum JournalError: Error { case invalid, locked, storage, conflict, trackingLimit }

// Owned by one serialized manager loop. Never share across threads or open
// Fios's database. Values are bound parameters; no workload content is stored.
public final class Journal {
    let directory:URL
    private var db: OpaquePointer?
    private var lockFD: Int32 = -1
    // Single serialized owner and exclusive writer lock. Cache decoded bounded
    // records between SQL mutations; every execute/transaction edge invalidates.
    private var jobsCache:[DurableJob]?
    private var sandboxesCache:[SandboxRecord]?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL) throws {
        self.directory=directory
        guard directory.isFileURL else { throw JournalError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(), (info.st_mode & 0o7777) == 0o700 else { throw JournalError.invalid }
        lockFD = open(directory.appendingPathComponent("manager.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard lockFD >= 0 else { throw JournalError.storage }
        var lockInfo=stat()
        guard fstat(lockFD,&lockInfo)==0,lockInfo.st_mode&S_IFMT==S_IFREG,lockInfo.st_nlink==1,
              lockInfo.st_uid==geteuid(),lockInfo.st_mode&0o7777==0o600 else {
            close(lockFD);lockFD = -1;throw JournalError.invalid
        }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD); lockFD = -1; throw JournalError.locked
        }
        do {
            var namedLock=stat()
            guard lstat(directory.appendingPathComponent("manager.lock").path,&namedLock)==0,
                  namedLock.st_dev==lockInfo.st_dev,namedLock.st_ino==lockInfo.st_ino,
                  namedLock.st_mode==lockInfo.st_mode,namedLock.st_uid==lockInfo.st_uid,namedLock.st_nlink==1 else {throw JournalError.invalid}
            let file = directory.appendingPathComponent("state.sqlite").path
            var created = true
            var fd = open(file, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            if fd < 0 && errno == EEXIST {
                created = false
                fd = open(file, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            }
            guard fd >= 0 else { throw JournalError.storage }
            var state = stat()
            let valid = fstat(fd, &state) == 0 && (state.st_mode & S_IFMT) == S_IFREG && state.st_nlink == 1 && state.st_uid == geteuid() && (state.st_mode & 0o7777) == 0o600 &&
                (created ? state.st_size == 0 : Self.platformHeader(fd: fd, bytes: state.st_size))
            close(fd)
            // Refuse foreign/unmarked/ambiguous existing files BEFORE opening
            // SQLite: even a read-write open may recover WAL/create sidecars.
            guard valid else { throw JournalError.invalid }
            let snapshot:JournalSchemaSnapshot? = created ? nil : try JournalSchemaSnapshot(source:directory)
            defer {withExtendedLifetime(snapshot) {}}
            let inspection=snapshot?.directory.appendingPathComponent("state.sqlite").path ?? file
            guard sqlite3_open_v2(inspection, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw JournalError.storage }
            sqlite3_busy_timeout(db, 1000)
            let version = try scalar("PRAGMA user_version")
            let application=try scalar("PRAGMA application_id")
            if created {
                guard version==0,application==0 else {throw JournalError.invalid}
            } else {
                // A marker/version alone is not permission to repair/adopt an
                // unknown layout. Inspect/recover only a bounded private copy
                // before touching the original with SQLite. Older layouts need
                // an explicit reviewed migration.
                guard version==8,application==0x46495339 else {throw JournalError.invalid}
                try validateCurrentSchema()
                try validateOwnershipRecords()
                guard sqlite3_close(db)==SQLITE_OK else {throw JournalError.storage}
                db=nil;jobsCache=nil;sandboxesCache=nil
                guard sqlite3_open_v2(file,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {throw JournalError.storage}
                sqlite3_busy_timeout(db,1000)
                guard try scalar("PRAGMA user_version")==8,try scalar("PRAGMA application_id")==0x46495339 else {throw JournalError.invalid}
                try validateCurrentSchema()
                try validateOwnershipRecords()
            }
            // Write the platform marker before a new database enters WAL, so
            // offline backup can identify even its first uncheckpointed boot.
            try execute("PRAGMA application_id=0x46495339")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS inference(job TEXT NOT NULL, attempt INTEGER NOT NULL CHECK(attempt BETWEEN 0 AND 3), model TEXT NOT NULL, uncertain INTEGER NOT NULL CHECK(uncertain IN(0,1)), PRIMARY KEY(job,attempt))")
            try execute("CREATE TABLE IF NOT EXISTS inference_scopes(job TEXT NOT NULL,attempt INTEGER NOT NULL CHECK(attempt BETWEEN 0 AND 3),payload TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('reserved','dispatched','uncertain','complete','not_sent')),PRIMARY KEY(job,attempt))")
            try execute("CREATE TABLE IF NOT EXISTS services(service TEXT PRIMARY KEY CHECK(service IN('mlx','orbstack')),desired TEXT NOT NULL CHECK(desired IN('running','maintenance','stopped')))")
            try execute("CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,idempotency TEXT NOT NULL UNIQUE,payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS request_history(job TEXT NOT NULL,attempt INTEGER NOT NULL,model TEXT NOT NULL,PRIMARY KEY(job,attempt))")
            if try scalar("SELECT count(*) FROM pragma_table_info('request_history') WHERE name='request_id'")==0 {
                try execute("ALTER TABLE request_history ADD COLUMN request_id TEXT")
            }
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS request_identity ON request_history(job,request_id) WHERE request_id IS NOT NULL")
            try execute("INSERT OR IGNORE INTO request_history(job,attempt,model) SELECT job,attempt,model FROM inference")
            try execute("CREATE TABLE IF NOT EXISTS sandboxes(job TEXT PRIMARY KEY,payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS worker_grants(job TEXT NOT NULL,attempt INTEGER NOT NULL,payload TEXT NOT NULL,reaped INTEGER NOT NULL CHECK(reaped IN(0,1)),PRIMARY KEY(job,attempt))")
            try execute("CREATE TABLE IF NOT EXISTS worker_launches(job TEXT NOT NULL,attempt INTEGER NOT NULL,nonce TEXT NOT NULL,boot TEXT NOT NULL,reaped INTEGER NOT NULL CHECK(reaped IN(0,1)),PRIMARY KEY(job,attempt))")
            for record in try workerGrants() {
                try execute("INSERT OR IGNORE INTO worker_launches VALUES(?,?,?,?,0)",[record.job,String(record.attempt),UUID().uuidString.lowercased(),record.grant.boot])
            }
            try execute("PRAGMA user_version=8")
            try recoverJobs()
            // Restart never proves native completion.
            try transaction {
                try execute("UPDATE inference SET uncertain=1")
                try execute("UPDATE inference_scopes SET state='uncertain' WHERE state IN('reserved','dispatched')")
            }
        } catch {
            if let db { sqlite3_close(db); self.db = nil }
            close(lockFD); lockFD = -1
            throw error
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) }
    }

    private static func platformHeader(fd: Int32, bytes: off_t) -> Bool {
        guard bytes >= 100 else { return false }
        var header = [UInt8](repeating: 0, count: 100), offset = 0
        while offset < header.count {
            let count = header.withUnsafeMutableBytes {
                Darwin.pread(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset, off_t(offset))
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return false }
            offset += count
        }
        func word(_ index: Int) -> UInt32 {
            UInt32(header[index]) << 24 | UInt32(header[index + 1]) << 16 |
                UInt32(header[index + 2]) << 8 | UInt32(header[index + 3])
        }
        // The marker is written before WAL on first creation, so legitimate
        // platform state never needs adoption of an unmarked main database.
        return Array(header.prefix(16)) == Array("SQLite format 3\0".utf8) &&
            word(68) == 0x46495339 && word(60) <= 8
    }

    private func validateCurrentSchema() throws {
        // Exact reviewed v8 SQL, normalized only for whitespace. Preserve case
        // in quoted CHECK values; do not silently weaken constraints, rebuild
        // indexes or discard future tables/columns/ownership during startup.
        let expected:[String:String]=[
            "inference":"CREATE TABLE inference(job TEXT NOT NULL, attempt INTEGER NOT NULL CHECK(attempt BETWEEN 0 AND 3), model TEXT NOT NULL, uncertain INTEGER NOT NULL CHECK(uncertain IN(0,1)), PRIMARY KEY(job,attempt))",
            "inference_scopes":"CREATE TABLE inference_scopes(job TEXT NOT NULL,attempt INTEGER NOT NULL CHECK(attempt BETWEEN 0 AND 3),payload TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('reserved','dispatched','uncertain','complete','not_sent')),PRIMARY KEY(job,attempt))",
            "services":"CREATE TABLE services(service TEXT PRIMARY KEY CHECK(service IN('mlx','orbstack')),desired TEXT NOT NULL CHECK(desired IN('running','maintenance','stopped')))",
            "jobs":"CREATE TABLE jobs(id TEXT PRIMARY KEY,idempotency TEXT NOT NULL UNIQUE,payload TEXT NOT NULL)",
            "request_history":"CREATE TABLE request_history(job TEXT NOT NULL,attempt INTEGER NOT NULL,model TEXT NOT NULL, request_id TEXT,PRIMARY KEY(job,attempt))",
            "request_identity":"CREATE UNIQUE INDEX request_identity ON request_history(job,request_id) WHERE request_id IS NOT NULL",
            "sandboxes":"CREATE TABLE sandboxes(job TEXT PRIMARY KEY,payload TEXT NOT NULL)",
            "worker_grants":"CREATE TABLE worker_grants(job TEXT NOT NULL,attempt INTEGER NOT NULL,payload TEXT NOT NULL,reaped INTEGER NOT NULL CHECK(reaped IN(0,1)),PRIMARY KEY(job,attempt))",
            "worker_launches":"CREATE TABLE worker_launches(job TEXT NOT NULL,attempt INTEGER NOT NULL,nonce TEXT NOT NULL,boot TEXT NOT NULL,reaped INTEGER NOT NULL CHECK(reaped IN(0,1)),PRIMARY KEY(job,attempt))"
        ]
        func normalized(_ value:String)->String {
            var result="",quote:Character?
            for character in value {
                if let active=quote {
                    result.append(character)
                    if character==active {quote=nil}
                } else if character=="'" || character=="\"" || character=="`" {
                    quote=character;result.append(character)
                } else if !character.isWhitespace {result.append(character)}
            }
            return result
        }
        // GLOB's underscore is literal; LIKE would hide sqliteX_future too.
        let query=try statement("SELECT name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*'")
        defer {sqlite3_finalize(query)}
        var actual:[String:String]=[:]
        while true {
            let result=sqlite3_step(query)
            if result==SQLITE_DONE {break}
            guard result==SQLITE_ROW,let name=sqlite3_column_text(query,0),let sql=sqlite3_column_text(query,1) else {throw JournalError.invalid}
            let key=String(cString:name)
            guard actual.count<expected.count,actual[key]==nil else {throw JournalError.invalid}
            actual[key]=normalized(String(cString:sql))
        }
        guard actual==expected.mapValues(normalized) else {throw JournalError.invalid}
        let check=try statement("PRAGMA quick_check")
        defer {sqlite3_finalize(check)}
        guard sqlite3_step(check)==SQLITE_ROW,let result=sqlite3_column_text(check,0),String(cString:result)=="ok",sqlite3_step(check)==SQLITE_DONE else {throw JournalError.invalid}
    }

    private func storedBytes(_ statement:OpaquePointer,_ column:Int32,maximum:Int) throws -> Data {
        guard sqlite3_column_type(statement,column)==SQLITE_TEXT else {throw JournalError.invalid}
        let count=Int(sqlite3_column_bytes(statement,column))
        guard count>0,count<=maximum,let value=sqlite3_column_text(statement,column) else {throw JournalError.invalid}
        return Data(bytes:value,count:count) // Never truncate persistent TEXT at NUL.
    }
    private func storedString(_ statement:OpaquePointer,_ column:Int32,maximum:Int=128) throws -> String {
        let data=try storedBytes(statement,column,maximum:maximum)
        guard !data.contains(0),let value=String(data:data,encoding:.utf8) else {throw JournalError.invalid}
        return value
    }
    private func validateOwnershipRecords() throws {
        _=try jobs();_=try sandboxRecords()
        // Every persisted identity participates in recovery, including history
        // and retired local workers. Validate before any restart writes, not
        // only when a particular active record happens to be queried later.
        for table in ["inference","request_history"] {
            let fields=table=="inference" ? "job,attempt,model,uncertain" : "job,attempt,model,request_id"
            let rows=try statement("SELECT \(fields) FROM \(table)")
            defer {sqlite3_finalize(rows)}
            var count=0
            while true {
                let code=sqlite3_step(rows)
                if code==SQLITE_DONE {break}
                guard code==SQLITE_ROW,count<(table=="inference" ? 2:1024),
                      sqlite3_column_type(rows,1)==SQLITE_INTEGER else {throw JournalError.invalid}
                try validate(job:storedString(rows,0),attempt:Int(sqlite3_column_int64(rows,1)))
                let bytes=try storedBytes(rows,2,maximum:WireLimits.modelBytes)
                guard let model=String(data:bytes,encoding:.utf8),WireScalar.model(model) else {throw JournalError.invalid}
                if table=="inference" {
                    guard sqlite3_column_type(rows,3)==SQLITE_INTEGER,(0...1).contains(sqlite3_column_int64(rows,3)) else {throw JournalError.invalid}
                } else if sqlite3_column_type(rows,3) != SQLITE_NULL {
                    try validate(job:storedString(rows,3),attempt:0)
                }
                count+=1
            }
        }
        try validateInferenceScopes()
        let launches=try statement("SELECT job,attempt,nonce,boot,reaped FROM worker_launches")
        defer {sqlite3_finalize(launches)}
        var launchesCount=0
        while true {
            let code=sqlite3_step(launches)
            if code==SQLITE_DONE {break}
            guard code==SQLITE_ROW,launchesCount<1024,sqlite3_column_type(launches,1)==SQLITE_INTEGER,
                  sqlite3_column_type(launches,4)==SQLITE_INTEGER,(0...1).contains(sqlite3_column_int64(launches,4)) else {throw JournalError.invalid}
            try validate(job:storedString(launches,0),attempt:Int(sqlite3_column_int64(launches,1)))
            try validate(job:storedString(launches,2),attempt:0)
            try validate(job:storedString(launches,3),attempt:0)
            launchesCount+=1
        }
        // Include reaped grants: unknown ownership fields cannot be silently
        // hidden in historical metadata and later rewritten by another tool.
        let stmt=try statement("SELECT job,attempt,payload FROM worker_grants ORDER BY job,attempt")
        defer {sqlite3_finalize(stmt)}
        var count=0
        while true {
            let result=sqlite3_step(stmt)
            if result==SQLITE_DONE {break}
            guard result==SQLITE_ROW,count<1024,sqlite3_column_type(stmt,1)==SQLITE_INTEGER else {throw JournalError.invalid}
            let job=try storedString(stmt,0),attempt=Int(sqlite3_column_int64(stmt,1))
            try validate(job:job,attempt:attempt)
            _=try OwnershipRecordCodec.worker(storedBytes(stmt,2,maximum:512));count+=1
        }
    }

    private func statement(_ sql: String, _ values: [String] = []) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw JournalError.storage }
        for (index, value) in values.enumerated() {
            guard sqlite3_bind_text(stmt, Int32(index + 1), value, Int32(value.utf8.count), transient) == SQLITE_OK else {
                sqlite3_finalize(stmt); throw JournalError.storage
            }
        }
        return stmt
    }
    private func execute(_ sql: String, _ values: [String] = []) throws {
        jobsCache=nil;sandboxesCache=nil
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw JournalError.storage }
    }
    private func scalar(_ sql: String, _ values: [String] = []) throws -> Int {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw JournalError.storage }
        return Int(sqlite3_column_int64(stmt, 0))
    }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func validate(job: String, attempt: Int) throws {
        guard let uuid = UUID(uuidString: job), uuid.uuidString.lowercased() == job,
              (0...3).contains(attempt) else { throw JournalError.invalid }
    }
    func requestCount(job:String) throws -> Int {
        try validate(job:job,attempt:0)
        return try scalar("SELECT count(*) FROM request_history WHERE job=?",[job])
    }
    public func claim(job: String, attempt: Int, model: String,requestID:String?=nil) throws {
        try claim(job:job,attempt:attempt,model:model,requestID:requestID,scope:nil)
    }
    func claim(job:String,attempt:Int,model:String,requestID:String?=nil,scope:InferenceScope) throws {
        try claim(job:job,attempt:attempt,model:model,requestID:requestID,scope:Optional(scope))
    }
    private func claim(job:String,attempt:Int,model:String,requestID:String?,scope:InferenceScope?) throws {
        try validate(job:job,attempt:attempt)
        let payload=try scope.map { try $0.encoded() }
        if let scope {guard WireScalar.exactModel(scope.canonicalModel,model) else {throw JournalError.invalid}}
        if let requestID { try validate(job:requestID,attempt:0) }
        guard WireScalar.model(model) else { throw JournalError.invalid }
        try transaction {
            guard try scalar("SELECT count(*) FROM inference") < 2,
                  try scalar("SELECT count(*) FROM request_history") < 1024 else { throw JournalError.trackingLimit }
            guard try scalar("SELECT count(*) FROM request_history WHERE job=?",[job]) == attempt else { throw JournalError.conflict }
            if let requestID {
                guard try scalar("SELECT count(*) FROM request_history WHERE job=? AND request_id=?",[job,requestID])==0 else { throw JournalError.conflict }
            }
            guard try scalar("SELECT count(*) FROM request_history WHERE job=? AND model != ?",[job,model]) == 0 else { throw JournalError.conflict }
            guard try scalar("SELECT count(*) FROM inference WHERE model != ?", [model]) == 0,
                  try scalar("SELECT count(*) FROM inference WHERE job=?",[job]) == 0 else { throw JournalError.conflict }
            guard try scalar("SELECT count(*) FROM inference WHERE job=? AND attempt=?", [job, String(attempt)]) == 0 else { throw JournalError.conflict }
            try execute("INSERT INTO inference(job,attempt,model,uncertain) VALUES(?,?,?,0)", [job,String(attempt),model])
            // Explicit null is a low-level unbound fixture claim, never an
            // absent metadata row that could silently downgrade a bound one.
            try execute("INSERT INTO inference_scopes(job,attempt,payload,state) VALUES(?,?,?,'reserved')",[job,String(attempt),payload.map {String(decoding:$0,as:UTF8.self)} ?? "null"])
            if let requestID {
                try execute("INSERT INTO request_history(job,attempt,model,request_id) VALUES(?,?,?,?)",[job,String(attempt),model,requestID])
            } else {
                try execute("INSERT INTO request_history(job,attempt,model) VALUES(?,?,?)",[job,String(attempt),model])
            }
        }
    }
    public func markUncertain(job: String, attempt: Int) throws {
        try validate(job: job, attempt: attempt)
        try transaction {
            try execute("UPDATE inference SET uncertain=1 WHERE job=? AND attempt=?", [job,String(attempt)])
            guard sqlite3_changes(db) == 1 else { throw JournalError.invalid }
            try execute("UPDATE inference_scopes SET state='uncertain' WHERE job=? AND attempt=? AND state IN('reserved','dispatched','uncertain')",[job,String(attempt)])
            guard sqlite3_changes(db)==1 else {throw JournalError.invalid}
        }
    }
    // Trusted correlated completion proof is required by the caller. This is
    // never a task/sandbox RPC. Cancellation is markUncertain, not complete.
    public func complete(job: String, attempt: Int) throws {
        try validate(job: job, attempt: attempt)
        guard try scalar("SELECT count(*) FROM inference_scopes WHERE job=? AND attempt=? AND payload='null'",[job,String(attempt)])==1 else {throw JournalError.conflict}
        try transaction {
            try execute("DELETE FROM inference WHERE job=? AND attempt=?", [job,String(attempt)])
            guard sqlite3_changes(db) == 1 else { throw JournalError.invalid }
            try execute("UPDATE inference_scopes SET state='complete' WHERE job=? AND attempt=?",[job,String(attempt)])
        }
    }
    func inferenceScope(job:String,attempt:Int) throws -> InferenceScopeRecord? {
        try validate(job:job,attempt:attempt)
        let row=try statement("SELECT payload,state FROM inference_scopes WHERE job=? AND attempt=?",[job,String(attempt)])
        defer {sqlite3_finalize(row)}
        let code=sqlite3_step(row)
        if code==SQLITE_DONE {return nil}
        guard code==SQLITE_ROW,let state=InferenceState(rawValue:try storedString(row,1)) else {throw JournalError.invalid}
        let bytes=try storedBytes(row,0,maximum:InferenceScope.maximumBytes)
        if bytes==Data("null".utf8) {return nil}
        let scope=try InferenceScope.decode(bytes)
        guard sqlite3_step(row)==SQLITE_DONE else {throw JournalError.invalid}
        return InferenceScopeRecord(scope:scope,state:state)
    }
    private func validateInferenceScopes() throws {
        guard try scalar("SELECT count(*) FROM request_history h WHERE NOT EXISTS(SELECT 1 FROM inference_scopes s WHERE s.job=h.job AND s.attempt=h.attempt)")==0,
              try scalar("SELECT count(*) FROM inference i WHERE NOT EXISTS(SELECT 1 FROM inference_scopes s WHERE s.job=i.job AND s.attempt=i.attempt)")==0 else {throw JournalError.invalid}
        let rows=try statement("SELECT job,attempt,payload,state FROM inference_scopes")
        defer {sqlite3_finalize(rows)}
        var count=0
        while true {
            let code=sqlite3_step(rows)
            if code==SQLITE_DONE {break}
            guard code==SQLITE_ROW,count<1024,sqlite3_column_type(rows,1)==SQLITE_INTEGER,
                  let state=InferenceState(rawValue:try storedString(rows,3)) else {throw JournalError.invalid}
            let job=try storedString(rows,0),attempt=Int(sqlite3_column_int64(rows,1))
            try validate(job:job,attempt:attempt)
            let bytes=try storedBytes(rows,2,maximum:InferenceScope.maximumBytes)
            let scope=bytes==Data("null".utf8) ? nil : try InferenceScope.decode(bytes)
            let arguments=[job,String(attempt)]
            guard try scalar("SELECT count(*) FROM request_history WHERE job=? AND attempt=?",arguments)==1 else {throw JournalError.invalid}
            if let scope {
                guard try scalar("SELECT count(*) FROM request_history WHERE job=? AND attempt=? AND model=?",arguments+[scope.canonicalModel])==1 else {throw JournalError.invalid}
            }
            let unresolved = ![InferenceState.complete,.not_sent].contains(state)
            guard try scalar("SELECT count(*) FROM inference WHERE job=? AND attempt=?",arguments)==(unresolved ? 1:0),
                  try scalar("SELECT count(*) FROM inference i JOIN request_history h ON i.job=h.job AND i.attempt=h.attempt AND i.model=h.model WHERE i.job=? AND i.attempt=?",arguments)==(unresolved ? 1:0) else {throw JournalError.invalid}
            if unresolved {
                guard try scalar("SELECT count(*) FROM inference WHERE job=? AND attempt=? AND uncertain=?",[job,String(attempt),state == .uncertain ? "1":"0"])==1 else {throw JournalError.invalid}
            }
            count+=1
        }
    }
    // Persist before any permission bytes can reach the worker. This means
    // dispatch MAY occur, not that a POST has actually happened; failure/exit
    // after this edge stays uncertain until correlated evidence resolves it.
    func markDispatched(job:String,attempt:Int) throws {
        try validate(job:job,attempt:attempt)
        guard let record=try inferenceScope(job:job,attempt:attempt),record.state == .reserved else {throw JournalError.conflict}
        try execute("UPDATE inference_scopes SET state='dispatched' WHERE job=? AND attempt=? AND state='reserved'",[job,String(attempt)])
        guard sqlite3_changes(db)==1 else {throw JournalError.conflict}
    }
    // Trusted broker/validated private-worker evidence only; never task IPC.
    // Scope correlation is necessary, not sufficient evidence of native
    // terminality. No timer, restart or new health invokes this operation.
    func resolveInference(job:String,attempt:Int,scope:InferenceScope,outcome:InferenceState) throws {
        guard [.complete,.not_sent].contains(outcome),
              let record=try inferenceScope(job:job,attempt:attempt),
              ![InferenceState.complete,.not_sent].contains(record.state),
              outcome != .complete || record.state != .reserved,
              try record.scope.encoded()==scope.encoded() else {throw JournalError.conflict}
        try transaction {
            try execute("DELETE FROM inference WHERE job=? AND attempt=?",[job,String(attempt)])
            guard sqlite3_changes(db)==1 else {throw JournalError.conflict}
            try execute("UPDATE inference_scopes SET state=? WHERE job=? AND attempt=?",[outcome.rawValue,job,String(attempt)])
            guard sqlite3_changes(db)==1 else {throw JournalError.conflict}
        }
    }
    func jobs() throws -> [DurableJob] {
        if let jobsCache {return jobsCache}
        let stmt=try statement("SELECT id,idempotency,payload FROM jobs ORDER BY id");defer { sqlite3_finalize(stmt) }
        var result:[DurableJob]=[]
        while true {
            let code=sqlite3_step(stmt)
            if code==SQLITE_DONE {jobsCache=result;return result}
            guard code==SQLITE_ROW,result.count<256 else { throw JournalError.storage }
            let record=try OwnershipRecordCodec.job(storedBytes(stmt,2,maximum:4096))
            guard record.id == (try storedString(stmt,0)),record.idempotency == (try storedString(stmt,1)) else {throw JournalError.invalid}
            result.append(record)
        }
    }
    func newestJobIDs() throws -> [String] {
        let stmt=try statement("SELECT id FROM jobs ORDER BY rowid DESC");defer {sqlite3_finalize(stmt)}
        var ids:[String]=[]
        while true {
            let code=sqlite3_step(stmt)
            if code==SQLITE_DONE { return ids }
            guard code==SQLITE_ROW,ids.count<256,let text=sqlite3_column_text(stmt,0) else { throw JournalError.storage }
            ids.append(String(cString:text))
        }
    }
    private func saveJob(_ job:DurableJob) throws {
        let data=try JSONEncoder().encode(job)
        guard data.count<=4096,let value=String(data:data,encoding:.utf8) else { throw JournalError.invalid }
        try execute("INSERT INTO jobs(id,idempotency,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",[job.id,job.idempotency,value])
    }
    private func recoverJobs() throws {
        try transaction {
            for var job in try jobs() where job.state != .removed {
                job.state = .reconciling;job.lease.revoke();try saveJob(job)
            }
        }
    }
    func reserveJob(_ proposed:DurableJob) throws -> DurableJob {
        var result=proposed
        try transaction {
            let existing=try jobs()
            if let found=existing.first(where:{$0.id==proposed.id || $0.idempotency==proposed.idempotency}) {
                guard found.ownerHash==proposed.ownerHash,found.requestHash==proposed.requestHash,
                      found.idempotency==proposed.idempotency else { throw JournalError.conflict }
                result=found;return
            }
            let sandboxIDs=Set(try sandboxRecords().map { $0.configuration.job })
            let active=existing.filter {$0.state != .removed}
            guard existing.count<256,active.count<4,active.filter({!sandboxIDs.contains($0.id)}).count<2,
                  proposed.state == .reserved,!proposed.lease.revoked else { throw JournalError.trackingLimit }
            try saveJob(proposed)
        }
        return result
    }
    func sandboxRecords() throws -> [SandboxRecord] {
        if let sandboxesCache {return sandboxesCache}
        let stmt=try statement("SELECT job,payload FROM sandboxes ORDER BY job");defer { sqlite3_finalize(stmt) }
        var result:[SandboxRecord]=[]
        while true {
            let code=sqlite3_step(stmt)
            if code==SQLITE_DONE {sandboxesCache=result;return result}
            guard code==SQLITE_ROW,result.count<256 else { throw JournalError.storage }
            let record=try OwnershipRecordCodec.sandbox(storedBytes(stmt,1,maximum:4096))
            guard record.configuration.job == (try storedString(stmt,0)) else {throw JournalError.invalid}
            result.append(record)
        }
    }
    private func writeSandbox(_ record:SandboxRecord) throws {
        let data=try JSONEncoder().encode(record)
        guard data.count<=4096,let value=String(data:data,encoding:.utf8) else { throw JournalError.invalid }
        try execute("INSERT INTO sandboxes VALUES(?,?) ON CONFLICT(job) DO UPDATE SET payload=excluded.payload",[record.configuration.job,value])
    }
    func reserveSandbox(job:DurableJob,configuration:SandboxConfiguration) throws -> SandboxRecord {
        guard job.id==configuration.job else { throw JournalError.invalid }
        var result=SandboxRecord(configuration:configuration)
        try transaction {
            let existing=try jobs(),sandboxes=try sandboxRecords()
            if let found=existing.first(where:{$0.id==job.id || $0.idempotency==job.idempotency}) {
                guard found.id==job.id,found.ownerHash==job.ownerHash,found.requestHash==job.requestHash,
                      found.idempotency==job.idempotency,
                      let saved=sandboxes.first(where:{$0.configuration.job==found.id}),saved.configuration==configuration else { throw JournalError.conflict }
                result=saved;return
            }
            let active=sandboxes.filter { sandbox in existing.first(where:{$0.id==sandbox.configuration.job})?.state != .removed }
            guard existing.count<256,existing.filter({$0.state != .removed}).count<4,
                  active.count<2,active.reduce(0,{$0+$1.configuration.cpus})+configuration.cpus<=4,
                  active.reduce(UInt64(0),{$0+$1.configuration.memory})+configuration.memory<=4<<30,
                  job.state == .reserved,!job.lease.revoked else { throw JournalError.trackingLimit }
            try saveJob(job);try writeSandbox(result)
        }
        return result
    }
    func saveSandbox(_ proposed:SandboxRecord) throws {
        try transaction {
            guard let old=try sandboxRecords().first(where:{$0.configuration.job==proposed.configuration.job}),
                  old.configuration==proposed.configuration,!old.createIssued || proposed.createIssued,
                  !old.startIssued || proposed.startIssued,!old.removalProven || proposed.removalProven,
                  old.runtimeID==nil || old.runtimeID==proposed.runtimeID else { throw JournalError.conflict }
            if let id=proposed.runtimeID {
                guard proposed.createIssued,id.utf8.count==64,
                      id.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}) else { throw JournalError.invalid }
            }
            guard !proposed.startIssued || (proposed.createIssued && proposed.runtimeID != nil),
                  !proposed.removalProven || (!proposed.createIssued || proposed.runtimeID != nil),
                  !old.removalProven || (old.startIssued==proposed.startIssued && old.createIssued==proposed.createIssued) else { throw JournalError.invalid }
            try writeSandbox(proposed)
        }
    }
    // Called only by a trusted runtime adapter after a successful absence
    // observation. An unknown create with no returned ID can still materialize;
    // a snapshot of absence alone is NOT proof its daemon action was cancelled.
    func confirmSandboxAbsent(job:String) throws {
        guard var record=try sandboxRecords().first(where:{$0.configuration.job==job}),
              !record.createIssued || record.runtimeID != nil else { throw JournalError.conflict }
        record.removalProven=true;try saveSandbox(record)
    }
    func transitionJob(id:String,to next:JobState,now:Int64=Int64(Date().timeIntervalSince1970*1000)) throws {
        guard now>=0,now<=ActivityPolicy.maximumTimestamp else { throw JournalError.invalid }
        try transaction {
            guard var job=try jobs().first(where:{$0.id==id}) else { throw JournalError.invalid }
            guard job.state.permits(next) else { throw JournalError.conflict }
            job.state=next
            if next == .removed {
                if let sandbox=try sandboxRecords().first(where:{$0.configuration.job==id}),!sandbox.removalProven { throw JournalError.conflict }
                guard now>=job.lease.created else { throw JournalError.invalid }
                job.closedAt=now
            }
            if [.revoking,.stopping,.removing,.removed,.reconciling].contains(next) { job.lease.revoke() }
            try saveJob(job)
        }
    }
    func renewJob(id:String,ownerHash:String,now:Int64) throws {
        var expired=false
        try transaction {
            guard var job=try jobs().first(where:{$0.id==id}) else { throw JournalError.invalid }
            guard job.ownerHash==ownerHash,[.reserved,.creating,.running].contains(job.state) else { throw JournalError.conflict }
            do { try job.lease.renew(now:now) }
            catch AdmissionError.expired { job.state = .revoking;expired=true }
            try saveJob(job)
        }
        if expired { throw AdmissionError.expired }
    }
    func expireTerminalJobs(now:Int64) throws {
        guard now>=0,now<=ActivityPolicy.maximumTimestamp else { throw JournalError.invalid }
        try transaction {
            for job in try jobs() where job.state == .removed {
                guard let closed=job.closedAt,closed>=job.lease.created,now>=closed,
                      now-closed>=86_400_000,
                      try scalar("SELECT count(*) FROM inference WHERE job=?",[job.id]) == 0,
                      try scalar("SELECT count(*) FROM worker_grants WHERE job=? AND reaped=0",[job.id]) == 0,
                      try scalar("SELECT count(*) FROM worker_launches WHERE job=? AND reaped=0",[job.id]) == 0 else { continue }
                // Only metadata/tombstones are pruned. Unresolved inference
                // has independent lifetime and is never expired by a clock.
                try execute("DELETE FROM worker_grants WHERE job=? AND reaped=1",[job.id])
                try execute("DELETE FROM worker_launches WHERE job=? AND reaped=1",[job.id])
                try execute("DELETE FROM inference_scopes WHERE job=? AND state IN('complete','not_sent')",[job.id])
                try execute("DELETE FROM request_history WHERE job=?",[job.id])
                try execute("DELETE FROM sandboxes WHERE job=?",[job.id])
                try execute("DELETE FROM jobs WHERE id=?",[job.id])
            }
        }
    }
    func activeLaunches() throws -> [(job:String,attempt:Int,nonce:String,boot:String)] {
        let stmt=try statement("SELECT job,attempt,nonce,boot FROM worker_launches WHERE reaped=0 ORDER BY job,attempt")
        defer { sqlite3_finalize(stmt) }
        var result:[(job:String,attempt:Int,nonce:String,boot:String)]=[]
        while true {
            let code=sqlite3_step(stmt)
            if code==SQLITE_DONE { return result }
            guard code==SQLITE_ROW,result.count<2,let job=sqlite3_column_text(stmt,0),
                  let nonce=sqlite3_column_text(stmt,2),let boot=sqlite3_column_text(stmt,3) else { throw JournalError.storage }
            let id=String(cString:job),attempt=Int(sqlite3_column_int(stmt,1)),token=String(cString:nonce),session=String(cString:boot)
            try validate(job:id,attempt:attempt)
            guard UUID(uuidString:token)?.uuidString.lowercased()==token,
                  UUID(uuidString:session)?.uuidString.lowercased()==session else { throw JournalError.invalid }
            result.append((id,attempt,token,session))
        }
    }
    func activeLaunchCount() throws -> Int { try scalar("SELECT count(*) FROM worker_launches WHERE reaped=0") }
    // Commit before fork/spawn. A crash before PID binding still consumes a
    // local worker slot; missing PID metadata is not proof of no process.
    func planWorkerLaunch(job:String,attempt:Int) throws -> String {
        try validate(job:job,attempt:attempt)
        let nonce=UUID().uuidString.lowercased(),boot=try HostBoot.identity()
        try transaction {
            guard try scalar("SELECT count(*) FROM inference WHERE job=? AND attempt=? AND uncertain=0",[job,String(attempt)])==1,
                  try scalar("SELECT count(*) FROM worker_launches WHERE job=? AND attempt=?",[job,String(attempt)])==0,
                  try scalar("SELECT count(*) FROM worker_grants WHERE job=? AND attempt=?",[job,String(attempt)])==0 else { throw JournalError.conflict }
            guard try activeLaunchCount()<2 else { throw JournalError.trackingLimit }
            try execute("INSERT INTO worker_launches VALUES(?,?,?,?,0)",[job,String(attempt),nonce,boot])
        }
        return nonce
    }
    private func grantPayload(_ grant:WorkerGrant) throws -> String {
        try grant.validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return String(decoding:try encoder.encode(grant),as:UTF8.self)
    }
    func bindWorker(job:String,attempt:Int,grant:WorkerGrant) throws {
        try validate(job:job,attempt:attempt)
        let payload=try grantPayload(grant)
        try transaction {
            guard try scalar("SELECT count(*) FROM inference WHERE job=? AND attempt=? AND uncertain=0",[job,String(attempt)])==1,
                  try scalar("SELECT count(*) FROM worker_grants WHERE job=? AND attempt=?",[job,String(attempt)])==0,
                  try scalar("SELECT count(*) FROM worker_launches WHERE job=? AND attempt=? AND boot=? AND reaped=0",[job,String(attempt),grant.boot])==1 else { throw JournalError.conflict }
            guard try scalar("SELECT count(*) FROM worker_grants WHERE reaped=0")<2 else { throw JournalError.trackingLimit }
            try execute("INSERT INTO worker_grants VALUES(?,?,?,0)",[job,String(attempt),payload])
        }
    }
    func workerGrants() throws -> [(job:String,attempt:Int,grant:WorkerGrant)] {
        let stmt=try statement("SELECT job,attempt,payload FROM worker_grants WHERE reaped=0 ORDER BY job,attempt");defer { sqlite3_finalize(stmt) }
        var result:[(job:String,attempt:Int,grant:WorkerGrant)]=[]
        while true {
            let code=sqlite3_step(stmt)
            if code==SQLITE_DONE { return result }
            guard code==SQLITE_ROW,result.count<2,let job=sqlite3_column_text(stmt,0),let payload=sqlite3_column_text(stmt,2) else { throw JournalError.storage }
            let id=String(cString:job),attempt=Int(sqlite3_column_int(stmt,1)),text=String(cString:payload)
            try validate(job:id,attempt:attempt)
            guard text.utf8.count<=512 else { throw JournalError.invalid }
            let grant=try OwnershipRecordCodec.worker(storedBytes(stmt,2,maximum:512))
            result.append((id,attempt,grant))
        }
    }
    func recordWorkerGone(job:String,attempt:Int,grant:WorkerGrant) throws {
        try validate(job:job,attempt:attempt)
        guard try grant.provenGone() else { throw JournalError.conflict }
        try transaction {
            try execute("UPDATE worker_grants SET reaped=1 WHERE job=? AND attempt=? AND payload=?",[job,String(attempt),try grantPayload(grant)])
            guard sqlite3_changes(db)==1 else { throw JournalError.invalid }
            try execute("UPDATE worker_launches SET reaped=1 WHERE job=? AND attempt=? AND boot=?",[job,String(attempt),grant.boot])
        }
    }
    func recordUnboundWorkerGone(job:String,attempt:Int,nonce:String,proof:WorkerCensusAbsence)throws {
        try validate(job:job,attempt:attempt)
        try proof.validate()
        try transaction {
            guard try scalar("SELECT count(*) FROM worker_grants WHERE job=? AND attempt=?",[job,String(attempt)])==0 else {throw JournalError.conflict}
            try execute("UPDATE worker_launches SET reaped=1 WHERE job=? AND attempt=? AND nonce=? AND boot=? AND reaped=0",[job,String(attempt),nonce,proof.boot])
            guard sqlite3_changes(db)==1 else {throw JournalError.conflict}
            // Only local memory/process bookkeeping. Inference is untouched.
        }
    }
    func recoverWorkerMetadata() throws {
        for record in try workerGrants() where try record.grant.provenGone() {
            try recordWorkerGone(job:record.job,attempt:record.attempt,grant:record.grant)
        }
        // A different stable kernel boot positively proves old local PIDs
        // cannot survive. It does NOT prove native request completion.
        try execute("UPDATE worker_launches SET reaped=1 WHERE boot != ?",[try HostBoot.identity()])
        // Native inference rows are deliberately untouched.
    }
    func hasClaim(job:String,attempt:Int) throws -> Bool {
        try validate(job:job,attempt:attempt)
        return try scalar("SELECT count(*) FROM inference WHERE job=? AND attempt=?",[job,String(attempt)]) == 1
    }
    func unresolvedCount(job:String) throws -> Int {
        try validate(job:job,attempt:0)
        return try scalar("SELECT count(*) FROM inference WHERE job=?",[job])
    }
    public func unresolvedCount() throws -> Int { try scalar("SELECT count(*) FROM inference") }
    public func uncertainCount() throws -> Int { try scalar("SELECT count(*) FROM inference WHERE uncertain=1") }
    public func setDesired(service: String, desired: String) throws {
        guard ["mlx","orbstack"].contains(service), ["running","maintenance","stopped"].contains(desired) else { throw JournalError.invalid }
        try execute("INSERT INTO services VALUES(?,?) ON CONFLICT(service) DO UPDATE SET desired=excluded.desired", [service,desired])
    }
    // An absent row is not explicit authority to reopen a native admission
    // fence after restart. Keep the existing display default separate.
    func recordedDesired(service:ManagedService) throws -> ServiceDesired? {
        let stmt=try statement("SELECT desired FROM services WHERE service=?",[service.rawValue])
        defer {sqlite3_finalize(stmt)}
        let result=sqlite3_step(stmt)
        if result==SQLITE_DONE {return nil}
        guard result==SQLITE_ROW,let text=sqlite3_column_text(stmt,0),
              let desired=ServiceDesired(rawValue:String(cString:text)) else {throw JournalError.storage}
        return desired
    }
    public func desired(service: String) throws -> String {
        guard ["mlx","orbstack"].contains(service) else { throw JournalError.invalid }
        let stmt = try statement("SELECT desired FROM services WHERE service=?", [service]); defer { sqlite3_finalize(stmt) }
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return "running" }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(stmt,0) else { throw JournalError.storage }
        return String(cString: text)
    }
}
