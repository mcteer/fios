import Foundation
import Darwin
import CoreFoundation
import CryptoKit

enum VMMetadataReadError:Error {case target,payload}

struct VMKernelSample:Sendable {
    let sampledAt:Int64
    let total:UInt64
    let free:UInt64
    let bootHash:String
    var envelope:VMResourceObservation? = nil
}

// Trusted off-loop collector only; no IPC accepts an exec command/path/user.
// Reuses an already-owned sandbox, never a foreign container or a third slot.
// The different guest UID prevents task code from signalling/ptracing the
// reader or rewriting its stdout. Its only executable and paths are fixed.
final class OwnedVMResourceReader:@unchecked Sendable {
    private let runtime:DockerRuntime
    private let images:Set<String>
    private let metadata:DockerVMMetadata?
    private let lock=NSLock()
    private var fenced=Set<String>()
    init(runtime:DockerRuntime,approvedImages:Set<String>,directMetadata:Bool=false) throws {
        guard !approvedImages.isEmpty,approvedImages.count<=8 else {throw RuntimeError.invalid}
        self.runtime=runtime;images=approvedImages
        metadata=directMetadata ? DockerVMMetadata(socketPath:runtime.socket,peerUID:geteuid(),endpointPolicy:runtime.endpointPolicy):nil
    }
    static func safeTarget(_ object:[String:Any],configuration:SandboxConfiguration,id:String)->Bool {
        func bool(_ value:Any?,_ expected:Bool)->Bool {
            guard let number=value as? NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID() else {return false};return number.boolValue==expected
        }
        func integer(_ value:Any?,_ expected:Int64)->Bool {
            guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),!["d","f"].contains(String(cString:number.objCType)) else {return false}
            return number.int64Value==expected
        }
        guard configuration.verifies(inspect:object,savedID:id),
              let config=object["Config"] as? [String:Any],config["User"] as? String=="65532:65532",
              let host=object["HostConfig"] as? [String:Any],bool(host["Privileged"],false),bool(host["ReadonlyRootfs"],true),
              host["NetworkMode"] as? String=="none",host["CapDrop"] as? [String]==["ALL"],
              integer(host["Memory"],Int64(configuration.memory)),integer(host["MemorySwap"],Int64(configuration.memory)),
              integer(host["NanoCpus"],Int64(configuration.cpus)*1000000000),integer(host["PidsLimit"],64),
              host["PidMode"] as? String=="",host["IpcMode"] as? String=="private",host["UTSMode"] as? String=="",host["UsernsMode"] as? String=="",
              (host["Devices"] is NSNull || (host["Devices"] as? [Any])?.isEmpty==true),
              (host["DeviceRequests"] is NSNull || (host["DeviceRequests"] as? [Any])?.isEmpty==true),
              (host["Binds"] is NSNull || (host["Binds"] as? [Any])?.isEmpty==true),
              (host["CapAdd"] is NSNull || (host["CapAdd"] as? [String])==[]),
              let options=host["SecurityOpt"] as? [String],options.contains(where:{$0=="no-new-privileges:true" || $0=="no-new-privileges"}),
              let mounts=object["Mounts"] as? [[String:Any]],mounts.allSatisfy({$0["Type"] as? String=="tmpfs" && ["/workspace","/tmp"].contains($0["Destination"] as? String ?? "")}),
              let state=object["State"] as? [String:Any],bool(state["Running"],true) else {return false}
        return true
    }
    private func verify(_ configuration:SandboxConfiguration,id:String)throws {
        if let metadata {
            guard Self.safeTarget(try metadata.inspect(id:id),configuration:configuration,id:id) else {throw VMMetadataReadError.target}
            return
        }
        let result=try runtime.command(["inspect","--type=container",id],timeout:1)
        guard result.status==0 else {throw RuntimeError.launch}
        try StrictJSON.validate(result.output,maximum:1<<20)
        guard let values=try JSONSerialization.jsonObject(with:result.output) as? [[String:Any]],values.count==1,
              Self.safeTarget(values[0],configuration:configuration,id:id) else {throw RuntimeError.identity}
    }
    static func decode(_ data:Data,sampledAt:Int64)throws->VMKernelSample {
        guard data.count<=32768,let text=String(data:data,encoding:.utf8) else {throw RuntimeError.invalid}
        let lines=text.split(separator:"\n")
        let uid=lines.first(where:{$0.hasPrefix("Uid:")})?.split(whereSeparator:{$0.isWhitespace})
        let capabilities=lines.first(where:{$0.hasPrefix("CapEff:")})?.split(whereSeparator:{$0.isWhitespace})
        let privileges=lines.first(where:{$0.hasPrefix("NoNewPrivs:")})?.split(whereSeparator:{$0.isWhitespace})
        guard uid?.count==5,uid?.dropFirst().allSatisfy({$0=="65533"})==true,
              capabilities?.count==2,capabilities?.last?.isEmpty==false,capabilities?.last?.allSatisfy({$0=="0"})==true,
              privileges?.count==2,privileges?.last=="1" else {throw RuntimeError.identity}
        guard lines.contains(where:{$0.contains(" /proc ") && $0.contains(" - proc ")}),
              !lines.contains(where:{let fields=$0.split(separator:" ");return fields.count>4 && fields[4]=="/proc/meminfo"}),
              let boot=lines.last,UUID(uuidString:String(boot))?.uuidString.lowercased()==String(boot) else {throw RuntimeError.identity}
        let selected=lines.filter({$0.hasPrefix("MemTotal:") || $0.hasPrefix("MemFree:")}).joined(separator:"\n")
        guard let memory=VMResources.kernelMemory(Data(selected.utf8)) else {throw RuntimeError.invalid}
        let hash=SHA256.hash(data:Data(("fios-vm-boot-v1\0"+boot).utf8)).map {String(format:"%02x",$0)}.joined()
        return VMKernelSample(sampledAt:sampledAt,total:memory.total,free:memory.free,bootHash:hash)
    }
    // Lifecycle executor calls this only after successful exact-ID listing
    // proves parent-container absence. Age/idle/cancel alone never clear it.
    func releaseAfterVerifiedAbsence(id:String) {
        lock.lock();fenced.remove(id);lock.unlock()
    }
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        guard images.contains(configuration.image),id.utf8.count==64,id.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else {throw RuntimeError.identity}
        let began=ProcessInfo.processInfo.systemUptime,sampledAt=HostResources.nowMilliseconds()
        guard sampledAt>=0,sampledAt<=ActivityPolicy.maximumTimestamp,leaseUntil<=ActivityPolicy.maximumTimestamp,leaseUntil>sampledAt,leaseUntil-sampledAt>=5000 else {throw RuntimeError.deadline}
        lock.lock()
        guard fenced.count<64,!fenced.contains(id) else {lock.unlock();throw RuntimeError.invalid}
        fenced.insert(id);lock.unlock()
        // Any error retains the fence. A CLI timeout is not guest-process
        // absence; do not repeatedly execute into an uncertain target.
        try verify(configuration,id:id)
        let output:Data
        if let metadata {output=try metadata.read(id:id)}
        else {
            let result=try runtime.command(["exec","--user","65533:65533","--workdir","/",id,"/bin/cat","/proc/meminfo","/proc/self/mountinfo","/proc/self/status","/proc/sys/kernel/random/boot_id"],timeout:1)
            guard result.status==0 else {throw RuntimeError.launch};output=result.output
        }
        let sample:VMKernelSample
        do {sample=try Self.decode(output,sampledAt:sampledAt)}catch {throw VMMetadataReadError.payload}
        try verify(configuration,id:id)
        let now=HostResources.nowMilliseconds()
        guard ProcessInfo.processInfo.systemUptime-began<=5,now>=sampledAt-1000,now-sampledAt<=5000,now<leaseUntil else {throw RuntimeError.deadline}
        lock.lock();fenced.remove(id);lock.unlock()
        return sample
    }
}
