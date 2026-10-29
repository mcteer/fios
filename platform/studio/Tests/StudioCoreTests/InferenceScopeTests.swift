import Foundation
import CSQLite

enum InferenceScopeTests {
    static func run() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let job=UUID().uuidString.lowercased(),newJob=UUID().uuidString.lowercased()
        let scope=InferenceScope(host:"fios-edge-a.lab",endpointHash:String(repeating:"a",count:64),
            profileHash:String(repeating:"b",count:64),managerEpoch:UUID().uuidString.lowercased(),
            nativeEpoch:"native-one",canonicalModel:"fixture/model",nativeModel:"fixture/model",sequence:1,sampledAt:1000)
        func refuses(_ body:()throws->Void) {
            do {try body()}catch{return};fatalError("Uncorrelated inference proof accepted")
        }
        do {
            let journal=try Journal(directory:root)
            try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
            guard try journal.inferenceScope(job:job,attempt:0)?.state == .reserved else {fatalError("Incorrect persistent inference state")}
            refuses {try journal.complete(job:job,attempt:0)}
            try journal.markDispatched(job:job,attempt:0)
            refuses {try journal.markDispatched(job:job,attempt:0)}
            try journal.markUncertain(job:job,attempt:0)
            try journal.claim(job:newJob,attempt:0,model:scope.canonicalModel,scope:scope)
            refuses {try journal.resolveInference(job:newJob,attempt:0,scope:scope,outcome:.complete)}
            try journal.markDispatched(job:newJob,attempt:0)
            try journal.resolveInference(job:newJob,attempt:0,scope:scope,outcome:.complete)
            guard try journal.unresolvedCount()==1 else {fatalError("Incorrect persistent inference state")}
        }
        let restarted=try Journal(directory:root)
        guard let record=try restarted.inferenceScope(job:job,attempt:0) else {fatalError("Lost native scope on restart")}
        precondition(record.state == .uncertain && record.scope.identity == scope.identity)
        let foreign=InferenceScope(host:scope.host,endpointHash:scope.endpointHash,profileHash:scope.profileHash,
            managerEpoch:scope.managerEpoch,nativeEpoch:"native-two",canonicalModel:scope.canonicalModel,
            nativeModel:scope.nativeModel,sequence:scope.sequence,sampledAt:scope.sampledAt)
        refuses {try restarted.resolveInference(job:job,attempt:0,scope:foreign,outcome:.complete)}
        refuses {try restarted.resolveInference(job:job,attempt:0,scope:scope,outcome:.dispatched)}
        try restarted.resolveInference(job:job,attempt:0,scope:scope,outcome:.not_sent)
        refuses {try restarted.resolveInference(job:job,attempt:0,scope:scope,outcome:.not_sent)}
        guard try restarted.unresolvedCount()==0 else {fatalError("Incorrect persistent inference state")}
        guard try restarted.requestCount(job:job)==1 else {fatalError("Incorrect persistent inference state")}
        guard try restarted.inferenceScope(job:job,attempt:0)?.state == .not_sent else {fatalError("Incorrect persistent inference state")}
        let long=InferenceScope(host:scope.host,endpointHash:scope.endpointHash,profileHash:scope.profileHash,
            managerEpoch:scope.managerEpoch,nativeEpoch:scope.nativeEpoch,
            canonicalModel:String(repeating:"\"",count:1024),nativeModel:String(repeating:"\\",count:1024),
            sequence:UInt64(Int64.max),sampledAt:scope.sampledAt)
        let longBytes=try long.encoded()
        precondition(longBytes.count>4096 && longBytes.count<=InferenceScope.maximumBytes)
        precondition(tryIdentity(longBytes)==long.identity)
        let longState=root.appendingPathComponent("long-identities")
        do {
            let journal=try Journal(directory:longState)
            try journal.claim(job:job,attempt:0,model:long.canonicalModel,scope:long)
            try journal.markDispatched(job:job,attempt:0)
            try journal.resolveInference(job:job,attempt:0,scope:long,outcome:.complete)
        }
        do {
            let journal=try Journal(directory:longState)
            guard let restored=try journal.inferenceScope(job:job,attempt:0),
                  restored.scope.identity==long.identity,restored.scope.sequence==long.sequence else {fatalError("Escaped model identity or sequence lost on restart")}
        }
        let encoded=try scope.encoded()
        let text=String(decoding:encoded,as:UTF8.self)
        var wrongModel=try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
        wrongModel["canonicalModel"]="foreign/model"
        let wrongModelText=String(decoding:try JSONSerialization.data(withJSONObject:wrongModel),as:UTF8.self)
        let invalidPayloads=[
            text.dropLast()+",\"foreign_proof\":true}",
            text.dropLast()+",\"host\":\"fios-edge-a.lab\"}",
            text.replacingOccurrences(of:"\"sequence\":1",with:"\"sequence\":1.0"),
            text.replacingOccurrences(of:"\"sequence\":1",with:"\"sequence\":true"),
            wrongModelText,
            text+"\0"
        ]
        precondition(invalidPayloads.allSatisfy {$0 != text},"Corruption fixture did not alter its scope")
        let sqlPayloads=invalidPayloads.map { value in
            "UPDATE inference_scopes SET payload=CAST(x'"+Data(value.utf8).map {String(format:"%02x",$0)}.joined()+"' AS TEXT)"
        }
        let corruptions=sqlPayloads+[
            "UPDATE inference_scopes SET state='complete'",
            "DELETE FROM inference_scopes",
            "UPDATE inference SET model='foreign/model'"
        ]
        for (index,sql) in corruptions.enumerated() {
            let directory=root.appendingPathComponent("corrupt-\(index)")
            do {
                let journal=try Journal(directory:directory)
                try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
            }
            let file=directory.appendingPathComponent("state.sqlite")
            var db:OpaquePointer?
            guard sqlite3_open(file.path,&db)==SQLITE_OK else {throw JournalError.storage}
            let code=sqlite3_exec(db,sql,nil,nil,nil);sqlite3_close(db)
            guard code==SQLITE_OK else {throw JournalError.storage}
            let before=try Data(contentsOf:file)
            do {_=try Journal(directory:directory);fatalError("Corrupted native scope admitted \(index)")}
            catch JournalError.invalid {}
            guard try Data(contentsOf:file)==before else {fatalError("Rejected native scope was rewritten")}
        }
    }
    private static func tryIdentity(_ bytes:Data) -> [Data] {
        do {return try InferenceScope.decode(bytes).identity}
        catch {fatalError("Bounded exact model identity rejected")}
    }
}
