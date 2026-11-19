import Foundation
import Darwin

private final class MetadataDaemonFixture:@unchecked Sendable {
    private let listener:UnixControlSocket
    private let done=DispatchSemaphore(value:0)
    private(set) var requests:[Data]=[]
    private var failed=false
    init(path:String,responses:[Data],optionalLastResponse:Bool=false,allowEmptyOptionalPeer:Bool=false,responded:@escaping @Sendable (Int)->Void={_ in})throws {
        listener=try UnixControlSocket(path:path)
        DispatchQueue.global().async { [self] in
            defer {done.signal()}
            do {
                for (index,response) in responses.enumerated() {
                    let optional=optionalLastResponse && index==responses.count-1
                    let end=ProcessInfo.processInfo.systemUptime+(optional ? 0.5:2)
                    var peer:Int32?
                    while peer==nil && ProcessInfo.processInfo.systemUptime<end {peer=try listener.acceptPeer();if peer==nil {Thread.sleep(forTimeInterval:0.001)}}
                    guard let peer else {if optional {break};throw RuntimeError.deadline}
                    defer {close(peer)}
                    var request=Data(),complete=false
                    while !complete && ProcessInfo.processInfo.systemUptime<end {
                        var bytes=[UInt8](repeating:0,count:4096)
                        let count=read(peer,&bytes,bytes.count)
                        if count>0 {request.append(contentsOf:bytes.prefix(count))}
                        else if count==0 {
                            if optional && allowEmptyOptionalPeer && request.isEmpty {return}
                            throw RuntimeError.launch
                        }
                        else if ![EAGAIN,EWOULDBLOCK,EINTR].contains(errno) {throw RuntimeError.launch}
                        guard request.count<=8192 else {throw RuntimeError.outputLimit}
                        if let header=request.range(of:Data("\r\n\r\n".utf8)),let text=String(data:request[..<header.lowerBound],encoding:.ascii) {
                            let line=text.components(separatedBy:"\r\n").first(where:{$0.hasPrefix("Content-Length: ")})
                            guard let line,let length=Int(line.dropFirst(16)) else {throw RuntimeError.invalid}
                            complete=request.count==header.upperBound+length
                        }
                        if !complete {Thread.sleep(forTimeInterval:0.001)}
                    }
                    guard complete else {throw RuntimeError.deadline};requests.append(request)
                    var sent=0
                    while sent<response.count && ProcessInfo.processInfo.systemUptime<end {
                        let count=response.withUnsafeBytes {write(peer,$0.baseAddress!.advanced(by:sent),response.count-sent)}
                        if count>0 {sent+=count}
                        else if ![EAGAIN,EWOULDBLOCK,EINTR].contains(errno) {throw RuntimeError.launch}
                        if count<=0 {Thread.sleep(forTimeInterval:0.001)}
                    }
                    guard sent==response.count else {throw RuntimeError.deadline}
                    responded(index)
                }
            }catch {failed=true}
        }
    }
    func finish()throws->[Data] {
        guard done.wait(timeout:.now()+3) == .success,!failed else {throw RuntimeError.deadline};return requests
    }
}

private final class MetadataFixtureClock:@unchecked Sendable {
    private let lock=NSLock()
    private var wall:Int64=10000
    func now()->Int64 {lock.lock();defer {lock.unlock()};return wall}
    func set(_ value:Int64) {lock.lock();wall=value;lock.unlock()}
}

func runDockerVMMetadataFlowTests()throws {
    let home="/private/tmp/fios-vm-flow-"+UUID().uuidString.lowercased()
    let directory=home+"/.orbstack/run"
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(atPath:home)}
    let id=String(repeating:"a",count:64),exec=String(repeating:"b",count:64)
    let files=["/proc/meminfo","/proc/self/mountinfo","/proc/self/status","/proc/sys/kernel/random/boot_id"]
    func json(_ object:[String:Any],status:Int=200)throws->Data {
        let bytes=try JSONSerialization.data(withJSONObject:object)
        return Data("HTTP/1.0 \(status) OK\r\nContent-Length: \(bytes.count)\r\n\r\n".utf8)+bytes
    }
    let created=try json(["Id":exec],status:201),payload=Data("FIXED_METADATA_FIXTURE".utf8)
    let stream=Data("HTTP/1.1 101 UPGRADED\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n".utf8)+Data([1,0,0,0,0,0,0,UInt8(payload.count)])+payload
    let completed=try json(["ID":exec,"ContainerID":id,"Running":false,"ExitCode":0,
        "ProcessConfig":["privileged":false,"tty":false,"user":"65533:65533","entrypoint":"/bin/cat","arguments":files]])
    let daemon=try MetadataDaemonFixture(path:directory+"/docker.sock",responses:[created,stream,completed])
    defer {withExtendedLifetime(daemon){}}
    let client=DockerVMMetadata(socketPath:directory+"/docker.sock",peerUID:geteuid(),endpointPolicy:try RuntimeEndpointPolicy(home:home,uid:geteuid(),peer:RuntimePeerPolicy(uid:geteuid(),executable:runtimePeerTestExecutable())))
    guard try client.read(id:id)==payload else {fatalError("Fixed metadata stream changed")}
    let requests=try daemon.finish()
    let own=try runtimePeerTestExecutable()
    let foreignPeer=try RuntimePeerPolicy(uid:geteuid(),executable:VerifiedExecutable(path:own.path,sha256:String(repeating:"0",count:64)))
    let foreign=DockerVMMetadata(socketPath:directory+"/docker.sock",peerUID:geteuid(),endpointPolicy:try RuntimeEndpointPolicy(home:home,uid:geteuid(),peer:foreignPeer))
    do {_=try foreign.inspect(id:id);fatalError("Metadata accepted an unapproved same-UID daemon image")}catch RuntimeError.identity {}

    guard chmod(directory,0o755)==0 else {fatalError("Fixture endpoint mode change failed")}
    do {_=try client.inspect(id:id);fatalError("Metadata ignored its enrolled endpoint policy")}catch RuntimeError.identity {}
    guard chmod(directory,0o700)==0 else {fatalError("Fixture endpoint mode restore failed")}

    guard requests.count==3 else {fatalError("Metadata exec was replayed")}
    guard String(decoding:requests[0],as:UTF8.self).hasPrefix("POST /v1.47/containers/"+id+"/exec HTTP/1.0\r\n"),
          String(decoding:requests[1],as:UTF8.self).hasPrefix("POST /v1.47/exec/"+exec+"/start HTTP/1.1\r\n"),
          String(decoding:requests[2],as:UTF8.self).hasPrefix("GET /v1.47/exec/"+exec+"/json HTTP/1.0\r\n") else {fatalError("Metadata route escaped fixed owned IDs")}
    let end=requests[0].range(of:Data("\r\n\r\n".utf8))!
    let command=try JSONSerialization.jsonObject(with:Data(requests[0][end.upperBound...])) as! [String:Any]
    guard Set(command.keys)==["AttachStdin","AttachStdout","AttachStderr","Tty","Privileged","User","WorkingDir","Cmd"],
          command["User"] as? String=="65533:65533",command["WorkingDir"] as? String=="/",command["Privileged"] as? Bool==false,command["Tty"] as? Bool==false,
          command["AttachStdin"] as? Bool==false,command["AttachStdout"] as? Bool==true,command["AttachStderr"] as? Bool==true,command["Cmd"] as? [String]==["/bin/cat"]+files else {fatalError("Metadata command gained caller execution authority")}
    let rejected=try MetadataDaemonFixture(path:directory+"/bad.sock",responses:[created,stream,try json(["ID":exec,"ContainerID":String(repeating:"c",count:64),"Running":false,"ExitCode":0])])
    do {_=try DockerVMMetadata(socketPath:directory+"/bad.sock",peerUID:geteuid()).read(id:id);fatalError("Foreign exec completion accepted")}catch DockerVMMetadataError.completion {}
    guard try rejected.finish().count==3 else {fatalError("Rejected completion triggered execution replay")}
    let configuration=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"d",count:64),image:"sha256:"+String(repeating:"e",count:64),memory:512<<20,cpus:1)
    let parent:[String:Any]=["Id":id,"Name":"/"+configuration.name,"Image":configuration.image,
        "Config":["User":"65532:65532","Labels":["fios.platform.job":configuration.job,"fios.platform.nonce":configuration.nonce]],
        "HostConfig":["Privileged":false,"ReadonlyRootfs":true,"NetworkMode":"none","CapDrop":["ALL"],"PidMode":"","IpcMode":"private","UTSMode":"","UsernsMode":"",
            "Devices":[],"DeviceRequests":[],"Binds":[],"CapAdd":[],"SecurityOpt":["no-new-privileges:true"],"Memory":512<<20,"MemorySwap":512<<20,"NanoCpus":1000000000,"PidsLimit":64],
        "Mounts":[],"State":["Running":true]]
    let fencedDaemon=try MetadataDaemonFixture(path:directory+"/fence.sock",responses:[try json(parent),try json(["Id":"invalid"])])
    let runtime=try DockerRuntime(executable:VerifiedExecutable(path:"/bin/false",sha256:String(repeating:"0",count:64)),socket:directory+"/fence.sock")
    let owned=try OwnedVMResourceReader(runtime:runtime,approvedImages:[configuration.image],directMetadata:true)
    let lease=HostResources.nowMilliseconds()+30000
    do {_=try owned.read(configuration:configuration,id:id,leaseUntil:lease);fatalError("Malformed metadata exec was accepted")}catch DockerVMMetadataError.create {}
    do {_=try owned.read(configuration:configuration,id:id,leaseUntil:lease);fatalError("Uncertain parent metadata read was retried")}catch RuntimeError.invalid {}
    guard try fencedDaemon.finish().count==2 else {fatalError("Metadata uncertainty fence issued another daemon request")}
    let clockCases:[(String,Int64,TimeInterval)]=[("expired",15000,1),("rewound",9999,1),("overbudget",10001,6.001)]
    for (label,wall,tick) in clockCases {
        let socket=directory+"/"+label+".sock"
        let source=try MetadataDaemonFixture(path:socket,responses:[try json(parent),try json(["Id":"invalid"])],optionalLastResponse:true)
        let fixtureRuntime=try DockerRuntime(executable:VerifiedExecutable(path:"/bin/false",sha256:String(repeating:"0",count:64)),socket:socket)
        var wallReads=0,tickReads=0
        let reader=try OwnedVMResourceReader(runtime:fixtureRuntime,approvedImages:[configuration.image],directMetadata:true,
            now:{wallReads+=1;return wallReads<=3 ? 10000:wall},uptime:{tickReads+=1;return tickReads<=3 ? 1:tick})
        var refused=false
        do {_=try reader.read(configuration:configuration,id:id,leaseUntil:15000)}
        catch RuntimeError.deadline {refused=true}
        catch {}
        guard refused,try source.finish().count==1 else {
            fatalError("Owned VM metadata reached guest read with an invalid original clock/lease: \(label)")
        }
    }
    let inspectSocket=directory+"/inspect-expired.sock"
    let inspectSource=try MetadataDaemonFixture(path:inspectSocket,responses:[try json(parent)],
        optionalLastResponse:true,allowEmptyOptionalPeer:true)
    let inspectRuntime=try DockerRuntime(executable:VerifiedExecutable(path:"/bin/false",sha256:String(repeating:"0",count:64)),socket:inspectSocket)
    var inspectReads=0
    let inspectReader=try OwnedVMResourceReader(runtime:inspectRuntime,approvedImages:[configuration.image],directMetadata:true,
        now:{inspectReads+=1;return inspectReads<=2 ? 10000:15000},uptime:{1})
    do {_=try inspectReader.read(configuration:configuration,id:id,leaseUntil:15000);fatalError("Expired inspect send returned capacity")}
    catch RuntimeError.deadline {}
    guard inspectReads==3,try inspectSource.finish().isEmpty else {fatalError("Expired inspect sent metadata bytes")}
    let startClock=MetadataFixtureClock(),startSocket=directory+"/start-expired.sock"
    let startSource=try MetadataDaemonFixture(path:startSocket,responses:[try json(parent),created,stream],optionalLastResponse:true,
        responded:{index in if index==1 {startClock.set(15000)}})
    let startRuntime=try DockerRuntime(executable:VerifiedExecutable(path:"/bin/false",sha256:String(repeating:"0",count:64)),socket:startSocket)
    let startReader=try OwnedVMResourceReader(runtime:startRuntime,approvedImages:[configuration.image],directMetadata:true,now:startClock.now,uptime:{1})
    do {_=try startReader.read(configuration:configuration,id:id,leaseUntil:15000);fatalError("Expired metadata flow returned capacity")}
    catch RuntimeError.deadline {}
    startClock.set(15001)
    do {_=try startReader.read(configuration:configuration,id:id,leaseUntil:45000);fatalError("New lease replayed uncertain metadata flow")}
    catch RuntimeError.invalid {}
    guard try startSource.finish().count==2 else {fatalError("Metadata exec start was published after original lease expired or replayed")}
    let goodClock=MetadataFixtureClock(),goodSocket=directory+"/original-clock.sock"
    let kernel=Data("MemTotal: 16384 kB\nMemFree: 8192 kB\n1 2 0:1 / /proc rw - proc proc rw\nUid: 65533 65533 65533 65533\nCapEff: 0\nNoNewPrivs: 1\n12345678-1234-1234-1234-123456789abc\n".utf8)
    let kernelStream=Data("HTTP/1.1 101 UPGRADED\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n".utf8)+Data([1,0,0,0,0,0,0,UInt8(kernel.count)])+kernel
    let goodSource=try MetadataDaemonFixture(path:goodSocket,responses:[try json(parent),created,kernelStream,completed,try json(parent)],
        responded:{index in goodClock.set(10001+Int64(index))})
    let goodRuntime=try DockerRuntime(executable:VerifiedExecutable(path:"/bin/false",sha256:String(repeating:"0",count:64)),socket:goodSocket)
    let goodReader=try OwnedVMResourceReader(runtime:goodRuntime,approvedImages:[configuration.image],directMetadata:true,now:goodClock.now,uptime:{1})
    let observation=try goodReader.read(configuration:configuration,id:id,leaseUntil:15000)
    guard observation.sampledAt==10000,observation.total==16<<20,observation.free==8<<20,try goodSource.finish().count==5 else {
        fatalError("Successful owned VM read redated its original sample or lost an observation phase")
    }
    let finalSocket=directory+"/final-inspect-expired.sock"
    let finalSource=try MetadataDaemonFixture(path:finalSocket,responses:[try json(parent),created,kernelStream,completed,try json(parent)],
        optionalLastResponse:true,allowEmptyOptionalPeer:true)
    let finalRuntime=try DockerRuntime(executable:VerifiedExecutable(path:"/bin/false",sha256:String(repeating:"0",count:64)),socket:finalSocket)
    // Initial stamp, three reads per inspect (before exchange, before
    // send and after proof), and two for each exec phase. Expire at the
    // final inspect send, not at the preceding successful guest read.
    var finalReads=0
    let finalReader=try OwnedVMResourceReader(runtime:finalRuntime,approvedImages:[configuration.image],directMetadata:true,
        now:{finalReads+=1;return finalReads==13 ? 15000:10000},uptime:{1})
    do {_=try finalReader.read(configuration:configuration,id:id,leaseUntil:15000);fatalError("Expired final inspect returned VM capacity")}
    catch RuntimeError.deadline {}
    guard finalReads==13,try finalSource.finish().count==4 else {fatalError("Expired final inspect published a request")}
    print("PASS: actual private mock Unix metadata create/start/completion flow, exact fixed cat/UID/path/argv, full exec/container binding and foreign completion refusal with no replay (mock daemon only)")
}
