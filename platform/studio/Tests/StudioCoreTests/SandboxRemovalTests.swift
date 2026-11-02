import Foundation
import Darwin
import CryptoKit

func runSandboxRemovalTests()throws {
    guard let path=ProcessInfo.processInfo.environment["FIOS_PLATFORM_SANDBOX_REMOVAL_FIXTURE"],
          URL(fileURLWithPath:path).lastPathComponent=="sandbox-removal-cli" else {fatalError("Missing finite sandbox-removal CLI fixture")}
    let home="/private/tmp/fios009-sandbox-removal-"+UUID().uuidString.lowercased()
    try FileManager.default.createDirectory(atPath:home,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(atPath:home)}
    let digest=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map{String(format:"%02x",$0)}.joined()
    let runtime=try DockerRuntime(executable:VerifiedExecutable(path:path,sha256:digest),socket:home+"/docker.sock")
    let id=String(repeating:"b",count:64)
    let configuration=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"a",count:64),memory:512<<20,cpus:1)
    let marker=URL(fileURLWithPath:home+"/remove.json")
    func scenario(_ state:[String:Any])throws {
        try? FileManager.default.removeItem(at:marker)
        let object:[String:Any]=["Id":id,"Name":"/"+configuration.name,"Image":configuration.image,
            "Config":["Labels":["fios.platform.job":configuration.job,"fios.platform.nonce":configuration.nonce]],"State":state]
        try JSONSerialization.data(withJSONObject:[object]).write(to:URL(fileURLWithPath:home+"/inspect.json"))
    }
    try scenario(["Running":true])
    var refused=false
    do {try runtime.removeOwned(configuration,savedID:id)}catch RuntimeError.launch {refused=true}
    guard refused,!FileManager.default.fileExists(atPath:marker.path) else {fatalError("FIO_SANDBOX_RUNNING_REMOVE_BYPASSED_GRACE")}
    for state:[String:Any] in [[:],["Running":0],["Running":"false"],["Running":NSNull()]] {
        try scenario(state);refused=false
        do {try runtime.removeOwned(configuration,savedID:id)}catch RuntimeError.identity {refused=true}
        guard refused,!FileManager.default.fileExists(atPath:marker.path) else {fatalError("Malformed running state reached owned removal")}
    }
    try scenario(["Running":false]);try runtime.removeOwned(configuration,savedID:id)
    guard try JSONSerialization.jsonObject(with:Data(contentsOf:marker)) as? [String]==["rm",id] else {fatalError("FIO_SANDBOX_REMOVE_STILL_FORCES_RUNNING_RACE")}
    try scenario(["Running":false]);try Data().write(to:URL(fileURLWithPath:home+"/race-running"));refused=false
    do {try runtime.removeOwned(configuration,savedID:id)}catch RuntimeError.launch {refused=true}
    guard refused,try JSONSerialization.jsonObject(with:Data(contentsOf:marker)) as? [String]==["rm",id] else {fatalError("Daemon running-race refusal became successful cleanup")}
    let executor=try SandboxExecutor(runtime:runtime,allowedImages:[configuration.image])
    let formatter=ISO8601DateFormatter()
    let cases:[(String,[String:Any],Int?)]=[
        ("never-started",[:],nil),
        ("zero-time",["FinishedAt":"0001-01-01T00:00:00Z"],nil),
        ("past",["FinishedAt":"2000-01-01T00:00:00Z"],0),
        ("nanoseconds",["FinishedAt":"2000-01-01T00:00:00.123456789Z"],0),
        ("future",["FinishedAt":formatter.string(from:Date().addingTimeInterval(60))],nil),
        ("invalid-date",["FinishedAt":"2026-02-30T00:00:00Z"],nil),
        ("null",["FinishedAt":NSNull()],nil),
        ("numeric",["FinishedAt":0],nil),
        ("long-fraction",["FinishedAt":"2000-01-01T00:00:00.1234567890Z"],nil),
        ("still-running",["Running":true,"FinishedAt":"2000-01-01T00:00:00Z"],nil)
    ]
    for (label,fields,expected) in cases {
        var state:[String:Any]=["Running":false,"ExitCode":0,"OOMKilled":false]
        for (key,value) in fields {state[key]=value}
        try scenario(state)
        try executor.submit(job:configuration.job,command:.inspect(configuration,id))
        var values:[SandboxExecution]=[]
        let until=ProcessInfo.processInfo.systemUptime+2
        while values.isEmpty && ProcessInfo.processInfo.systemUptime<until {values=executor.drain();Thread.sleep(forTimeInterval:0.001)}
        guard values.count==1,case .success(.observed(_,let code,_))=values[0].result,code==expected else {fatalError("FIO_SANDBOX_UNVERIFIED_EXIT_STATUS_"+label)}
    }
    print("PASS: finite fake CLI proves running/malformed refusal, plain full-ID argv/race failure and completed-exit timestamp attenuation; no daemon/native terminal proof")
}
