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
    print("PASS: fixed different-UID owned-container VM reader rejects foreign/privileged/host-namespace/mount/device targets and binds procfs observation to kernel boot hash")
}
