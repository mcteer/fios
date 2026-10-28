import Foundation
import Darwin

func runSessionTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    defer { try? FileManager.default.removeItem(at:directory) }
    guard SessionState.read(directory:directory,boot:"boot-one",now:1000)==nil else { fatalError("Missing session fabricated") }
    let path=directory.appendingPathComponent("session.json")
    let processStart=String(try WorkerResources.startIdentifier(pid:getpid()))
    var fields:[String:Any] = ["version":2,"uid":geteuid(),"pid":getpid(),"process_start":processStart,"boot":"boot-one","sampled_uptime_ms":1000,"console_session":true,"mlx_present":false,"orbstack_present":false,"lifecycle_enabled":false]
    try AtomicState.write(JSONSerialization.data(withJSONObject:fields),to:path)
    guard SessionState.read(directory:directory,boot:"boot-one",now:1001)?.console == true else { fatalError("Fresh session rejected") }
    guard SessionState.read(directory:directory,boot:"boot-two",now:1001)==nil else { fatalError("Previous boot session accepted") }
    guard SessionState.read(directory:directory,boot:"boot-one",now:7000)==nil else { fatalError("Stale GUI status accepted") }
    let invalidStarts:[Any]=[String((UInt64(processStart) ?? 0)+1),"0","01","1e3",true,123]
    for invalid in invalidStarts {
        fields["process_start"]=invalid
        try AtomicState.write(JSONSerialization.data(withJSONObject:fields),to:path)
        guard SessionState.read(directory:directory,boot:"boot-one",now:1001)==nil else {fatalError("Reused/malformed session process identity accepted")}
    }
    fields["process_start"]=processStart
    fields["lifecycle_enabled"]=true
    try AtomicState.write(JSONSerialization.data(withJSONObject:fields),to:path)
    guard SessionState.read(directory:directory,boot:"boot-one",now:1001)==nil else {fatalError("A session file granted lifecycle authority")}
    fields["lifecycle_enabled"]=false
    fields["uid"]=true
    try AtomicState.write(JSONSerialization.data(withJSONObject:fields),to:path)
    guard SessionState.read(directory:directory,boot:"boot-one",now:1001)==nil else { fatalError("Boolean UID accepted") }
    guard UUID(uuidString:try HostBoot.identity()) != nil else { fatalError("Boot identity unavailable") }
    print("PASS: session prerequisites bind UID/boot/kernel process-start/monotonic freshness; stale/reused identity and file-granted lifecycle authority are refused")
}
