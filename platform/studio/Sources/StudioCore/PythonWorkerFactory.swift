import Foundation
import Darwin
import CryptoKit

struct WorkerMetadata:Decodable,Sendable {
    let version:Int
    let pipe_version:Int
    let native_handoff_version:Int
    let native_preparation_version:Int?
    let package_version:String
    let python_version:String
    let policy_sha256:String
    let policy_input_units:Int
    static func decode(_ bytes:Data,policySHA256:String,packageVersion:String="0.1.0")throws->Self {
        try StrictJSON.validate(bytes,maximum:4096)
        guard let object=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              let version=WireScalar.integer(object["version"]),[2,3].contains(version) else {throw RuntimeError.identity}
        let base:Set<String>=["version","pipe_version","native_handoff_version","package_version","python_version","policy_sha256","policy_input_units"]
        guard Set(object.keys)==(version==3 ? base.union(["native_preparation_version"]):base),
              ["pipe_version","native_handoff_version","policy_input_units"].allSatisfy({WireScalar.integer(object[$0]) != nil}),
              version != 3 || WireScalar.integer(object["native_preparation_version"])==1 else {throw RuntimeError.identity}
        let value=try JSONDecoder().decode(Self.self,from:bytes)
        guard value.pipe_version==1,value.native_handoff_version==1,
              value.package_version==packageVersion,value.python_version=="3.11.17",value.policy_sha256==policySHA256,
              (1...128000).contains(value.policy_input_units) else {throw RuntimeError.identity}
        return value
    }
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

// No public/memberwise initializer: only the live factory's pre-spawn
// cancellation/withdrawal branch can attest that its plan created no process.
struct WorkerNeverSpawnedEvidence:Sendable {
    let plan:PlannedWorkerStart
    let handoff:WorkerHandoffBinding?
    let preparation:WorkerPreparationBinding?
    fileprivate init(plan:PlannedWorkerStart,handoff:WorkerHandoffBinding?=nil,preparation:WorkerPreparationBinding?=nil) {
        self.plan=plan;self.handoff=handoff;self.preparation=preparation
    }
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
        let bytes=try Self.probe(invocation:invocation,executable:executable)
        metadata=try WorkerMetadata.decode(bytes,policySHA256:policySHA256,packageVersion:packageVersion)
    }
    private static func verifyInvocation(_ path:String,executable:VerifiedExecutable) throws {
        var info=stat()
        guard lstat(path,&info)==0,info.st_uid==0 || info.st_uid==geteuid(),
              [S_IFREG,S_IFLNK].contains(info.st_mode & S_IFMT),
              (info.st_mode & S_IFMT == S_IFLNK || info.st_mode & 0o022==0),
              URL(fileURLWithPath:path).resolvingSymlinksInPath().path==executable.path else { throw RuntimeError.identity }
        try executable.verify()
    }
    private static func probe(invocation:String,executable:VerifiedExecutable) throws -> Data {
        let result=try executable.platformWorkerMetadata(invocation:invocation)
        guard result.status==0 else {throw RuntimeError.identity}
        return result.output
    }
    // Pure binding validation. Binary verification/spawn occur off-loop for
    // broker starts; no journal, caller argv or permission bytes enter work.
    private func validate(_ binding:WorkerDispatchBinding,now:Int64)throws {
        guard binding.profileHash.utf8.count==64,binding.profileHash.utf8.allSatisfy({ (48...57).contains($0)||(97...102).contains($0) }),
              UUID(uuidString:binding.managerEpoch)?.uuidString.lowercased()==binding.managerEpoch,
              binding.guardPath.hasPrefix("/"),binding.guardPath.hasSuffix("/observe.sock"),
              try NativeAdmission.permitsDispatch(binding,now:now) else { throw PolicyError.invalidObservation }
        let components=URLComponents(string:binding.baseURL)
        guard components?.scheme=="http",["127.0.0.1","::1","[::1]"].contains(components?.host ?? ""),
              components?.path=="/v1",components?.user==nil,components?.password==nil,
              components?.query==nil,components?.fragment==nil else { throw RuntimeError.identity }
    }
    func beginStart(binding:WorkerDispatchBinding,plan:PlannedWorkerStart,started:Int64,now:Int64,initiallyCancelled:Bool=false,handoff:WorkerHandoffBinding?=nil)throws->PendingPythonWorker {
        try validate(binding,now:now)
        guard WireScalar.uuid(plan.nonce),started>=0,started<=ActivityPolicy.maximumTimestamp-2000 else {throw RuntimeError.invalid}
        try handoff?.validateForLaunch(plan:plan,scope:binding.inferenceScope())
        guard try plan.scope.encoded()==binding.inferenceScope().encoded(),plan.consume() else {throw RuntimeError.identity}
        return PendingPythonWorker(initiallyCancelled:initiallyCancelled) { [self] cancelled in
            do {return .success(try spawnTransport(binding:binding,launchID:plan.nonce,handoff:handoff,cancelled:cancelled))}
            catch WorkerStartFailure.cancelled {return .failure(.neverSpawned(WorkerNeverSpawnedEvidence(plan:plan,handoff:handoff)))}
            catch {return .failure(.unavailable)}
        }
    }
    func beginPreparationStart(binding:WorkerDispatchBinding,plan:PlannedWorkerStart,preparation:WorkerPreparationBinding,
                               observation:NativePreparationObservation,journal:Journal,started:Int64,now:Int64,initiallyCancelled:Bool=false)throws->PendingPythonWorker {
        guard metadata.native_preparation_version==1 else {throw RuntimeError.identity}
        try validate(binding,now:now)
        guard WireScalar.uuid(plan.nonce),started>=0,started<=ActivityPolicy.maximumTimestamp-2000 else {throw RuntimeError.invalid}
        let scope=try binding.inferenceScope()
        try preparation.validate(plan:plan,scope:scope,journal:journal,now:now)
        let subject=try NativePreparationSubject(payload:["job_id":plan.job,"attempt":plan.attempt,"root_sequence":String(preparation.rootSequence),"correlation_id":preparation.correlationID])
        _=try observation.encoded(subject:subject,managerEpoch:binding.managerEpoch,journal:journal,now:now)
        guard try plan.scope.encoded()==scope.encoded(),plan.consume() else {throw RuntimeError.identity}
        return PendingPythonWorker(initiallyCancelled:initiallyCancelled) { [self] cancelled in
            do {return .success(try spawnTransport(binding:binding,launchID:plan.nonce,preparation:preparation,cancelled:cancelled))}
            catch WorkerStartFailure.cancelled {return .failure(.neverSpawned(WorkerNeverSpawnedEvidence(plan:plan,preparation:preparation)))}
            catch {return .failure(.unavailable)}
        }
    }
    // Local plan only: no native withdrawal or native terminal claim.
    func withdrawUnstartedPreparation(plan:PlannedWorkerStart,preparation:WorkerPreparationBinding)throws->WorkerNeverSpawnedEvidence {
        try preparation.validateIdentity(plan:plan,scope:plan.scope)
        guard WireScalar.uuid(plan.nonce),plan.consume() else {throw RuntimeError.identity}
        return WorkerNeverSpawnedEvidence(plan:plan,preparation:preparation)
    }
    // Consume only an original, still-unused plan. This executes no process,
    // refreshes no permission and needs no live model-admission observation.
    // A native registration requires paired native cancellation separately.
    func withdrawUnstarted(plan:PlannedWorkerStart,handoff:WorkerHandoffBinding)throws->WorkerNeverSpawnedEvidence {
        try plan.scope.validate()
        try handoff.validate(plan:plan,scope:plan.scope)
        guard WireScalar.uuid(plan.nonce),plan.consume() else {throw RuntimeError.identity}
        return WorkerNeverSpawnedEvidence(plan:plan,handoff:handoff)
    }
    private func spawnTransport(binding:WorkerDispatchBinding,launchID:String,handoff:WorkerHandoffBinding?=nil,preparation:WorkerPreparationBinding?=nil,cancelled:@Sendable ()->Bool)throws->StartedPythonWorker {
        guard !cancelled() else {throw WorkerStartFailure.cancelled}
        try Self.verifyInvocation(invocation,executable:executable)
        guard !cancelled() else {throw WorkerStartFailure.cancelled}
        guard handoff == nil || preparation == nil else {throw RuntimeError.identity}
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
        if let handoff {
            env["FIOS_PLATFORM_HANDOFF_ROOT"]=String(handoff.rootSequence)
            env["FIOS_PLATFORM_HANDOFF_CORRELATION"]=handoff.correlationID
        }
        if let preparation {
            env["FIOS_PLATFORM_PREPARATION_ROOT"]=String(preparation.rootSequence)
            env["FIOS_PLATFORM_PREPARATION_CORRELATION"]=preparation.correlationID
        }
        process.executableURL=URL(fileURLWithPath:invocation);process.arguments=Self.arguments
        process.environment=env;process.currentDirectoryURL=URL(fileURLWithPath:"/var/empty")
        process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        do {
            try process.run()
            let grant=try? WorkerGrant.capture(pid:process.processIdentifier)
            return StartedPythonWorker(process:process,input:input.fileHandleForWriting,output:output.fileHandleForReading,grant:grant,handoff:handoff,preparation:preparation)
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
