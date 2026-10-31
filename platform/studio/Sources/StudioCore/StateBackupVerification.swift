import Foundation
import Darwin
import CryptoKit

extension StoppedStateBackup {
    public static func verify(directory:URL,expectedSHA256:String)throws->StateBackupReceipt {
        try verify(directory:directory,expectedSHA256:expectedSHA256,journalSchema:8)
    }
    static func verify(directory:URL,expectedSHA256:String,journalSchema:Int)throws->StateBackupReceipt {
        guard [7,8].contains(journalSchema) else {throw JournalError.invalid}
        struct Manifest:Decodable {
            let version:Int;let scope:String;let host_hash:String;let owner_uid:UInt32;let journal_schema:Int;let journal_application_id:String
            let journal_bytes:Int64;let journal_sha256:String;let artifact_index_sha256:String;let artifact_files:[ArtifactBackupFile]
            let service_recovery_bytes:Int64?;let service_recovery_sha256:String?
            let migration_hold_bytes:Int64?;let migration_hold_sha256:String?
        }
        func digest(_ value:String)->Bool {value.utf8.count==64 && value.utf8.allSatisfy {(48...57).contains($0)||(97...102).contains($0)}}
        func privateDirectory(_ url:URL)throws {
            var info=stat()
            guard lstat(url.path,&info)==0,info.st_mode&S_IFMT==S_IFDIR,info.st_uid==geteuid(),info.st_mode&0o077==0 else {throw JournalError.invalid}
        }
        let deadline=ProcessInfo.processInfo.systemUptime+30
        func hash(_ url:URL,maximum:Int64,collect:Bool=false)throws->(String,Int64,Data) {
            let fd=open(url.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw JournalError.invalid};defer {close(fd)}
            var info=stat()
            guard fstat(fd,&info)==0,info.st_mode&S_IFMT==S_IFREG,info.st_nlink==1,info.st_uid==geteuid(),info.st_mode&0o077==0,info.st_size>=0,info.st_size<=maximum else {throw JournalError.invalid}
            var hash=SHA256(),count:Int64=0,data=Data(),buffer=[UInt8](repeating:0,count:65536)
            while true {
                guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
                let size=Darwin.read(fd,&buffer,buffer.count)
                if size<0 && errno==EINTR {continue}
                guard size>=0,count+Int64(max(0,size))<=maximum else {throw JournalError.invalid}
                if size==0 {break}
                let chunk=Data(buffer.prefix(size));hash.update(data:chunk)
                if collect {data.append(chunk)} else if data.count<100 {data.append(chunk.prefix(100-data.count))}
                count+=Int64(size)
            }
            guard count==info.st_size else {throw JournalError.invalid}
            return (hash.finalize().map {String(format:"%02x",$0)}.joined(),count,data)
        }
        guard directory.isFileURL,digest(expectedSHA256) else {throw JournalError.invalid}
        try privateDirectory(directory)
        let (receiptHash,_,data)=try hash(directory.appendingPathComponent("backup.json"),maximum:65536,collect:true)
        guard receiptHash==expectedSHA256 else {throw JournalError.invalid}
        try StrictJSON.validate(data,maximum:65536)
        guard let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any],let version=WireScalar.integer(raw["version"],maximum:3),(1...3).contains(version) else {throw JournalError.invalid}
        guard journalSchema != 7 || version<=2 else {throw JournalError.invalid}
        let extra=version>=2 ? ["service_recovery_bytes","service_recovery_sha256"]+(version==3 ? ["migration_hold_bytes","migration_hold_sha256"]:[]):[]
        guard Set(raw.keys)==Set(["version","scope","host_hash","owner_uid","journal_schema","journal_application_id","journal_bytes","journal_sha256","artifact_index_sha256","artifact_files"]+extra),
              let files=raw["artifact_files"] as? [[String:Any]],files.allSatisfy({Set($0.keys)==Set(["path","bytes","sha256"])}) else {throw JournalError.invalid}
        let manifest=try JSONDecoder().decode(Manifest.self,from:data)
        let scope=version==3 ? "platform_journal_exports_and_migration_hold":version==2 ? "platform_journal_exports_and_service_recovery":"platform_journal_and_exports"
        guard manifest.scope==scope,manifest.owner_uid==geteuid(),manifest.host_hash == (try StoppedPlatformState.hostHash()),manifest.journal_schema==journalSchema,manifest.journal_application_id=="FIS9",(100...(64<<20)).contains(manifest.journal_bytes),digest(manifest.journal_sha256),digest(manifest.artifact_index_sha256),manifest.artifact_files.count<=256 else {throw JournalError.invalid}
        let hasRecovery=version==2 || (version==3 && !(raw["service_recovery_bytes"] is NSNull))
        let additional=(hasRecovery ? ["service-recovery.json"]:[])+(version==3 ? ["migration-hold.json"]:[])
        guard Set(try FileManager.default.contentsOfDirectory(atPath:directory.path))==Set(["backup.json","state.sqlite","artifacts"]+additional) else {throw JournalError.invalid}
        var recoveryBytes:Int64=0
        if hasRecovery {
            guard let declared=WireScalar.integer(raw["service_recovery_bytes"],maximum:4096),declared>0,
                  let expected=manifest.service_recovery_sha256,digest(expected),
                  let bytes=try serviceRecoveryPayload(directory:directory),Int64(bytes.count)==declared,
                  SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined()==expected else {throw JournalError.invalid}
            recoveryBytes=declared
        }
        var holdBytes:Int64=0
        if version==3 {
            if !hasRecovery {guard raw["service_recovery_sha256"] is NSNull else {throw JournalError.invalid}}
            guard let declared=WireScalar.integer(raw["migration_hold_bytes"],maximum:4096),declared>0,
                  let expected=manifest.migration_hold_sha256,digest(expected),
                  let bytes=try migrationHoldPayload(directory:directory),Int64(bytes.count)==declared,
                  SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined()==expected else {throw JournalError.invalid}
            holdBytes=declared
        }
        let artifacts=directory.appendingPathComponent("artifacts")
        try privateDirectory(artifacts)
        var names=Set(["index.json"]),total:Int64=0
        for file in manifest.artifact_files {
            guard file.path.hasSuffix(".blob"),UUID(uuidString:String(file.path.dropLast(5)))?.uuidString.lowercased()==String(file.path.dropLast(5)),(0...16<<20).contains(file.bytes),digest(file.sha256),names.insert(file.path).inserted else {throw JournalError.invalid}
            total+=file.bytes;guard total<=4<<30 else {throw JournalError.invalid}
            let (actual,length,_)=try hash(artifacts.appendingPathComponent(file.path),maximum:16<<20)
            guard actual==file.sha256,length==file.bytes else {throw JournalError.invalid}
        }
        guard Set(try FileManager.default.contentsOfDirectory(atPath:artifacts.path))==names else {throw JournalError.invalid}
        let (index,_,indexData)=try hash(artifacts.appendingPathComponent("index.json"),maximum:1<<20,collect:true)
        guard index==manifest.artifact_index_sha256 else {throw JournalError.invalid}
        struct IndexVersion:Decodable {let version:Int}
        try StrictJSON.validate(indexData,maximum:1<<20)
        guard let object=try JSONSerialization.jsonObject(with:indexData) as? [String:Any],Set(object.keys)==Set(["version","records"]),
              let records=object["records"] as? [[String:Any]],records.count<=256,
              records.allSatisfy({Set($0.keys)==Set(["id","job","ownerHash","created","bytes","sha256","state"])}) else {throw JournalError.invalid}
        guard try JSONDecoder().decode(IndexVersion.self,from:indexData).version==1 else {throw JournalError.invalid}
        let (journal,length,header)=try hash(directory.appendingPathComponent("state.sqlite"),maximum:64<<20)
        guard journal==manifest.journal_sha256,length==manifest.journal_bytes,header.count==100,
              Array(header.prefix(16))==Array("SQLite format 3\0".utf8),Array(header[60..<64])==[0,0,0,UInt8(journalSchema)],Array(header[68..<72])==[0x46,0x49,0x53,0x39] else {throw JournalError.invalid}
        return StateBackupReceipt(scope:scope,bytes:length+total+recoveryBytes+holdBytes,artifacts:manifest.artifact_files.count,sha256:receiptHash)
    }
}
