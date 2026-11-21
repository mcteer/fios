import Foundation
import Darwin
import CryptoKit

// Decoded review metadata, never an installed policy or native permission.
struct PythonRuntimeEnrollmentDocument:Sendable {
    let uid:uid_t
    let host:String
    let statePath:String
    let reviewSHA256:String
    let managerSHA256:String
    let manifestSHA256:String
    let pythonSHA256:String
    let lockSHA256:String
    let producerSHA256:String
    let templateSHA256:String
    let policySHA256:String
    init(_ bytes:Data)throws {
        do {
            try StrictJSON.validate(bytes,maximum:4096)
            guard let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  Set(value.keys)==Set(["version","purpose","uid","host","state_path","review_sha256","manager_sha256","manifest_sha256",
                    "python_sha256","uv_lock_sha256","producer_sha256","release_template_sha256","policy_sha256","python_version","package_version"]),
                  WireScalar.integer(value["version"],maximum:1)==1,value["purpose"] as? String=="reviewed_platform_python_worker",
                  value["python_version"] as? String=="3.11.17",value["package_version"] as? String=="0.1.0",
                  let uid=WireScalar.integer(value["uid"],maximum:Int64(UInt32.max)),uid>0,
                  let host=value["host"] as? String,["fios-edge-a.lab","fios-edge-b.lab"].contains(host),
                  let state=value["state_path"] as? String,state.hasPrefix("/"),!state.hasSuffix("/"),!state.contains("//"),!state.contains("\0"),
                  state.utf8.count<Int(MAXPATHLEN),state.dropFirst().split(separator:"/").allSatisfy({$0 != "." && $0 != ".."}) else {throw ControlError.unauthorized}
            func digest(_ key:String)throws->String {
                guard let text=value[key] as? String,WireScalar.sha256(text) else {throw ControlError.unauthorized};return text
            }
            self.uid=uid_t(uid);self.host=host;statePath=state
            reviewSHA256=try digest("review_sha256");managerSHA256=try digest("manager_sha256");manifestSHA256=try digest("manifest_sha256")
            pythonSHA256=try digest("python_sha256");lockSHA256=try digest("uv_lock_sha256");producerSHA256=try digest("producer_sha256")
            templateSHA256=try digest("release_template_sha256");policySHA256=try digest("policy_sha256")
        }catch {throw ControlError.unauthorized}
    }
    func matches(uid:uid_t,host:String,statePath:String)->Bool {self.uid==uid && self.host==host && self.statePath==statePath}
    func matches(_ tree:PythonRuntimeTreeObservation)->Bool {
        tree.rootProtected && tree.interpreterSHA256==pythonSHA256 && tree.lockSHA256==lockSHA256 &&
        tree.producerSHA256==producerSHA256 && tree.templateSHA256==templateSHA256
    }
}

// Code-only installed factory composition. Loading reads protected metadata;
// makeFactory must run off the serialized loop and performs metadata only.
// No public startup wiring or native compatibility/dispatch issuer is added.
struct PythonRuntimeEnrolledPolicy:Sendable {
    static let policyPath="/Library/Application Support/Fios/Studio/python-enrollment.json"
    static let runtimePath="/Library/Application Support/Fios/Studio/python/runtime"
    static let managerPath=RuntimeEnrolledPolicy.managerPath
    let document:PythonRuntimeEnrollmentDocument
    let policySHA256:String
    private let directory:URL
    private init(document:PythonRuntimeEnrollmentDocument,policySHA256:String,directory:URL) {
        self.document=document;self.policySHA256=policySHA256;self.directory=directory
    }
    private static func ownPath()throws->String {
        var image=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(getpid(),&image,UInt32(image.count))>0,
              let path=String(bytes:image.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw ControlError.unauthorized}
        return path
    }
    private static func verifyManager(_ document:PythonRuntimeEnrollmentDocument,directory:URL)throws {
        guard try ownPath()==managerPath,
              document.matches(uid:geteuid(),host:ProcessInfo.processInfo.hostName,statePath:directory.path) else {throw ControlError.unauthorized}
        let manager=try VerifiedExecutable(path:managerPath,sha256:document.managerSHA256)
        try RootPolicyFile.verifyExecutable(manager)
        _=try ServiceIdentity.verified(peer:NativeControlPeer(pid:getpid(),start:WorkerResources.startIdentifier(pid:getpid()),executable:manager),
            expectedUID:document.uid,deadline:ProcessInfo.processInfo.systemUptime+2)
    }
    static func load(directory:URL)throws->PythonRuntimeEnrolledPolicy? {
        guard try ownPath()==managerPath else {return nil}
        var entry=stat()
        if lstat(policyPath,&entry) != 0 {guard errno==ENOENT else {throw ControlError.unauthorized};return nil}
        let bytes=try RootPolicyFile.read(path:policyPath,maximum:4096)
        let document=try PythonRuntimeEnrollmentDocument(bytes)
        try verifyManager(document,directory:directory)
        try RootPolicyFile.verifyExecutable(VerifiedExecutable(path:runtimePath+"/bin/python",sha256:document.pythonSHA256))
        return PythonRuntimeEnrolledPolicy(document:document,policySHA256:SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined(),directory:directory)
    }
    func makeFactory()throws->PythonWorkerFactory {
        _=try RootPolicyFile.read(path:Self.policyPath,maximum:4096,expectedSHA256:policySHA256)
        try Self.verifyManager(document,directory:directory)
        let tree=try PythonRuntimeTreeReview.rootProtectedCandidate(directory:URL(fileURLWithPath:Self.runtimePath),manifestSHA256:document.manifestSHA256)
        guard document.matches(tree) else {throw ControlError.unauthorized}
        let interpreter=try VerifiedExecutable(path:Self.runtimePath+"/bin/python",sha256:document.pythonSHA256)
        try RootPolicyFile.verifyExecutable(interpreter)
        return try PythonWorkerFactory(invocation:interpreter.path,executableSHA256:document.pythonSHA256,policySHA256:document.policySHA256)
    }
}
