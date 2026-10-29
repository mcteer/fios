import Foundation
import Darwin
import CryptoKit

struct WorkerMetadata:Decodable,Sendable {
    let version:Int
    let pipe_version:Int
    let package_version:String
    let python_version:String
    let policy_sha256:String
    let policy_input_units:Int
}

// Constructed only by trusted, reviewed enrollment, never by task IPC. Profile
// acceptance includes cached model/capacity/native non-preemption evidence.
struct WorkerDispatchBinding:Sendable {
    let baseURL:String
    let guardPath:String
    let host:String
    let profileHash:String
    let managerEpoch:String
    let canonicalModel:String
    let nativeModel:String
    let nativeSnapshot:NativeSnapshot
    let nativeCompatibilityAccepted:Bool
    let apiKey:String?
}

final class PythonWorkerFactory:Sendable {
    private let invocation:String
    private let executable:VerifiedExecutable
    let metadata:WorkerMetadata
    private static let arguments=["-I","-B","-m","fios_agent.platform_worker"]
    private static let environment=["PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C","HOME":"/var/empty","PYDANTIC_AI_NO_BANNER":"1"]

    init(invocation:String,executableSHA256:String,policySHA256:String,packageVersion:String="0.1.0") throws {
        guard geteuid() != 0,invocation.hasPrefix("/"),!invocation.contains("\0"),invocation.utf8.count<=4096 else { throw RuntimeError.identity }
        self.invocation=invocation
        executable=try VerifiedExecutable(path:URL(fileURLWithPath:invocation).resolvingSymlinksInPath().path,sha256:executableSHA256)
        try Self.verifyInvocation(invocation,executable:executable)
        let bytes=try Self.probe(invocation:invocation)
        try StrictJSON.validate(bytes,maximum:4096)
        guard let object=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              Set(object.keys)==Set(["version","pipe_version","package_version","python_version","policy_sha256","policy_input_units"]) else { throw RuntimeError.identity }
        metadata=try JSONDecoder().decode(WorkerMetadata.self,from:bytes)
        guard metadata.version==1,metadata.pipe_version==1,metadata.package_version==packageVersion,
              metadata.python_version=="3.11.17",metadata.policy_sha256==policySHA256,
              (1...128000).contains(metadata.policy_input_units) else { throw RuntimeError.identity }
    }
    private static func verifyInvocation(_ path:String,executable:VerifiedExecutable) throws {
        var info=stat()
        guard lstat(path,&info)==0,info.st_uid==0 || info.st_uid==geteuid(),
              [S_IFREG,S_IFLNK].contains(info.st_mode & S_IFMT),
              (info.st_mode & S_IFMT == S_IFLNK || info.st_mode & 0o022==0),
              URL(fileURLWithPath:path).resolvingSymlinksInPath().path==executable.path else { throw RuntimeError.identity }
        try executable.verify()
    }
    private static func probe(invocation:String) throws -> Data {
        let process=Process(),pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:invocation);process.arguments=arguments+["--metadata"]
        process.environment=environment;process.currentDirectoryURL=URL(fileURLWithPath:"/var/empty")
        process.standardInput=FileHandle.nullDevice;process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        try process.run()
        let handle=pipe.fileHandleForReading,fd=handle.fileDescriptor
        defer { try? handle.close();if process.isRunning { kill(process.processIdentifier,SIGKILL) } }
        guard fcntl(fd,F_SETFL,O_NONBLOCK)>=0 else { throw RuntimeError.launch }
        let deadline=ProcessInfo.processInfo.systemUptime+10
        var data=Data(),eof=false
        while !eof || process.isRunning {
            var bytes=[UInt8](repeating:0,count:4096)
            let count=Darwin.read(fd,&bytes,bytes.count)
            if count>0 {
                guard data.count+count<=4096 else { throw RuntimeError.outputLimit };data.append(contentsOf:bytes.prefix(count))
            } else if count==0 { eof=true }
            else if errno != EINTR && errno != EAGAIN { throw RuntimeError.launch }
            guard ProcessInfo.processInfo.systemUptime<deadline else { throw RuntimeError.deadline }
            if !eof || process.isRunning { Thread.sleep(forTimeInterval:0.005) }
        }
        // EOF plus !isRunning already establish terminated metadata output.
        // Do not add an unbounded Foundation notification wait after deadline.
        guard process.terminationStatus==0 else { throw RuntimeError.identity }
        return data
    }
    // Pure binding validation. Binary verification/spawn occur off-loop for
    // broker starts; no journal, caller argv or permission bytes enter work.
    private func validate(_ binding:WorkerDispatchBinding,now:Int64)throws {
        guard binding.nativeCompatibilityAccepted,binding.nativeSnapshot.host==binding.host,
              binding.nativeSnapshot.endpointHash==Self.digest(binding.baseURL),
              binding.profileHash.utf8.count==64,binding.profileHash.utf8.allSatisfy({ (48...57).contains($0)||(97...102).contains($0) }),
              UUID(uuidString:binding.managerEpoch)?.uuidString.lowercased()==binding.managerEpoch,
              binding.guardPath.hasPrefix("/"),binding.guardPath.hasSuffix("/observe.sock"),
              try ActivityPolicy.permits(target:binding.canonicalModel,snapshot:binding.nativeSnapshot,now:now) else { throw PolicyError.invalidObservation }
        let components=URLComponents(string:binding.baseURL)
        guard components?.scheme=="http",["127.0.0.1","::1","[::1]"].contains(components?.host ?? ""),
              components?.path=="/v1",components?.user==nil,components?.password==nil,
              components?.query==nil,components?.fragment==nil else { throw RuntimeError.identity }
    }
    func beginStart(binding:WorkerDispatchBinding,launchID:String,started:Int64,now:Int64)throws->PendingPythonWorker {
        try validate(binding,now:now)
        guard WireScalar.uuid(launchID),started>=0,started<=ActivityPolicy.maximumTimestamp-2000 else {throw RuntimeError.invalid}
        return PendingPythonWorker { [self] cancelled in
            do {return .success(try spawnTransport(binding:binding,launchID:launchID,cancelled:cancelled))}
            catch WorkerStartFailure.cancelled {return .failure(.cancelled)}
            catch {return .failure(.unavailable)}
        }
    }
    private func spawnTransport(binding:WorkerDispatchBinding,launchID:String,cancelled:@Sendable ()->Bool)throws->StartedPythonWorker {
        guard !cancelled() else {throw WorkerStartFailure.cancelled}
        try Self.verifyInvocation(invocation,executable:executable)
        guard !cancelled() else {throw WorkerStartFailure.cancelled}
        let process=Process(),input=Pipe(),output=Pipe()
        var env=Self.environment
        env["FIOS_PLATFORM_LAUNCH_ID"]=launchID
        env["MLX_BASE_URL"]=binding.baseURL
        env["MLX_API_KEY"]=binding.apiKey ?? "not-required"
        env["FIOS_WEB_SEARCH"]="off"
        env["FIOS_PLATFORM_GUARD_PATH"]=binding.guardPath
        env["FIOS_PLATFORM_HOST_ID"]=binding.host
        env["FIOS_PLATFORM_PROFILE_HASH"]=binding.profileHash
        env["FIOS_PLATFORM_NATIVE_EPOCH"]=binding.nativeSnapshot.nativeEpoch
        env["FIOS_PLATFORM_NATIVE_SEQUENCE"]=String(binding.nativeSnapshot.sequence)
        env["FIOS_PLATFORM_CANONICAL_MODEL"]=binding.canonicalModel
        env["FIOS_PLATFORM_NATIVE_MODEL"]=binding.nativeModel
        process.executableURL=URL(fileURLWithPath:invocation);process.arguments=Self.arguments
        process.environment=env;process.currentDirectoryURL=URL(fileURLWithPath:"/var/empty")
        process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        do {
            try process.run()
            let grant=try? WorkerGrant.capture(pid:process.processIdentifier)
            return StartedPythonWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,grant:grant)
        }catch {
            try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()
            if process.isRunning {kill(process.processIdentifier,SIGKILL)}
            throw error
        }
    }
    // Synchronous compatibility for isolated direct factory fixtures only.
    // The manager broker exclusively uses beginStart/once-only result transfer.
    func start(journal:Journal,job:String,attempt:Int,binding:WorkerDispatchBinding,command:Data,now:Int64)throws->PrivateWorker {
        let started=Int64(ProcessInfo.processInfo.systemUptime*1000)
        try validate(binding,now:now)
        guard try journal.activeLaunchCount()<2 else {throw PolicyError.invalidObservation}
        try Self.verifyInvocation(invocation,executable:executable)
        let nonce=try journal.planWorkerLaunch(job:job,attempt:attempt)
        let transport=try spawnTransport(binding:binding,launchID:nonce,cancelled:{false})
        let worker=try transport.bind(journal:journal,key:WorkerLaunchKey(job:job,attempt:attempt),nonce:nonce,started:started,readyAt:Int64(ProcessInfo.processInfo.systemUptime*1000))
        try worker.enqueue(command,expectedModel:binding.nativeModel,endpointHash:binding.nativeSnapshot.endpointHash,epoch:binding.managerEpoch,now:now)
        return worker
    }
    static func digest(_ value:String)->String { SHA256.hash(data:Data(value.utf8)).map {String(format:"%02x",$0)}.joined() }
}
