import Foundation
import Darwin
import CryptoKit

private final class ServiceCensusFixture:ServiceProcessCensusReading,@unchecked Sendable {
    var entries:[Int32:ServiceProcessEntry]=[:]
    var first:[Int32]=[getpid()],second:[Int32]?=nil
    var calls=0
    var fail=false
    var time:Int64=10000
    var tick:TimeInterval=1
    init() {entries[getpid()]=ServiceProcessEntry(pid:getpid(),uid:geteuid(),realUID:getuid(),savedUID:geteuid(),start:1,path:"/usr/bin/true")}
    func pids(uid:uid_t)throws->[Int32] {calls+=1;return calls%2==1 ? first:second ?? first}
    func entry(pid:Int32)throws->ServiceProcessEntry? {if fail {throw ServiceError.invalid};return entries[pid]}
    func verify(_ entry:ServiceProcessEntry,executable:VerifiedExecutable,uid:uid_t,deadline:TimeInterval)throws->ServiceIdentity {
        ServiceIdentity(pid:entry.pid,start:entry.start,sha256:executable.sha256)
    }
}
func runServiceProcessCensusTests() throws {
    let temporary=URL(fileURLWithPath:"/tmp/fios-service-census-"+UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    guard let canonical=realpath(temporary.path,nil) else {throw ServiceError.invalid}
    let root=URL(fileURLWithPath:String(cString:canonical));free(canonical)
    defer {try? FileManager.default.removeItem(at:root)}
    guard let original=ProcessInfo.processInfo.environment["FIOS_PLATFORM_CENSUS_FIXTURE"] else {throw ServiceError.invalid}
    let binary=root.appendingPathComponent("service")
    try FileManager.default.copyItem(atPath:original,toPath:binary.path)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:binary.path)
    let hash=SHA256.hash(data:try Data(contentsOf:binary)).map {String(format:"%02x",$0)}.joined()
    let executable=try VerifiedExecutable(path:binary.path,sha256:hash),review=String(repeating:"a",count:64)
    func policy(_ fixture:ServiceCensusFixture)throws->ServiceProcessCensus {
        try ServiceProcessCensus(executable:executable,relatedRoots:[root.path],reviewDigest:review,uid:geteuid(),source:fixture,now:{fixture.time},uptime:{fixture.tick})
    }
    let fixture=ServiceCensusFixture(),census=try policy(fixture)
    let empty=census.capture()
    guard empty.presence == .absent,empty.sampledAt==10000,empty.reviewDigest==review,empty.uid==geteuid() else {fatalError("Complete scoped absence lost provenance")}
    for bad in [[],[getpid(),getpid()],[Int32.max]] {
        let source=ServiceCensusFixture();source.first=bad
        guard try policy(source).capture().presence == .unknown else {fatalError("Incomplete census became absence")}
    }
    let changed=ServiceCensusFixture();changed.first=[getpid(),Int32.max];changed.second=[getpid(),Int32.max-1]
    guard try policy(changed).capture().presence == .unknown else {fatalError("Changed census became absence")}
    let missing=ServiceCensusFixture();missing.fail=true
    guard try policy(missing).capture().presence == .unknown else {fatalError("Inspection failure became absence")}
    let candidate=ServiceProcessEntry(pid:Int32.max,uid:geteuid(),realUID:getuid(),savedUID:geteuid(),start:2,path:binary.path)
    let multiple=ServiceCensusFixture();multiple.first=[getpid(),Int32.max,Int32.max-1]
    multiple.entries[Int32.max]=candidate
    multiple.entries[Int32.max-1]=ServiceProcessEntry(pid:Int32.max-1,uid:geteuid(),realUID:getuid(),savedUID:geteuid(),start:3,path:binary.path)
    guard try policy(multiple).capture().presence == .unknown else {fatalError("Multiple service candidates adopted")}
    let principal=ServiceCensusFixture();principal.first=[getpid(),Int32.max]
    principal.entries[Int32.max]=ServiceProcessEntry(pid:Int32.max,uid:geteuid(),realUID:0,savedUID:geteuid(),start:2,path:binary.path)
    guard try policy(principal).capture().presence == .unknown else {fatalError("Unexpected candidate principal adopted")}
    let helper=root.appendingPathComponent("helper")
    try FileManager.default.copyItem(atPath:original,toPath:helper.path)
    let related=ServiceCensusFixture();related.first=[getpid(),Int32.max]
    related.entries[Int32.max]=ServiceProcessEntry(pid:Int32.max,uid:geteuid(),realUID:getuid(),savedUID:geteuid(),start:2,path:helper.path)
    guard try policy(related).capture().presence == .unknown else {fatalError("Unreviewed related helper became absence")}
    fixture.time=9999
    guard census.capture().presence == .unknown else {fatalError("Census clock rollback accepted")}
    fixture.time=10001
    guard census.capture().presence == .unknown else {fatalError("Census clock fence revived")}
    let native=try ServiceProcessCensus(executable:executable,relatedRoots:[root.path],reviewDigest:review,uid:geteuid())
    // Other same-UID CI processes may start/exit between kernel lists. Each
    // such sample must stay unknown. Observe again within a finite fixture
    // window; never turn churn into absence or relax the production checks.
    func stableCapture()->ServiceProcessSample {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        var value=native.capture()
        while value.presence == .unknown,["inspection","second_enumeration"].contains(value.diagnostic),
              ProcessInfo.processInfo.systemUptime<deadline {
            Thread.sleep(forTimeInterval:0.025)
            value=native.capture()
        }
        return value
    }
    func start()->(Process,Pipe,Pipe) {
        let process=Process(),input=Pipe(),output=Pipe()
        process.executableURL=binary;process.arguments=[];process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        return (process,input,output)
    }
    let (process,input,output)=start();try process.run()
    defer {if process.isRunning {process.terminate()};process.waitUntilExit()}
    output.fileHandleForWriting.closeFile()
    var ready=pollfd(fd:output.fileHandleForReading.fileDescriptor,events:Int16(POLLIN),revents:0)
    guard poll(&ready,1,2000)>0,try output.fileHandleForReading.read(upToCount:6)==Data("READY\n".utf8) else {fatalError("Service sentinel did not start")}
    var actualPath=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
    guard proc_pidpath(process.processIdentifier,&actualPath,UInt32(actualPath.count))>0,
          actualPath.prefix(while:{$0 != 0}).map({UInt8(bitPattern:$0)})==Array(executable.path.utf8) else {fatalError("Sentinel kernel path differs from reviewed path")}
    guard SHA256.hash(data:try Data(contentsOf:binary)).map({String(format:"%02x",$0)}).joined()==hash else {fatalError("Sentinel image changed after execution")}
    var fileInfo=stat()
    guard lstat(binary.path,&fileInfo)==0,fileInfo.st_nlink==1,fileInfo.st_mode&0o6022==0 else {fatalError("Sentinel inode is not private single-link executable")}
    do {
        _=try ServiceIdentity.verified(peer:NativeControlPeer(pid:process.processIdentifier,start:WorkerResources.startIdentifier(pid:process.processIdentifier),executable:executable),expectedUID:geteuid(),deadline:ProcessInfo.processInfo.systemUptime+1)
    } catch {fatalError("Owned sentinel direct identity check failed: \(error)")}
    let observed=stableCapture()
    guard case .present(let identity)=observed.presence,identity.pid==process.processIdentifier,identity.start==(try WorkerResources.startIdentifier(pid:process.processIdentifier)) else {fatalError("Live service identity was not verified: \(observed.diagnostic)")}
    guard process.isRunning else {fatalError("Census signalled sentinel")}
    process.terminate();process.waitUntilExit() // Only the fixture owner signals its child.
    try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()
    let after=stableCapture()
    guard after.presence == .absent else {fatalError("Reaped service remained present or inspection incomplete")}
    try FileManager.default.removeItem(at:binary)
    try FileManager.default.copyItem(atPath:original,toPath:binary.path)
    guard native.capture().presence == .unknown else {fatalError("Replaced reviewed image retained census authority")}
    print("PASS: bounded UID-scoped process census, two-list/inspection/clock/image refusal and real owned sentinel PID/start/path/hash presence then scoped absence; no launch or native-terminal authority")
}
