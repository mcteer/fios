import Foundation
import Darwin

enum SessionEntryRole {case manager,session}

// Opaque, launch-only installation authority. No initializer takes decoded
// task/session metadata, no environment/CLI override and no fake file reader.
// Installer/release review and stopped-process immutable upgrade discipline
// remain mandatory; this does not attest all-client native activity or enable
// quit, inference, sandbox execution, login or privileged operations.
struct SessionEnrolledPolicy {
    static let policyPath="/Library/Application Support/Fios/Studio/session-enrollment.json"
    static let managerPath="/Library/Application Support/Fios/Studio/bin/studio-manager"
    static let sessionPath="/Library/Application Support/Fios/Studio/bin/studio-session"
    let document:SessionEnrollmentDocument
    let manager:VerifiedExecutable
    let session:VerifiedExecutable
    let applications:[ManagedService:VerifiedExecutable]

    private init(document:SessionEnrollmentDocument,manager:VerifiedExecutable,session:VerifiedExecutable,
                 applications:[ManagedService:VerifiedExecutable]) {
        self.document=document;self.manager=manager;self.session=session;self.applications=applications
    }
    static func load(directory:URL,role:SessionEntryRole)throws->SessionEnrolledPolicy? {
        var image=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(getpid(),&image,UInt32(image.count))>0,
              let path=String(bytes:image.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw ControlError.unauthorized}
        // Development/PR binaries remain observation-only even on a Studio
        // which already has an installed policy. No CLI/environment override.
        guard path==(role == .manager ? managerPath:sessionPath) else {return nil}
        var entry=stat()
        if lstat(policyPath,&entry) != 0 {
            guard errno==ENOENT else {throw ControlError.unauthorized}
            return nil // Default development/unenrolled helper is observation-only.
        }
        let document=try SessionEnrollmentDocument(RootPolicyFile.read(path:policyPath,maximum:4096))
        guard document.uid==geteuid(),document.host==ProcessInfo.processInfo.hostName,
              document.statePath==directory.path else {throw ControlError.unauthorized}
        let manager=try VerifiedExecutable(path:managerPath,sha256:document.managerSHA256)
        let session=try VerifiedExecutable(path:sessionPath,sha256:document.sessionSHA256)
        try RootPolicyFile.verifyExecutable(manager)
        try RootPolicyFile.verifyExecutable(session)
        let own=role == .manager ? manager:session
        _=try ServiceIdentity.verified(peer:NativeControlPeer(pid:getpid(),start:WorkerResources.startIdentifier(pid:getpid()),executable:own),
            expectedUID:document.uid,deadline:ProcessInfo.processInfo.systemUptime+2)
        // Fixed GUI executable paths, not values selected by a request or the
        // bundle's mutable Info.plist. The actuator must revalidate immutable
        // app files/signatures before issuing the fixed application operation.
        let applications:[ManagedService:VerifiedExecutable]=[
            .mlx:try VerifiedExecutable(path:"/Applications/MLX-Serve.app/Contents/MacOS/MLXCore",sha256:document.applicationHashes[.mlx]!),
            .orbstack:try VerifiedExecutable(path:"/Applications/OrbStack.app/Contents/MacOS/OrbStack",sha256:document.applicationHashes[.orbstack]!),
        ]
        return SessionEnrolledPolicy(document:document,manager:manager,session:session,applications:applications)
    }
}
