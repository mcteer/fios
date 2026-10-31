import Foundation
import CryptoKit

func runVMHostFootprintTests() throws {
    let path="/bin/sleep",digest=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let executable=try VerifiedExecutable(path:path,sha256:digest),child=Process()
    child.executableURL=URL(fileURLWithPath:path);child.arguments=["5"];child.environment=["PATH":"/usr/bin:/bin"]
    child.standardInput=FileHandle.nullDevice;child.standardOutput=FileHandle.nullDevice;child.standardError=FileHandle.nullDevice
    try child.run();defer {if child.isRunning {child.terminate()};child.waitUntilExit()}
    let value=try VMHostFootprint.sample(executable:executable,pid:child.processIdentifier)
    guard value.resident>0,value.physicalFootprint>0,value.startIdentifier>0 else {fatalError("Missing native footprint fabricated zero")}
    do {_=try VMHostFootprint.sample(executable:executable,pid:child.processIdentifier,expectedStart:UInt64.max);fatalError("Foreign/recycled process footprint accepted")}catch RuntimeError.identity {}
    print("PASS: identity/start-bound native footprint counters are readable without VM execution; no unproven free-capacity derivation")
}
