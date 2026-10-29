import Foundation
import StudioCore

let arguments=CommandLine.arguments
let usage="Usage: studioctl --state ABSOLUTE_PRIVATE_DIRECTORY status|activity|resources|supervisor|task|export; service mlx|orbstack running|maintenance|stopped|drain|force prepare|force confirm TOKEN SCOPE_DIGEST; backup|backup-state --to ABSOLUTE_NEW_PATH; verify-backup --sha256 REVIEWED_DIGEST; restore-state|migrate-state-seven --sha256 REVIEWED_DIGEST --to ABSOLUTE_NEW_DIRECTORY\n       studioctl plan-memory --ram-gib POSITIVE_GIB\n       studioctl stage-release --from ABSOLUTE_REVIEWED_RELEASE --sha256 REVIEWED_MANIFEST_SHA --to ABSOLUTE_NEW_DIRECTORY\n"
if arguments.count==2 && ["--help","-h"].contains(arguments[1]) {
    FileHandle.standardOutput.write(Data(usage.utf8))
    exit(0)
}
if arguments.count==4,arguments[1]=="plan-memory",arguments[2]=="--ram-gib",
   let gib=UInt64(arguments[3]),gib>0,gib<=UInt64.max/(1<<30) {
    let physical=gib*(1<<30)
    let headroom=HostRAMBudget.nativeHeadroom(physicalBytes:physical)
    let headroomGiB=(Double(headroom)/Double(1<<30)*100).rounded()/100
    let plan:[String:Any] = ["mode":"planning_only","measured":false,"physical_bytes":physical,
                           "physical_gib":gib,"native_headroom_bytes":headroom,
                           "native_headroom_gib_approx":headroomGiB]
    do {
        let data=try JSONSerialization.data(withJSONObject:plan,options:[.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("studioctl: cannot render RAM plan\n".utf8))
        exit(1)
    }
}
// Artifact copying only; no state socket, journal, service or execution path.
if arguments.count==8,arguments[1]=="stage-release",arguments[2]=="--from",arguments[3].hasPrefix("/"),arguments[4]=="--sha256",arguments[6]=="--to",arguments[7].hasPrefix("/") {
    do {
        let receipt=try PlatformReleaseStaging.create(source:URL(fileURLWithPath:arguments[3]),expectedSHA256:arguments[5],destination:URL(fileURLWithPath:arguments[7]))
        let value:[String:Any]=["ok":true,"scope":"hash_bound_development_artifact_copy","manifest_sha256":receipt.manifestSHA256,"artifacts":receipt.artifacts,"bytes":receipt.bytes,"activation":false,"installed":false]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]));FileHandle.standardOutput.write(Data([10]));exit(0)
    }catch PlatformReleaseStagingError.retained(let name) {
        FileHandle.standardError.write(Data(("studioctl: staging failed; retained private copy "+name+"\n").utf8));exit(1)
    }catch PlatformReleaseStagingError.publicationUncertain {
        FileHandle.standardError.write(Data("studioctl: staging publication uncertain; inspect destination before retrying\n".utf8));exit(1)
    }catch {
        FileHandle.standardError.write(Data("studioctl: staging refused\n".utf8));exit(1)
    }
}
let offlineBackup=arguments.count==6 && ["backup","backup-state"].contains(arguments[3]) && arguments[4]=="--to" && arguments[5].hasPrefix("/")
let verifyBackup=arguments.count==6 && arguments[3]=="verify-backup" && arguments[4]=="--sha256"
let restoreBackup=arguments.count==8 && ["restore-state","migrate-state-seven"].contains(arguments[3]) && arguments[4]=="--sha256" && arguments[6]=="--to" && arguments[7].hasPrefix("/")
let ordinary=arguments.count==4 && ["status","activity","resources","supervisor","task","export"].contains(arguments[3])
let serviceCommand=OperatorServiceCommand(arguments:Array(arguments.dropFirst(3)))
if (!offlineBackup && !ordinary && !verifyBackup && !restoreBackup && serviceCommand == nil) || arguments[1] != "--state" || !arguments[2].hasPrefix("/") {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
// Fixed SSH forced-command mode never interprets client commands/stdin or
// permits a PTY. Server enrollment must separately prohibit environment and
// every forwarding/alternate subsystem channel; this is not an SSH server.
let exporting=arguments[3]=="export"
if exporting && (!(ProcessInfo.processInfo.environment["SSH_ORIGINAL_COMMAND"] ?? "").isEmpty || ProcessInfo.processInfo.environment["SSH_TTY"] != nil) {
    FileHandle.standardError.write(Data("studioctl: forced observation refused\n".utf8));exit(2)
}
do {
    let directory=URL(fileURLWithPath:arguments[2])
    let result:[String:Any]
    if restoreBackup {
        let migrating=arguments[3]=="migrate-state-seven"
        let target=URL(fileURLWithPath:arguments[7])
        let receipt=try migrating ? StoppedStateBackup.migrateSeven(directory:directory,expectedSHA256:arguments[5],destination:target):StoppedStateBackup.restore(directory:directory,expectedSHA256:arguments[5],destination:target)
        if migrating {
            result=["ok":true,"from_schema":7,"to_schema":8,"input_backup_sha256":receipt.sha256,"maintenance":true,"started":false]
        }else {
            result=["ok":true,"scope":receipt.scope,"bytes":receipt.bytes,"artifacts":receipt.artifacts,"sha256":receipt.sha256,"started":false]
        }
    } else if verifyBackup {
        let receipt=try StoppedStateBackup.verify(directory:directory,expectedSHA256:arguments[5])
        result=["ok":true,"scope":receipt.scope,"bytes":receipt.bytes,"artifacts":receipt.artifacts,"sha256":receipt.sha256]
    } else if offlineBackup {
        if arguments[3]=="backup-state" {
            let receipt=try StoppedStateBackup.create(directory:directory,destination:URL(fileURLWithPath:arguments[5]))
            result=["ok":true,"scope":receipt.scope,"bytes":receipt.bytes,"artifacts":receipt.artifacts,"sha256":receipt.sha256]
        } else {
            let receipt=try StoppedJournalBackup.create(directory:directory,destination:URL(fileURLWithPath:arguments[5]))
            result=["ok":true,"scope":"platform_journal_only","schema":receipt.schema,"bytes":receipt.bytes,"sha256":receipt.sha256]
        }
    } else if let serviceCommand {
        result=try ControlClient.request(path:directory.appendingPathComponent("control.sock").path,operation:serviceCommand.operation,payload:serviceCommand.payload)
    } else if exporting {
        let response=try ControlClient.request(path:directory.appendingPathComponent("observe.sock").path,operation:.activity)
        guard response["ok"] as? Bool==true,let observation=response["observation"] as? [String:Any] else {throw ControlError.invalid_request}
        let bytes=try JSONSerialization.data(withJSONObject:observation,options:[.sortedKeys])
        try ReadonlyObservationFrame.validateStructure(bytes)
        result=observation
    } else if arguments[3]=="task" {
        result=try TaskControlClient.request(directory:directory)
    } else if arguments[3]=="supervisor" {
        let expected=URL(fileURLWithPath:arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("studio-supervisor").path
        result=try SupervisorStatus.read(directory:directory,expectedExecutable:expected)
    } else {
        let operation=ControlOperation(rawValue:arguments[3])!
        result=try ControlClient.request(path:directory.appendingPathComponent("observe.sock").path,operation:operation)
    }
    let data=try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
    guard data.count<=65536 else {throw ControlError.invalid_request}
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    if !exporting && result["ok"] as? Bool != true { exit(1) }
} catch {
    FileHandle.standardError.write(Data("studioctl: request failed\n".utf8)); exit(1)
}
