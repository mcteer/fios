import Foundation
import CryptoKit

func runOwnedVMResourceTests() throws {
    let job=UUID().uuidString.lowercased(),id=String(repeating:"d",count:64),image="sha256:"+String(repeating:"a",count:64)
    let configuration=try SandboxConfiguration(job:job,nonce:String(repeating:"b",count:64),image:image,memory:512<<20,cpus:1)
    let host:[String:Any]=["Privileged":false,"ReadonlyRootfs":true,"NetworkMode":"none","CapDrop":["ALL"],"CapAdd":NSNull(),"SecurityOpt":["no-new-privileges:true"],"PidMode":"","IpcMode":"private","UTSMode":"","UsernsMode":"","Devices":[],"DeviceRequests":NSNull(),"Binds":NSNull(),"Memory":512<<20,"MemorySwap":512<<20,"NanoCpus":1000000000,"PidsLimit":64]
    let target:[String:Any]=["Id":id,"Name":"/"+configuration.name,"Image":image,"Config":["User":"65532:65532","Labels":["fios.platform.job":job,"fios.platform.nonce":configuration.nonce]],"HostConfig":host,"Mounts":[],"State":["Running":true]]
    guard OwnedVMResourceReader.safeTarget(target,configuration:configuration,id:id) else {fatalError("Owned isolated VM read target refused")}
    for (key,value):(String,Any) in [("Memory",1024<<20),("Memory",true),("MemorySwap",-1),("NanoCpus",2000000000),("PidsLimit",0),("Privileged",true),("ReadonlyRootfs",false),("PidMode","host"),("NetworkMode","host"),("Binds",["/host:/escape"]),("Devices",[["PathOnHost":"/dev/mem"]]),("DeviceRequests",[["Driver":"unapproved"]])] {
        var changed=host;changed[key]=value;var object=target;object["HostConfig"]=changed
        guard !OwnedVMResourceReader.safeTarget(object,configuration:configuration,id:id) else {fatalError("Unsafe VM read target accepted")}
    }
    let boot="12345678-1234-1234-1234-123456789abc"
    let raw="MemTotal: 16384 kB\nMemFree: 8192 kB\n1 2 0:1 / /proc rw - proc proc rw\nUid: 65533 65533 65533 65533\nCapEff: 0000000000000000\nNoNewPrivs: 1\n"+boot+"\n"
    let sample=try OwnedVMResourceReader.decode(Data(raw.utf8),sampledAt:1000)
    guard sample.total==16<<20,sample.free==8<<20,sample.bootHash.count==64 else {fatalError("VM exec observation incorrectly decoded")}
    do {_=try OwnedVMResourceReader.decode(Data(("MemTotal: 1 kB\nMemFree: 0 kB\n"+boot).utf8),sampledAt:1000);fatalError("Missing kernel procfs proof accepted")}catch RuntimeError.identity {}
    for altered in [raw.replacingOccurrences(of:"65533",with:"65532"),raw.replacingOccurrences(of:"NoNewPrivs: 1",with:"NoNewPrivs: 0"),raw.replacingOccurrences(of:"CapEff: 0000000000000000",with:"CapEff: 0000000000000001"),raw.replacingOccurrences(of:boot,with:"not-a-kernel-identity")] {
        do {_=try OwnedVMResourceReader.decode(Data(altered.utf8),sampledAt:1000);fatalError("Unsealed/foreign-UID resource process accepted")}catch RuntimeError.identity {}
    }
    let falsePath="/usr/bin/false",digest=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:falsePath))).map {String(format:"%02x",$0)}.joined()
    let runtime=try DockerRuntime(executable:VerifiedExecutable(path:falsePath,sha256:digest),socket:"/fixture/not-a-runtime.sock")
    let reader=try OwnedVMResourceReader(runtime:runtime,approvedImages:[image])
    let until=HostResources.nowMilliseconds()+30000
    do {_=try reader.read(configuration:configuration,id:id,leaseUntil:until);fatalError("Failed verification accepted VM sample")}catch RuntimeError.launch {}
    do {_=try reader.read(configuration:configuration,id:id,leaseUntil:until);fatalError("Uncertain target automatically re-executed")}catch RuntimeError.invalid {}
    reader.releaseAfterVerifiedAbsence(id:id) // Trusted lifecycle proof seam, no public operation.
    do {_=try reader.read(configuration:configuration,id:id,leaseUntil:until);fatalError("False fixture produced VM sample")}catch RuntimeError.launch {}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-owned-vm-"+job)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:directory)}
    let cli=directory.appendingPathComponent("mock-docker"),log=directory.appendingPathComponent("operations")
    let json=String(decoding:try JSONSerialization.data(withJSONObject:[target]),as:UTF8.self)
    func quoted(_ value:String)->String {"'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'"}
    let script=Data(("#!/bin/sh\n[ \"$1\" = --host ] && [ \"$2\" = unix:///fixture/not-a-runtime.sock ] || exit 1\n" +
        "printf '%s\\n' \"$3\" >> "+quoted(log.path)+"\n" +
        "case \"$3\" in inspect) printf '%s' "+quoted(json)+";; exec) printf '%s' "+quoted(raw)+";; *) exit 1;; esac\n").utf8)
    try script.write(to:cli)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:cli.path)
    let hash=SHA256.hash(data:script).map{String(format:"%02x",$0)}.joined()
    let mock=try DockerRuntime(executable:VerifiedExecutable(path:cli.path,sha256:hash),socket:"/fixture/not-a-runtime.sock")
    var preInspectReads=0
    let expiredInspect=try OwnedVMResourceReader(runtime:mock,approvedImages:[image],now:{
        preInspectReads+=1;return preInspectReads==1 ? 10000:15000
    },uptime:{1})
    do {_=try expiredInspect.read(configuration:configuration,id:id,leaseUntil:15000);fatalError("Expired inspect returned a VM sample")}
    catch RuntimeError.deadline {}
    guard !FileManager.default.fileExists(atPath:log.path) else {fatalError("Expired VM lease still published initial inspect")}
    for edge in [false,true] {
        var wallCalls=0,tickCalls=0
        let boundary=try OwnedVMResourceReader(runtime:mock,approvedImages:[image],now:{
            wallCalls+=1;return edge && wallCalls>1 ? 15000:10000
        },uptime:{
            tickCalls+=1;return !edge && tickCalls>1 ? 6:1
        })
        do {
            _=try boundary.read(configuration:configuration,id:id,leaseUntil:16000)
            fatalError("Owned VM read accepted exact observation budget cutoff")
        } catch RuntimeError.deadline {}
        guard !FileManager.default.fileExists(atPath:log.path) else {fatalError("Observation deadline still published inspect")}
    }
    var reads=0
    let expired=try OwnedVMResourceReader(runtime:mock,approvedImages:[image],now:{reads+=1;return reads<4 ? 10000:15000},uptime:{1})
    do {_=try expired.read(configuration:configuration,id:id,leaseUntil:15000);fatalError("Mock CLI exec ran after expiry during preflight")}
    catch RuntimeError.deadline {}
    guard try String(contentsOf:log,encoding:.utf8)=="inspect\n" else {fatalError("Expired CLI published guest execution")}
    var goodWall=0,goodTick=0
    let good=try OwnedVMResourceReader(runtime:mock,approvedImages:[image],now:{
        goodWall+=1;return goodWall==1 ? 10000:14999
    },uptime:{
        goodTick+=1;return goodTick==1 ? 1:5.999
    })
    let result=try good.read(configuration:configuration,id:id,leaseUntil:15000)
    guard result.sampledAt==10000,result.total==sample.total,result.free==sample.free,result.bootHash==sample.bootHash,
          try String(contentsOf:log,encoding:.utf8)=="inspect\ninspect\nexec\ninspect\n" else {
        fatalError("Valid owned VM CLI observation did not traverse all phases")
    }
    print("PASS: fixed different-UID owned-container VM reader rejects foreign/privileged/host-namespace/mount/device targets and binds procfs observation to kernel boot hash")
}
