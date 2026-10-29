import Foundation
import Darwin

extension StoppedStateBackup {
    // Restore into a NEW private state directory only. No in-place rollback,
    // launchd/native action, enrollment, source deletion or task replay.
    public static func restore(directory:URL,expectedSHA256:String,destination:URL)throws->StateBackupReceipt {
        try restore(directory:directory,expectedSHA256:expectedSHA256,destination:destination,migrateSeven:false)
    }
    public static func migrateSeven(directory:URL,expectedSHA256:String,destination:URL)throws->StateBackupReceipt {
        try restore(directory:directory,expectedSHA256:expectedSHA256,destination:destination,migrateSeven:true)
    }
    private static func restore(directory:URL,expectedSHA256:String,destination:URL,migrateSeven:Bool)throws->StateBackupReceipt {
        let receipt=try verify(directory:directory,expectedSHA256:expectedSHA256,journalSchema:migrateSeven ? 7:8)
        guard destination.isFileURL else {throw JournalError.invalid}
        let parent=destination.deletingLastPathComponent()
        let sourcePath=directory.resolvingSymlinksInPath().standardizedFileURL.path
        let targetPath=parent.resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent).standardizedFileURL.path
        guard targetPath != sourcePath,!targetPath.hasPrefix(sourcePath+"/") else {throw JournalError.invalid}
        var info=stat()
        guard lstat(parent.path,&info)==0,info.st_mode&S_IFMT==S_IFDIR,info.st_uid==geteuid(),info.st_mode&0o077==0 else {throw JournalError.invalid}
        guard lstat(destination.path,&info) != 0,errno==ENOENT else {throw JournalError.conflict}
        let disk=try FileManager.default.attributesOfFileSystem(forPath:parent.path)
        guard let free=(disk[.systemFreeSize] as? NSNumber)?.int64Value,free>=receipt.bytes+(10<<30) else {throw JournalError.storage}
        let temporary=parent.appendingPathComponent(".fios-restore-"+UUID().uuidString.lowercased())
        guard mkdir(temporary.path,0o700)==0 else {throw JournalError.storage}
        defer {try? FileManager.default.removeItem(at:temporary)}
        var recovery=try serviceRecoveryPayload(directory:directory)==nil ? []:["service-recovery.json"]
        if try migrationHoldPayload(directory:directory) != nil {recovery.append("migration-hold.json")}
        for name in ["state.sqlite","artifacts","backup.json"]+recovery {
            try FileManager.default.copyItem(at:directory.appendingPathComponent(name),to:temporary.appendingPathComponent(name))
        }
        // Verify the copied tree, not just the previously observed source. A
        // changed/linked/extra file cannot become a published restoration.
        _=try verify(directory:temporary,expectedSHA256:expectedSHA256,journalSchema:migrateSeven ? 7:8)
        // Fresh working-state locks are not copied from a backup. Create them
        // only after verifying the private copy, so a stopped restored state
        // can be backed up again without first starting any controller/store.
        let lockPaths=[temporary.appendingPathComponent("manager.lock"),temporary.appendingPathComponent("supervisor.lock"),temporary.appendingPathComponent("artifacts/store.lock")]
        for path in lockPaths {
            let fd=open(path.path,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            guard fd>=0 else {throw JournalError.conflict}
            close(fd)
        }
        if migrateSeven {
            let hold=try JSONSerialization.data(withJSONObject:["version":1,"from_schema":7,"to_schema":8,"input_backup_sha256":expectedSHA256,"reason":"legacy_native_scope_unknown","admission":"maintenance"],options:[.sortedKeys])
            let path=temporary.appendingPathComponent("migration-hold.json")
            try hold.write(to:path,options:.withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
            try Journal.migrateSevenCopy(directory:temporary)
            recovery.append("migration-hold.json")
        }
        let artifactDirectory=temporary.appendingPathComponent("artifacts")
        let artifactNames=try FileManager.default.contentsOfDirectory(atPath:artifactDirectory.path)
        let files=(["state.sqlite","backup.json","manager.lock","supervisor.lock"]+recovery).map {temporary.appendingPathComponent($0)}+artifactNames.map {artifactDirectory.appendingPathComponent($0)}
        for file in files {
            let fd=open(file.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw JournalError.storage}
            let result=fsync(fd);close(fd)
            guard result==0 else {throw JournalError.storage}
        }
        let artifacts=open(artifactDirectory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard artifacts>=0 else {throw JournalError.storage};defer {close(artifacts)}
        guard fsync(artifacts)==0 else {throw JournalError.storage}
        let folder=open(temporary.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard folder>=0 else {throw JournalError.storage};defer {close(folder)}
        guard fsync(folder)==0,renamex_np(temporary.path,destination.path,UInt32(RENAME_EXCL))==0 else {throw JournalError.conflict}
        let outer=open(parent.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard outer>=0 else {throw JournalError.storage};defer {close(outer)}
        guard fsync(outer)==0 else {throw JournalError.storage}
        return receipt
    }
}
