import Foundation
import Darwin

func runSessionTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    defer { try? FileManager.default.removeItem(at:directory) }
    guard SessionState.read(directory:directory,boot:"boot-one",now:1000)==nil else { fatalError("Missing session fabricated") }
    let path=directory.appendingPathComponent("session.json")
    guard mkfifo(path.path,0o600)==0 else {throw RuntimeError.launch}
    guard SessionState.read(directory:directory,boot:"boot-one",now:1000)==nil else {fatalError("Nonregular session admitted")}
    try FileManager.default.removeItem(at:path)
    let processStart=String(try WorkerResources.startIdentifier(pid:getpid()))
    var fields:[String:Any] = ["version":2,"uid":geteuid(),"pid":getpid(),"process_start":processStart,"boot":"boot-one","sampled_uptime_ms":1000,"console_session":true,"mlx_present":false,"orbstack_present":false,"lifecycle_enabled":false]
    try AtomicState.write(JSONSerialization.data(withJSONObject:fields),to:path)
    guard SessionState.read(directory:directory,boot:"boot-one",now:1001)?.console == true else { fatalError("Fresh session rejected") }
    guard SessionState.read(directory:directory,boot:"boot-two",now:1001)==nil else { fatalError("Previous boot session accepted") }
    for now:Int64 in [0,6000] {
        guard SessionState.read(directory:directory,boot:"boot-one",now:now)?.console==true else {fatalError("Exact session clock boundary refused")}
    }
    for now:Int64 in [-1,6001,.min,.max] {
        guard SessionState.read(directory:directory,boot:"boot-one",now:now)==nil else {fatalError("Invalid or stale GUI status accepted")}
    }
    guard SessionState.read(directory:directory,boot:"boot-one",now:5999,completionNow:{6000})?.console==true else {
        fatalError("Collector refused exact final session age")
    }
    for completion:Int64 in [5998,6001,.max] {
        guard SessionState.read(directory:directory,boot:"boot-one",now:5999,completionNow:{completion})==nil else {
            fatalError("Session published outside the original clock window")
        }
    }
    fields["sampled_uptime_ms"]=1001
    try AtomicState.write(JSONSerialization.data(withJSONObject:fields),to:path)
    guard SessionState.read(directory:directory,boot:"boot-one",now:0)==nil else {fatalError("Future GUI status exceeded clock tolerance")}
    fields["sampled_uptime_ms"]=1000
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
