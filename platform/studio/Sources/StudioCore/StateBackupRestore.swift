import Foundation
import Darwin

extension StoppedStateBackup {
    // Restore into a NEW private state directory only. No in-place rollback,
    // launchd/native action, enrollment, source deletion or task replay.
    public static func restore(directory:URL,expectedSHA256:String,destination:URL)throws->StateBackupReceipt {
        try restore(directory:directory,expectedSHA256:expectedSHA256,destination:destination,migrateFrom:nil)
    }
    public static func migrateSeven(directory:URL,expectedSHA256:String,destination:URL)throws->StateBackupReceipt {
        try restore(directory:directory,expectedSHA256:expectedSHA256,destination:destination,migrateFrom:7)
    }
    public static func migrateEight(directory:URL,expectedSHA256:String,destination:URL)throws->StateBackupReceipt {
        try restore(directory:directory,expectedSHA256:expectedSHA256,destination:destination,migrateFrom:8)
    }
    private static func restore(directory:URL,expectedSHA256:String,destination:URL,migrateFrom:Int?)throws->StateBackupReceipt {
        let receipt=try verify(directory:directory,expectedSHA256:expectedSHA256,journalSchema:migrateFrom ?? 9)
        guard destination.isFileURL else {throw JournalError.invalid}
        let parent=destination.deletingLastPathComponent()
        let sourcePath=directory.resolvingSymlinksInPath().standardizedFileURL.path
        let targetPath=parent.resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent).standardizedFileURL.path
        guard targetPath != sourcePath,!targetPath.hasPrefix(sourcePath+"/") else {throw JournalError.invalid}
        let outer=open(parent.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard outer>=0 else {throw JournalError.invalid};defer {close(outer)}
        var parentInfo=stat(),info=stat()
        guard fstat(outer,&parentInfo)==0,parentInfo.st_mode&S_IFMT==S_IFDIR,
              parentInfo.st_uid==geteuid(),parentInfo.st_mode&0o077==0 else {throw JournalError.invalid}
        guard lstat(destination.path,&info) != 0,errno==ENOENT else {throw JournalError.conflict}
        let disk=try FileManager.default.attributesOfFileSystem(forPath:parent.path)
        guard let free=(disk[.systemFreeSize] as? NSNumber)?.int64Value,free>=receipt.bytes+(10<<30) else {throw JournalError.storage}
        let temporary=parent.appendingPathComponent(".fios-restore-"+UUID().uuidString.lowercased())
        guard mkdir(temporary.path,0o700)==0 else {throw JournalError.storage}
        // Retain a failed private copy for diagnosis. Publication removes this
        // name by exclusive rename; no recursive cleanup follows uncertainty.
        var recovery=try serviceRecoveryPayload(directory:directory)==nil ? []:["service-recovery.json"]
        if try migrationHoldPayload(directory:directory) != nil {recovery.append("migration-hold.json")}
        let hasConfiguration=receipt.scope=="platform_journal_exports_and_configuration"
        for name in ["state.sqlite","artifacts","backup.json"]+recovery+(hasConfiguration ? ["configuration"]:[]) {
            try FileManager.default.copyItem(at:directory.appendingPathComponent(name),to:temporary.appendingPathComponent(name))
        }
        // Verify the copied tree, not just the previously observed source. A
        // changed/linked/extra file cannot become a published restoration.
        if migrateFrom == nil {
            _=try verifyCompatibility(directory:temporary,expectedSHA256:expectedSHA256)
        }else {
            _=try verify(directory:temporary,expectedSHA256:expectedSHA256,journalSchema:migrateFrom ?? 9)
        }
        // Fresh working-state locks are not copied from a backup. Create them
        // only after verifying the private copy, so a stopped restored state
        // can be backed up again without first starting any controller/store.
        let lockPaths=[temporary.appendingPathComponent("manager.lock"),temporary.appendingPathComponent("supervisor.lock"),temporary.appendingPathComponent("serving-custody.lock"),temporary.appendingPathComponent("artifacts/store.lock")]
        for path in lockPaths {
            let fd=open(path.path,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            guard fd>=0 else {throw JournalError.conflict}
            close(fd)
        }
        if let migrateFrom {
            if try migrationHoldPayload(directory:temporary)==nil {
                let hold=try JSONSerialization.data(withJSONObject:["version":1,"from_schema":migrateFrom,"to_schema":9,"input_backup_sha256":expectedSHA256,"reason":migrateFrom==7 ? "legacy_native_scope_unknown":"legacy_native_lineage_unknown","admission":"maintenance"],options:[.sortedKeys])
                let path=temporary.appendingPathComponent("migration-hold.json")
                try hold.write(to:path,options:.withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
                recovery.append("migration-hold.json")
            }
            if migrateFrom==7 {try Journal.migrateSevenCopy(directory:temporary)}
            else {try Journal.migrateEightCopy(directory:temporary)}
        }
        let artifactDirectory=temporary.appendingPathComponent("artifacts")
        let artifactNames=try FileManager.default.contentsOfDirectory(atPath:artifactDirectory.path)
        let files=(["state.sqlite","backup.json","manager.lock","supervisor.lock","serving-custody.lock"]+recovery).map {temporary.appendingPathComponent($0)}+artifactNames.map {artifactDirectory.appendingPathComponent($0)}
        for file in files {try syncRestoredFile(file)}
        if hasConfiguration {
            let config=temporary.appendingPathComponent("configuration")
            for name in try FileManager.default.contentsOfDirectory(atPath:config.path) {
                try syncRestoredFile(config.appendingPathComponent(name))
            }
            let fd=open(config.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw JournalError.storage}
            let result=fsync(fd);close(fd);guard result==0 else {throw JournalError.storage}
        }
        let artifacts=open(artifactDirectory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard artifacts>=0 else {throw JournalError.storage};defer {close(artifacts)}
        guard fsync(artifacts)==0 else {throw JournalError.storage}
        let folder=open(temporary.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard folder>=0 else {throw JournalError.storage};defer {close(folder)}
        guard fsync(folder)==0 else {throw JournalError.storage}
        // Publish and sync against the same retained destination parent.
        guard lstat(parent.path,&info)==0,info.st_dev==parentInfo.st_dev,info.st_ino==parentInfo.st_ino,
              info.st_mode==parentInfo.st_mode,info.st_uid==parentInfo.st_uid,
              renameatx_np(outer,temporary.lastPathComponent,outer,destination.lastPathComponent,UInt32(RENAME_EXCL))==0 else {throw JournalError.conflict}
        guard fsync(outer)==0 else {throw JournalError.storage}
        return receipt
    }
    // Validate the actual input to fsync; a previous tree verification is
    // not a reason to block opening a nonregular file in the private copy.
    static func syncRestoredFile(_ file:URL)throws {
        let fd=open(file.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard fd>=0 else {throw JournalError.storage};defer {close(fd)}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode&S_IFMT==S_IFREG,info.st_nlink==1,
              info.st_uid==geteuid(),info.st_mode&0o077==0 else {throw JournalError.invalid}
        guard fsync(fd)==0 else {throw JournalError.storage}
    }
}
