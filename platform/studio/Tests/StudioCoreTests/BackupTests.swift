import Foundation
import CSQLite
import CryptoKit
import Darwin

func runBackupTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let state=root.appendingPathComponent("state"),backup=root.appendingPathComponent("backup.sqlite")
    let job=UUID().uuidString.lowercased()
    do {
        let journal=try Journal(directory:state)
        try journal.claim(job:job,attempt:0,model:"fixture/model")
        var refused=false
        do {_=try StoppedJournalBackup.create(directory:state,destination:backup)} catch {refused=true}
        guard refused else {fatalError("Live single-writer database was backed up as stopped")}
    }
    do {
        let supervisor=open(state.appendingPathComponent("supervisor.lock").path,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard supervisor>=0,flock(supervisor,LOCK_EX|LOCK_NB)==0 else {throw JournalError.storage}
        defer {flock(supervisor,LOCK_UN);close(supervisor)}
        do {_=try StoppedJournalBackup.create(directory:state,destination:backup);fatalError("Backup accepted a live supervisor capable of restarting the manager")}catch JournalError.locked {}
    }
    do {
        let custody=try PrivateWriterLock(directory:state,kind:.servingCustody)
        defer {custody.release()}
        var refused=false
        do {_=try StoppedJournalBackup.create(directory:state,destination:backup)}catch JournalError.locked {refused=true}
        guard refused else {
            FileHandle.standardError.write(Data("CUSTODY_BACKUP_FENCE_MISSING\n".utf8));throw RuntimeError.invalid
        }
    }
    do {
        let stopped=try StoppedPlatformState(directory:state)
        let contender=open(state.appendingPathComponent("supervisor.lock").path,O_RDWR|O_NOFOLLOW|O_CLOEXEC)
        guard contender>=0 else {throw JournalError.storage}
        defer {close(contender)}
        try withExtendedLifetime(stopped) {
            guard flock(contender,LOCK_EX|LOCK_NB) != 0 else {fatalError("Supervisor could restart while offline writer fence was held")}
            do {_=try Journal(directory:state);fatalError("Manager opened state during offline writer fence")}catch JournalError.locked {}
            do {_=try PrivateWriterLock(directory:state,kind:.servingCustody);fatalError("Custody module opened during offline writer fence")}catch ControlError.busy {}
        }
    }
    do {
        let stopped=try StoppedPlatformState(directory:state)
        let database=state.appendingPathComponent("state.sqlite"),original=root.appendingPathComponent("original.sqlite")
        try FileManager.default.moveItem(at:database,to:original)
        defer {try? FileManager.default.removeItem(at:database);try? FileManager.default.moveItem(at:original,to:database)}
        try FileManager.default.copyItem(at:original,to:database)
        do {_=try StoppedJournalBackup.create(directory:state,destination:backup,stopped:stopped)
            fatalError("Stopped proof accepted a different database with identical contents")
        } catch JournalError.invalid {}
        do {_=try JournalSchemaSnapshot(source:state,stopped:stopped)
            fatalError("Snapshot accepted a different database under stopped proof")
        } catch JournalError.invalid {}
        guard !FileManager.default.fileExists(atPath:backup.path) else {fatalError("Mismatched stopped proof left an output")}
    }
    let managerLock=state.appendingPathComponent("manager.lock").path
    guard chmod(managerLock,0o644)==0 else {throw JournalError.storage}
    do {
        defer {_=chmod(managerLock,0o600)}
        do {_=try StoppedPlatformState(directory:state);fatalError("Invalid manager lock metadata accepted")}
        catch JournalError.invalid {}
        for name in ["supervisor.lock","serving-custody.lock"] {
            let contender=open(state.appendingPathComponent(name).path,O_RDWR|O_NOFOLLOW|O_CLOEXEC)
            guard contender>=0 else {throw JournalError.storage}
            defer {close(contender)}
            guard flock(contender,LOCK_EX|LOCK_NB)==0 else {fatalError("Stopped-state refusal retained a writer fence")}
        }
    }
    let receipt=try StoppedJournalBackup.create(directory:state,destination:backup)
    let savedBytes=try Data(contentsOf:backup)
    let independentlyHashed=SHA256.hash(data:savedBytes).map {String(format:"%02x",$0)}.joined()
    guard receipt.schema==9,receipt.sha256==independentlyHashed,receipt.bytes==savedBytes.count,
          receipt.bytes>100 else {fatalError("Stopped journal receipt did not match published bytes")}
    let copy=root.appendingPathComponent("restored")
    try FileManager.default.createDirectory(at:copy,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    try FileManager.default.copyItem(at:backup,to:copy.appendingPathComponent("state.sqlite"))
    do {
        let restored=try Journal(directory:copy)
        guard try restored.unresolvedCount()==1,try restored.uncertainCount()==1 else {fatalError("Backup lost independent native ownership")}
    }
    var overwritten=false
    do {_=try StoppedJournalBackup.create(directory:state,destination:backup);overwritten=true} catch {}
    guard !overwritten else {fatalError("Backup overwrote an existing path")}
    let foreign=root.appendingPathComponent("not-platform")
    try FileManager.default.createDirectory(at:foreign,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    try Data(repeating:0,count:100).write(to:foreign.appendingPathComponent("state.sqlite"))
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:foreign.appendingPathComponent("state.sqlite").path)
    do {_=try StoppedJournalBackup.create(directory:foreign,destination:root.appendingPathComponent("bad.sqlite"));fatalError("Unmarked database accepted")} catch JournalError.invalid {}
    let fifo=root.appendingPathComponent("fifo-state")
    try FileManager.default.createDirectory(at:fifo,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    guard mkfifo(fifo.appendingPathComponent("state.sqlite").path,0o600)==0 else {throw JournalError.storage}
    do {_=try StoppedPlatformState(directory:fifo);fatalError("Nonregular state accepted as SQLite")} catch JournalError.invalid {}
    for directory in [foreign,fifo] {
        for name in ["supervisor.lock","serving-custody.lock","manager.lock"] {
            guard !FileManager.default.fileExists(atPath:directory.appendingPathComponent(name).path) else {
                fatalError("Stopped-state refusal left lock files in unrelated directory")
            }
        }
    }
    let future=root.appendingPathComponent("future")
    try FileManager.default.createDirectory(at:future,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let futureFile=future.appendingPathComponent("state.sqlite")
    try FileManager.default.copyItem(at:backup,to:futureFile)
    var database:OpaquePointer?
    guard sqlite3_open_v2(futureFile.path,&database,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK else {throw JournalError.storage}
    let changed=sqlite3_exec(database,"PRAGMA user_version=10",nil,nil,nil)
    sqlite3_close(database)
    guard changed==SQLITE_OK else {throw JournalError.storage}
    try AtomicState.write(Data(),to:future.appendingPathComponent("manager.lock"))
    let failedJournal=root.appendingPathComponent("rejected-schema-retained.sqlite")
    do {_=try StoppedJournalBackup.create(directory:future,destination:failedJournal);fatalError("Future schema backup accepted")}catch JournalError.invalid {}
    guard FileManager.default.fileExists(atPath:failedJournal.path) else {fatalError("Rejected journal backup discarded diagnostic output")}
    let before=try Data(contentsOf:futureFile)
    do {_=try Journal(directory:future);fatalError("Future ownership schema silently downgraded")} catch JournalError.invalid {}
    guard try Data(contentsOf:futureFile)==before else {fatalError("Rejected future journal was mutated")}
    let payload=Data("EXPLICIT_EXPORT_FIXTURE".utf8),owner=String(repeating:"a",count:64)
    var artifact=""
    do {
        let store=try ArtifactStore(directory:state.appendingPathComponent("artifacts"),availableBytes:{100<<30})
        artifact=try store.publish(job:job,ownerHash:owner,data:payload,now:1000)
        do {_=try StoppedArtifactBackup.create(directory:state,destination:root.appendingPathComponent("live-exports"));fatalError("Active artifact writer was snapshotted")} catch JournalError.locked {}
    }
    let exports=root.appendingPathComponent("exports-copy")
    let indexBefore=try Data(contentsOf:state.appendingPathComponent("artifacts/index.json"))
    let saved=try StoppedArtifactBackup.create(directory:state,destination:exports)
    guard saved.artifacts==1,saved.bytes==payload.count,saved.indexSHA256.count==64,
          try Data(contentsOf:state.appendingPathComponent("artifacts/index.json"))==indexBefore else {fatalError("Export snapshot mutated source or lost data")}
    do {
        let restored=try ArtifactStore(directory:exports,availableBytes:{100<<30})
        var stream=try restored.download(id:artifact,ownerHash:owner,now:1001)
        _=try stream.next(now:1001)
        guard case .chunk(0,let encoded)=try stream.next(now:1001),Data(base64Encoded:encoded)==payload else {fatalError("Restored export differs")}
    }
    let indexPath=state.appendingPathComponent("artifacts/index.json")
    var unknown=try JSONSerialization.jsonObject(with:indexBefore) as! [String:Any]
    unknown["unreviewed_ownership"]=true
    try JSONSerialization.data(withJSONObject:unknown).write(to:indexPath)
    do {_=try ArtifactStore(directory:state.appendingPathComponent("artifacts"),availableBytes:{100<<30});fatalError("Unknown artifact ownership fields ignored")} catch ArtifactError.invalid {}
    try indexBefore.write(to:indexPath)
    do {
        let savedIndex=root.appendingPathComponent("original-index")
        try FileManager.default.moveItem(at:indexPath,to:savedIndex)
        defer {try? FileManager.default.removeItem(at:indexPath);try? FileManager.default.moveItem(at:savedIndex,to:indexPath)}
        guard mkfifo(indexPath.path,0o600)==0 else {throw JournalError.storage}
        let destination=root.appendingPathComponent("nonregular-index")
        do {_=try StoppedStateBackup.create(directory:state,destination:destination);fatalError("FIFO index accepted as stopped artifact metadata")}
        catch JournalError.invalid {}
        guard !FileManager.default.fileExists(atPath:destination.appendingPathComponent("backup.json").path) else {
            fatalError("Invalid artifact index published a sealed backup")
        }
    }
    let sourceBlob=state.appendingPathComponent("artifacts/"+artifact+".blob")
    let wrongPayload=Data(repeating:0,count:payload.count)
    try wrongPayload.write(to:sourceBlob)
    let failedExports=root.appendingPathComponent("rejected-export-retained")
    do {_=try StoppedArtifactBackup.create(directory:state,destination:failedExports);fatalError("Mismatched export hash accepted")}catch JournalError.invalid {}
    guard try Data(contentsOf:failedExports.appendingPathComponent(artifact+".blob"))==wrongPayload,
          try Data(contentsOf:sourceBlob)==wrongPayload else {fatalError("Failed export snapshot discarded output or changed source")}
    try payload.write(to:sourceBlob)
    let link=root.appendingPathComponent("external-link")
    try FileManager.default.linkItem(at:state.appendingPathComponent("artifacts/"+artifact+".blob"),to:link)
    do {_=try StoppedArtifactBackup.create(directory:state,destination:root.appendingPathComponent("linked-copy"));fatalError("Linked export accepted")} catch JournalError.invalid {}
    try FileManager.default.removeItem(at:link)
    try AtomicState.write(Data("VOLATILE_CUSTODY_FIXTURE".utf8),to:state.appendingPathComponent("serving-custody.json"))
    let bundle=root.appendingPathComponent("state-bundle")
    let bundleReceipt=try StoppedStateBackup.create(directory:state,destination:bundle)
    guard bundleReceipt.artifacts==1,bundleReceipt.sha256.count==64 else {fatalError("No full state snapshot receipt")}
    do {_=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:bundleReceipt.sha256,destination:bundle.appendingPathComponent("nested"));fatalError("Restore modified its source archive")} catch JournalError.invalid {}
    let alias=root.appendingPathComponent("state-alias")
    try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:state)
    do {_=try StoppedStateBackup.create(directory:state,destination:alias.appendingPathComponent("artifacts/nested"));fatalError("Snapshot entered source exports through an alias")} catch JournalError.invalid {}
    let checked=try StoppedStateBackup.verify(directory:bundle,expectedSHA256:bundleReceipt.sha256)
    guard checked.bytes==bundleReceipt.bytes,checked.artifacts==1 else {fatalError("Snapshot verification differs")}
    let sealedEntries=try FileManager.default.contentsOfDirectory(atPath:bundle.path).sorted()
    let compatible=try StoppedStateBackup.verifyCompatibility(directory:bundle,expectedSHA256:bundleReceipt.sha256)
    guard compatible.bytes==checked.bytes,compatible.artifacts==checked.artifacts,
          try FileManager.default.contentsOfDirectory(atPath:bundle.path).sorted()==sealedEntries else {
        fatalError("Compatibility preflight changed the sealed backup namespace")
    }
    do {_=try StoppedStateBackup.verify(directory:bundle,expectedSHA256:String(repeating:"0",count:64));fatalError("Unreviewed snapshot accepted")} catch JournalError.invalid {}
    let corrupt=root.appendingPathComponent("corrupt-bundle")
    try FileManager.default.copyItem(at:bundle,to:corrupt)
    try Data("changed export".utf8).write(to:corrupt.appendingPathComponent("artifacts/"+artifact+".blob"))
    do {_=try StoppedStateBackup.verify(directory:corrupt,expectedSHA256:bundleReceipt.sha256);fatalError("Changed export verified")} catch JournalError.invalid {}
    let nonregularBundle=root.appendingPathComponent("fifo-bundle")
    try FileManager.default.copyItem(at:bundle,to:nonregularBundle)
    let nonregularBlob=nonregularBundle.appendingPathComponent("artifacts/"+artifact+".blob")
    try FileManager.default.removeItem(at:nonregularBlob)
    guard mkfifo(nonregularBlob.path,0o600)==0 else {throw JournalError.storage}
    let unpublished=root.appendingPathComponent("fifo-restore")
    do {_=try StoppedStateBackup.restore(directory:nonregularBundle,expectedSHA256:bundleReceipt.sha256,destination:unpublished)
        fatalError("Nonregular backup artifact restored")
    } catch JournalError.invalid {}
    var refusedBlob=stat()
    guard lstat(nonregularBlob.path,&refusedBlob)==0,refusedBlob.st_mode&S_IFMT==S_IFIFO,
          !FileManager.default.fileExists(atPath:unpublished.path) else {fatalError("Refused backup was mutated or published")}
    do {
        let journalBytes=try Data(contentsOf:bundle.appendingPathComponent("state.sqlite"))
        let expected=SHA256.hash(data:journalBytes).map {String(format:"%02x",$0)}.joined()
        do {_=try JournalSchemaSnapshot(source:bundle,sealedJournalSHA256:String(repeating:"0",count:64))
            fatalError("Compatibility snapshot accepted unauthenticated journal bytes")
        } catch JournalError.invalid {}
        let wal=bundle.appendingPathComponent("state.sqlite-wal")
        let marker=Data("not sealed journal data".utf8)
        try marker.write(to:wal)
        defer {try? FileManager.default.removeItem(at:wal)}
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:wal.path)
        let sealed=try JournalSchemaSnapshot(source:bundle,sealedJournalSHA256:expected)
        guard try Data(contentsOf:sealed.directory.appendingPathComponent("state.sqlite"))==journalBytes,
              !FileManager.default.fileExists(atPath:sealed.directory.appendingPathComponent("state.sqlite-wal").path),
              try Data(contentsOf:wal)==marker else {fatalError("Sealed compatibility snapshot imported an unreviewed sidecar")}
    }
    let foreignBundle=root.appendingPathComponent("foreign-bundle")
    try FileManager.default.copyItem(at:bundle,to:foreignBundle)
    let manifestPath=foreignBundle.appendingPathComponent("backup.json")
    var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:manifestPath)) as! [String:Any]
    let localHost=manifest["host_hash"]!
    for field in ["host_hash","owner_uid"] {
        manifest["host_hash"]=localHost
        manifest["owner_uid"]=Int(geteuid())
        if field=="host_hash" {manifest[field]=String(repeating:"0",count:64)} else {manifest[field]=Int(geteuid())+1}
        let bytes=try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
        try bytes.write(to:manifestPath)
        let hash=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        do {_=try StoppedStateBackup.verify(directory:foreignBundle,expectedSHA256:hash);fatalError("Foreign host/user snapshot was adopted")} catch JournalError.invalid {}
    }
    let restoredState=root.appendingPathComponent("restored-state")
    _=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:bundleReceipt.sha256,destination:restoredState)
    var custodyLock=stat()
    guard lstat(restoredState.appendingPathComponent("serving-custody.lock").path,&custodyLock)==0,
          custodyLock.st_mode&S_IFMT==S_IFREG,custodyLock.st_mode&0o7777==0o600,
          !FileManager.default.fileExists(atPath:restoredState.appendingPathComponent("serving-custody.json").path) else {fatalError("Restore copied a custody descriptor or omitted its fresh writer fence")}
    // A published working directory has fresh local lock identities. The
    // original receipt still identifies its sealed input, not this namespace.
    do {_=try StoppedStateBackup.verify(directory:restoredState,expectedSHA256:bundleReceipt.sha256);fatalError("Working state was accepted as a sealed backup")}
    catch JournalError.invalid {}
    let rebundled=root.appendingPathComponent("restored-before-start-backup")
    let rebackup=try StoppedStateBackup.create(directory:restoredState,destination:rebundled)
    _=try StoppedStateBackup.verify(directory:rebundled,expectedSHA256:rebackup.sha256)
    do {_=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:bundleReceipt.sha256,destination:state);fatalError("In-place restoration overwrote live state") } catch JournalError.conflict {}
    do {
        let restoredJournal=try Journal(directory:restoredState)
        let restoredExports=try ArtifactStore(directory:restoredState.appendingPathComponent("artifacts"),availableBytes:{100<<30})
        guard try restoredJournal.unresolvedCount()==1,try restoredJournal.uncertainCount()==1 else {fatalError("Bundle erased native uncertainty")}
        var stream=try restoredExports.download(id:artifact,ownerHash:owner,now:1001)
        _=try stream.next(now:1001)
        guard case .chunk(0,let encoded)=try stream.next(now:1001),Data(base64Encoded:encoded)==payload else {fatalError("Bundle lost explicit export")}
    }
    let configuration=root.appendingPathComponent("configuration-source")
    try FileManager.default.createDirectory(at:configuration,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let policy=Data("opaque enrollment reference; not authority".utf8)
    try AtomicState.write(policy,to:configuration.appendingPathComponent("runtime-enrollment.json"))
    try AtomicState.write(Data(),to:configuration.appendingPathComponent("session-enrollment.json"))
    try AtomicState.write(Data("unrelated".utf8),to:configuration.appendingPathComponent("unrelated.json"))
    try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:configuration.appendingPathComponent("runtime-enrollment.json").path)
    let configured=root.appendingPathComponent("configured-backup")
    let configuredReceipt=try StoppedStateBackup.create(directory:state,destination:configured,configuration:configuration)
    guard configuredReceipt.scope=="platform_journal_exports_and_configuration" else {fatalError("Missing configuration scope")}
    _=try StoppedStateBackup.verify(directory:configured,expectedSHA256:configuredReceipt.sha256)
    let configurationManifest=try JSONDecoder().decode(ConfigurationBackup.Manifest.self,from:Data(contentsOf:configured.appendingPathComponent("configuration/manifest.json")))
    guard configurationManifest.version==2,configurationManifest.files.count==6,configurationManifest.files[0].originalMode==0o644,
          configurationManifest.files[0].originalGID==getegid(),configurationManifest.files[1].originalGID==getegid(),
          configurationManifest.files[2].originalGID==nil,
          configurationManifest.files[1].bytes==0,configurationManifest.files[2].bytes==nil else {fatalError("Configuration original metadata/absence lost")}

    // Old v1 snapshots retain unknown group; v2 must retain the observed group.
    let legacy=root.appendingPathComponent("legacy-configuration")
    try FileManager.default.copyItem(at:configured.appendingPathComponent("configuration"),to:legacy)
    let legacyManifest=legacy.appendingPathComponent("manifest.json")
    var legacyRaw=try JSONSerialization.jsonObject(with:Data(contentsOf:legacyManifest)) as! [String:Any]
    legacyRaw["version"]=1
    legacyRaw["files"]=(legacyRaw["files"] as! [[String:Any]]).map {row in var value=row;value.removeValue(forKey:"originalGID");return value}
    let legacyData=try JSONSerialization.data(withJSONObject:legacyRaw)
    try AtomicState.write(legacyData,to:legacyManifest)
    _=try ConfigurationBackup.verify(directory:legacy,expected:ConfigurationBackup.digest(legacyData))
    legacyRaw["version"]=2
    let missingGroup=try JSONSerialization.data(withJSONObject:legacyRaw)
    try AtomicState.write(missingGroup,to:legacyManifest)
    do {_=try ConfigurationBackup.verify(directory:legacy,expected:ConfigurationBackup.digest(missingGroup));fatalError("v2 lost original group")}
    catch JournalError.invalid {}

    let configuredRestore=root.appendingPathComponent("configured-restore")
    _=try StoppedStateBackup.restore(directory:configured,expectedSHA256:configuredReceipt.sha256,destination:configuredRestore)
    let restoredConfiguration=configuredRestore.appendingPathComponent("configuration")
    guard try Data(contentsOf:restoredConfiguration.appendingPathComponent("runtime-enrollment.json"))==policy,
          try Data(contentsOf:restoredConfiguration.appendingPathComponent("session-enrollment.json")).isEmpty,
          !FileManager.default.fileExists(atPath:restoredConfiguration.appendingPathComponent("python-enrollment.json").path),
          try Data(contentsOf:configuration.appendingPathComponent("unrelated.json"))==Data("unrelated".utf8) else {fatalError("Configuration bytes/absence changed")}
    var stagedInfo=stat()
    guard lstat(restoredConfiguration.appendingPathComponent("runtime-enrollment.json").path,&stagedInfo)==0,
          stagedInfo.st_uid==geteuid(),stagedInfo.st_mode&0o7777==0o600 else {fatalError("Configuration restoration not private")}
    do {_=try RootPolicyFile.read(path:restoredConfiguration.appendingPathComponent("runtime-enrollment.json").path,maximum:65536);fatalError("Private restoration granted enrollment")}catch ControlError.unauthorized {}
    do {
        let journal=try Journal(directory:configuredRestore)
        guard try journal.uncertainCount()==1 else {fatalError("Configuration restore cleared native uncertainty")}
    }
    let configRebackup=root.appendingPathComponent("configured-restored-before-start-backup")
    let configRebackupReceipt=try StoppedStateBackup.create(directory:configuredRestore,destination:configRebackup,configuration:restoredConfiguration)
    _=try StoppedStateBackup.verify(directory:configRebackup,expectedSHA256:configRebackupReceipt.sha256)
    // Recovery and migration hold remain opaque and independent of the
    // configuration's missing enrollments, for all four presence combinations.
    for mask in 1...3 {
        let recovery=state.appendingPathComponent("service-recovery.json"),hold=state.appendingPathComponent("migration-hold.json")
        if mask&1 != 0 {try AtomicState.write(Data("retained service uncertainty".utf8),to:recovery)}
        if mask&2 != 0 {try AtomicState.write(Data("retained migration hold".utf8),to:hold)}
        let bundle=root.appendingPathComponent("configuration-recovery-\(mask)")
        let receipt=try StoppedStateBackup.create(directory:state,destination:bundle,configuration:configuration)
        _=try StoppedStateBackup.verify(directory:bundle,expectedSHA256:receipt.sha256)
        let restored=root.appendingPathComponent("configuration-recovery-restored-\(mask)")
        _=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:receipt.sha256,destination:restored)
        if mask&1 != 0 {
            guard try Data(contentsOf:restored.appendingPathComponent("service-recovery.json"))==Data(contentsOf:recovery) else {fatalError("Configuration snapshot lost recovery uncertainty")}
            try FileManager.default.removeItem(at:recovery)
        }
        if mask&2 != 0 {
            guard try Data(contentsOf:restored.appendingPathComponent("migration-hold.json"))==Data(contentsOf:hold) else {fatalError("Configuration snapshot lost migration hold")}
            try FileManager.default.removeItem(at:hold)
        }
    }
    let changedConfiguration=root.appendingPathComponent("changed-configuration-backup")
    try FileManager.default.copyItem(at:configured,to:changedConfiguration)
    try policy.dropLast().write(to:changedConfiguration.appendingPathComponent("configuration/runtime-enrollment.json"))
    do {_=try StoppedStateBackup.verify(directory:changedConfiguration,expectedSHA256:configuredReceipt.sha256);fatalError("Changed configuration verified")}catch JournalError.invalid {}
    let failedBundle=root.appendingPathComponent("failed-backup-retained")
    try Data("not an artifact index".utf8).write(to:indexPath)
    do {_=try StoppedStateBackup.create(directory:state,destination:failedBundle);fatalError("Malformed artifact index accepted")}catch {}
    guard FileManager.default.fileExists(atPath:failedBundle.appendingPathComponent("state.sqlite").path),
          !FileManager.default.fileExists(atPath:failedBundle.appendingPathComponent("backup.json").path) else {fatalError("Failed backup evidence removed or sealed")}
    try indexBefore.write(to:indexPath)
    try runBackupDecisionCompatibilityTests(root:root)
    print("PASS: bounded configuration bytes and absences privately restored without enrollment; independent uncertainty and failed partial backup retained")
    print("PASS: supervisor+custody+manager-fenced stopped-only bounded platform-marked SQLite backup, immutable receipt/no overwrite and independent uncertainty preserved on restore; no Fios database access")
}

private func runBackupDecisionCompatibilityTests(root:URL)throws {
    let state=root.appendingPathComponent("future-decision"),bundle=root.appendingPathComponent("future-decision-backup"),target=root.appendingPathComponent("future-decision-restored")
    let job=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:String(repeating:"c",count:32),canonicalModel:"fixture/model",nativeModel:"fixture/model",sequence:1,sampledAt:10000)
    do {
        let journal=try Journal(directory:state)
        try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
        try journal.markDispatched(job:job,attempt:0)
        _=try ArtifactStore(directory:state.appendingPathComponent("artifacts"))
    }
    var writer:OpaquePointer?
    guard sqlite3_open_v2(state.appendingPathComponent("state.sqlite").path,&writer,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let writer else {throw JournalError.storage}
    let status=sqlite3_exec(writer,"INSERT INTO native_lineages(job,attempt,payload) VALUES('\(job)',0,'{\"version\":99}')",nil,nil,nil)
    guard sqlite3_close(writer)==SQLITE_OK,status==SQLITE_OK else {throw JournalError.storage}
    let receipt=try StoppedStateBackup.create(directory:state,destination:bundle)
    _=try StoppedStateBackup.verify(directory:bundle,expectedSHA256:receipt.sha256)
    let databaseBefore=try Data(contentsOf:bundle.appendingPathComponent("state.sqlite")),namesBefore=try FileManager.default.contentsOfDirectory(atPath:bundle.path).sorted()
    do {_=try StoppedStateBackup.verifyCompatibility(directory:bundle,expectedSHA256:receipt.sha256);fatalError("Byte-valid future decision became compatible")}
    catch JournalError.invalid {}
    do {_=try StoppedStateBackup.restore(directory:bundle,expectedSHA256:receipt.sha256,destination:target);fatalError("Unsupported journal decision was published for restoration")}
    catch JournalError.invalid {}
    guard !FileManager.default.fileExists(atPath:target.path),
          try Data(contentsOf:bundle.appendingPathComponent("state.sqlite"))==databaseBefore,
          try FileManager.default.contentsOfDirectory(atPath:bundle.path).sorted()==namesBefore else {fatalError("Compatibility refusal mutated input or published destination")}
    print("PASS: byte-valid unsupported journal decisions remain preservable backups but cannot pass executable compatibility or publish restored state; input unchanged")
}
