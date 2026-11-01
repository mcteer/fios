import Foundation
import Darwin
import CryptoKit

enum NativeServingEntryRole:Sendable {case manager,supervisor}

// Protected configuration metadata only, not native activity/dependency
// attestation, exclusive ownership, a credential reader or lifecycle authority.
// The public manager does not load or activate this source factory.
struct NativeServingReviewedConfiguration:Sendable {
    static let policyPath="/Library/Application Support/Fios/Studio/native-serving-launch.json"
    static let managerPath="/Library/Application Support/Fios/Studio/bin/studio-manager"
    static let supervisorPath="/Library/Application Support/Fios/Studio/bin/studio-supervisor"
    let role:NativeServingEntryRole
    let document:NativeServingLaunchDocument
    let policySHA256:String
    let processProfile:MLXServingProcessProfile
    private init(role:NativeServingEntryRole,document:NativeServingLaunchDocument,policySHA256:String,processProfile:MLXServingProcessProfile) {
        self.role=role;self.document=document;self.policySHA256=policySHA256;self.processProfile=processProfile
    }
    func makeHealthCollector()throws->ServiceHealthCollector {
        try ServiceHealthCollector(mlxServing:processProfile,probe:document.makeHealthProbe())
    }
    // An authenticated transport, never a native admission/lifecycle permit.
    // The fixed installed manager can resolve only its reviewed supervisor.
    func makeCustodyClient(approvedHashes:[ManagedService:String])throws->ServingCustodyClient? {
        guard role == .manager,approvedHashes[.mlx]==document.serverSHA256 else {throw ControlError.unauthorized}
        let base=try ServiceLaunchProfile.digest(approvedHashes)
        let profile=try document.recoveryProfileHash(base:base,reviewedConfigurationSHA256:policySHA256)
        let directory=URL(fileURLWithPath:document.statePath)
        guard let descriptor=try ServingCustodyDescriptor.read(directory:directory,expectedUID:document.uid,expectedProfile:profile,boot:HostBoot.identity()) else {return nil}
        let peer=NativeControlPeer(pid:descriptor.pid,start:descriptor.start,executable:try VerifiedExecutable(path:Self.supervisorPath,sha256:document.supervisorSHA256))
        _=try ServiceIdentity.verified(peer:peer,expectedUID:document.uid,deadline:ProcessInfo.processInfo.systemUptime+2)
        return try ServingCustodyClient(directory:directory,peer:peer,instance:descriptor.instance,profile:profile,baseProfileHash:base,imageSHA256:document.serverSHA256)
    }
    static func load(directory:URL,role:NativeServingEntryRole = .manager)throws->NativeServingReviewedConfiguration? {
        var image=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(getpid(),&image,UInt32(image.count))>0,
              let path=String(bytes:image.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw ControlError.unauthorized}
        // Refuse development images before reading any installed metadata.
        guard path==(role == .manager ? managerPath:supervisorPath) else {return nil}
        var entry=stat()
        if lstat(policyPath,&entry) != 0 {
            guard errno==ENOENT else {throw ControlError.unauthorized};return nil
        }
        let bytes=try RootPolicyFile.read(path:policyPath,maximum:32768)
        let document=try NativeServingLaunchDocument(bytes)
        guard document.uid==geteuid(),getuid()==geteuid(),
              document.host==ProcessInfo.processInfo.hostName,document.statePath==directory.path else {throw ControlError.unauthorized}
        let manager=try VerifiedExecutable(path:managerPath,sha256:document.managerSHA256)
        let supervisor=try VerifiedExecutable(path:supervisorPath,sha256:document.supervisorSHA256)
        try RootPolicyFile.verifyExecutable(manager)
        try RootPolicyFile.verifyExecutable(supervisor)
        let own=role == .manager ? manager:supervisor
        _=try ServiceIdentity.verified(peer:NativeControlPeer(pid:getpid(),start:WorkerResources.startIdentifier(pid:getpid()),executable:own),
            expectedUID:document.uid,deadline:ProcessInfo.processInfo.systemUptime+2)
        let profile=try MLXServingProcessProfile(serverSHA256:document.serverSHA256,applicationSHA256:document.applicationSHA256,
            reviewDigest:document.reviewSHA256,uid:document.uid)
        try RootPolicyFile.verifyApplicationTree(path:MLXServingProcessProfile.bundle,deadline:ProcessInfo.processInfo.systemUptime+10)
        try RootPolicyFile.verifyExecutable(profile.server)
        try RootPolicyFile.verifyExecutable(profile.application)
        // Current immutable tree + two image pins are not mapped-code or
        // framework provenance. Native enrollment must separately establish
        // dependencies, GUI handover, namespace and retained reservations.
        return NativeServingReviewedConfiguration(role:role,document:document,policySHA256:SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined(),processProfile:profile)
    }
}
