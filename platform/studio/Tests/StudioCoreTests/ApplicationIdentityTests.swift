import Foundation
import CryptoKit

func runApplicationIdentityTests()throws {
    // Public, root-protected system app. Read/signature verification only;
    // Calculator, MLX-Serve and OrbStack are never launched by this fixture.
    let bundle=URL(fileURLWithPath:"/System/Applications/Calculator.app")
    let path=bundle.appendingPathComponent("Contents/MacOS/Calculator").path
    let hash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let executable=try VerifiedExecutable(path:path,sha256:hash)
    do {try RootPolicyFile.verifyApplicationTree(path:bundle.path,deadline:ProcessInfo.processInfo.systemUptime+10)}
    catch {FileHandle.standardError.write(Data("System application fixture immutable-tree preflight failed\n".utf8));throw error}
    do {try RootPolicyFile.verifyExecutable(executable)}
    catch {FileHandle.standardError.write(Data("System application fixture executable preflight failed\n".utf8));throw error}
    try ApplicationIdentity.verify(bundle:bundle,executable:executable,identifier:"com.apple.calculator",deadline:ProcessInfo.processInfo.systemUptime+10)
    for (identifier,team) in [("com.apple.foreign",nil),("com.apple.calculator", "0000000000"),("com.apple.calculator\" or true",nil)] as [(String,String?)] {
        do {try ApplicationIdentity.verify(bundle:bundle,executable:executable,identifier:identifier,team:team,deadline:ProcessInfo.processInfo.systemUptime+10);fatalError("Unapproved application identity/requirement accepted")}catch ControlError.unauthorized {}
    }
    do {try ApplicationIdentity.verify(bundle:bundle,executable:executable,identifier:"com.apple.calculator",deadline:ProcessInfo.processInfo.systemUptime-1);fatalError("Expired application check reached actuator boundary")}catch ControlError.unauthorized {}
    do {try ApplicationIdentity.verify(bundle:bundle,executable:VerifiedExecutable(path:path,sha256:String(repeating:"0",count:64)),identifier:"com.apple.calculator",deadline:ProcessInfo.processInfo.systemUptime+10);fatalError("Unapproved application executable accepted")}catch ControlError.unauthorized {}
    print("PASS: genuine system application metadata/executable/signature verification, wrong bundle/team/hash/injected requirement/expired deadline refusal; no application launch")
}
