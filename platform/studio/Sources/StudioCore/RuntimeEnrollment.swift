import Foundation
import Darwin
import CryptoKit

// A decoded document is metadata, never an issuer. No caller-selected CLI paths, socket,
// environment, native coverage, images or task permissions are caller fields.
struct RuntimeEnrollmentDocument {
    let uid:uid_t
    let host:String
    let statePath:String
    let homePath:String
    let reviewSHA256:String
    let managerSHA256:String
    let dockerSHA256:String
    let orbctlSHA256:String
    let daemonRelativePath:String
    let daemonSHA256:String
    init(_ bytes:Data)throws {
        do {
            try StrictJSON.validate(bytes,maximum:4096)
            guard let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  Set(value.keys)==Set(["version","purpose","uid","host","state_path","home_path","review_sha256",
                      "manager_sha256","docker_sha256","orbctl_sha256","daemon_relative_path","daemon_sha256"]),
                  WireScalar.integer(value["version"],maximum:2)==2,
                  value["purpose"] as? String=="reviewed_platform_runtime",
                  let uid=WireScalar.integer(value["uid"],maximum:Int64(UInt32.max)),uid>0,
                  let host=value["host"] as? String,["fios-edge-a.lab","fios-edge-b.lab"].contains(host),
                  let state=value["state_path"] as? String,state.hasPrefix("/"),!state.hasSuffix("/"),
                  !state.contains("\0"),!state.contains("//"),state.utf8.count<Int(MAXPATHLEN),
                  state.dropFirst().split(separator:"/").allSatisfy({$0 != "." && $0 != ".."}),
                  let home=value["home_path"] as? String,home.hasPrefix("/Users/"),
                  home.split(separator:"/",omittingEmptySubsequences:false).count==3,
                  !home.hasSuffix("/"),!home.contains("\0"),home.utf8.count<Int(MAXPATHLEN),
                  ![".",".."].contains(String(home.dropFirst(7))),
                  let review=value["review_sha256"] as? String,WireScalar.sha256(review),
                  let manager=value["manager_sha256"] as? String,WireScalar.sha256(manager),
                  let docker=value["docker_sha256"] as? String,WireScalar.sha256(docker),
                  let orbctl=value["orbctl_sha256"] as? String,WireScalar.sha256(orbctl),
                  let relative=value["daemon_relative_path"] as? String,relative.hasPrefix("Contents/"),
                  relative.utf8.count<=512,!relative.contains("\0"),!relative.hasSuffix("/"),
                  relative.split(separator:"/",omittingEmptySubsequences:false).allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}),
                  let daemon=value["daemon_sha256"] as? String,WireScalar.sha256(daemon) else {throw ControlError.unauthorized}
            self.uid=uid_t(uid);self.host=host;statePath=state;homePath=home;reviewSHA256=review
            managerSHA256=manager;dockerSHA256=docker;orbctlSHA256=orbctl
            daemonRelativePath=relative;daemonSHA256=daemon
        } catch {throw ControlError.unauthorized}
    }
}

// Only the fixed installed manager image can load root-reviewed immutable
// runtime inputs. This factory performs no CLI, daemon or lifecycle operation.
// A separate native/admission/image/lease policy must enable any task executor.
struct RuntimeEnrolledPolicy {
    static let policyPath="/Library/Application Support/Fios/Studio/runtime-enrollment.json"
    static let managerPath="/Library/Application Support/Fios/Studio/bin/studio-manager"
    // Preserve the Docker multicall basename without following the mutable
    // installed `docker` alias. The operator must stage this exact reviewed
    // binary as a root-owned, single-link immutable installation artifact.
    static let dockerPath="/Library/Application Support/Fios/Studio/bin/docker"
    static let orbctlPath="/Applications/OrbStack.app/Contents/MacOS/scli.app/Contents/MacOS/scli"
    let document:RuntimeEnrollmentDocument
    let policySHA256:String
    let runtime:DockerRuntime
    private let orbctl:VerifiedExecutable
    var inventory:VerifiedVMInventory {VerifiedVMInventory(executable:orbctl,home:document.homePath)}
    var capacity:VerifiedVMCap {VerifiedVMCap(executable:orbctl,home:document.homePath)}
    private init(document:RuntimeEnrollmentDocument,policySHA256:String,runtime:DockerRuntime,orbctl:VerifiedExecutable) {
        self.document=document;self.policySHA256=policySHA256;self.runtime=runtime;self.orbctl=orbctl
    }
    static func load(directory:URL)throws->RuntimeEnrolledPolicy? {
        var image=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(getpid(),&image,UInt32(image.count))>0,
              let path=String(bytes:image.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw ControlError.unauthorized}
        guard path==managerPath else {return nil}
        var entry=stat()
        if lstat(policyPath,&entry) != 0 {
            guard errno==ENOENT else {throw ControlError.unauthorized};return nil
        }
        let bytes=try RootPolicyFile.read(path:policyPath,maximum:4096)
        let document=try RuntimeEnrollmentDocument(bytes)
        guard document.uid==geteuid(),document.host==ProcessInfo.processInfo.hostName,
              document.statePath==directory.path else {throw ControlError.unauthorized}
        let manager=try VerifiedExecutable(path:managerPath,sha256:document.managerSHA256)
        try RootPolicyFile.verifyExecutable(manager)
        _=try ServiceIdentity.verified(peer:NativeControlPeer(pid:getpid(),start:WorkerResources.startIdentifier(pid:getpid()),executable:manager),
            expectedUID:document.uid,deadline:ProcessInfo.processInfo.systemUptime+2)
        let docker=try VerifiedExecutable(path:dockerPath,sha256:document.dockerSHA256)
        let orbctl=try VerifiedExecutable(path:orbctlPath,sha256:document.orbctlSHA256)
        try RootPolicyFile.verifyExecutable(docker)
        // orbctl locates bundled resources relative to its installed image;
        // protect that complete tree rather than silently copying it elsewhere.
        try RootPolicyFile.verifyApplicationTree(path:"/Applications/OrbStack.app",deadline:ProcessInfo.processInfo.systemUptime+10)
        try RootPolicyFile.verifyExecutable(orbctl)
        // The root-reviewed account home, never HOME or a CLI/context option,
        // selects the fixed local OrbStack suffix. Same-user host compromise
        // remains outside the sandbox boundary, not daemon peer attestation.
        var home=stat()
        guard lstat(document.homePath,&home)==0,home.st_mode&S_IFMT==S_IFDIR,
              home.st_uid==document.uid,home.st_mode&0o022==0 else {throw ControlError.unauthorized}
        let daemon=try VerifiedExecutable(path:"/Applications/OrbStack.app/"+document.daemonRelativePath,sha256:document.daemonSHA256)
        try RootPolicyFile.verifyExecutable(daemon)
        let peer=try RuntimePeerPolicy(uid:document.uid,executable:daemon)
        let endpoint=try RuntimeEndpointPolicy(home:document.homePath,uid:document.uid,peer:peer)
        let runtime=DockerRuntime(executable:docker,endpoint:endpoint)
        return RuntimeEnrolledPolicy(document:document,
            policySHA256:SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined(),runtime:runtime,orbctl:orbctl)
    }
}
