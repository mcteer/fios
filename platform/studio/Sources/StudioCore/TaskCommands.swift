import Foundation
import CoreFoundation
import Darwin
import CryptoKit

enum TaskCommandError:String,Error {case native_unsupported,invalid_request,unauthorized,cleanup_pending,resource_limit,model_unavailable}

// Role-separated task RPC payloads. Owner credentials authenticate only an
// existing grant/job, never a management role. Trusted policy supplies images,
// bindings, native proof and activation; none is read from task data.
final class TaskCommands {
    private struct Upload {
        let owner:String,hash:String,kind:String
        let binding:WorkerDispatchBinding?
        var transfer:ChunkTransfer
    }
    private let journal:Journal
    private let tasks:TaskController
    private let sandbox:SandboxTaskController
    private let artifacts:AsyncArtifacts
    private let approvedImages:Set<String>
    private let enrolled:Bool
    private let admissionOpen:()->Bool
    private let peerUID:uid_t
    private var uploads:[String:Upload]=[:]
    private var mailbox=TaskMailbox()
    private var outputLost=Set<String>()
    private var outcomes:[String:SandboxTaskFinished]=[:]
    private struct Download {let owner:String;var stream:ArtifactDownload?;var failure=false;let created:Int64}
    private var downloads:[String:Download]=[:]
    init(journal:Journal,tasks:TaskController,sandbox:SandboxTaskController,artifacts:AsyncArtifacts,
         approvedImages:Set<String>,enrolled:Bool=false,peerUID:uid_t,admissionOpen:@escaping ()->Bool={false}) {
        self.journal=journal;self.tasks=tasks;self.sandbox=sandbox;self.artifacts=artifacts
        self.approvedImages=approvedImages;self.enrolled=enrolled;self.peerUID=peerUID;self.admissionOpen=admissionOpen
    }
    private func integer(_ value:Any?)->Int64? {
        guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),!["d","f"].contains(String(cString:number.objCType)),number.doubleValue>=0,number.doubleValue<=Double(ActivityPolicy.maximumTimestamp) else {return nil}
        return number.int64Value
    }
    private func owned(_ id:String,_ owner:String) throws -> DurableJob {
        guard let job=try journal.jobs().first(where:{$0.id==id}),job.ownerHash==owner else {throw TaskCommandError.unauthorized};return job
    }
    private func status(_ job:DurableJob)->[String:Any] {["job":job.id,"state":job.state.rawValue]}
    private func nonce()->String {SymmetricKey(size:.bits256).withUnsafeBytes {Data($0).map {String(format:"%02x",$0)}.joined()}}
    func handle(_ request:ControlRequest,role:ControlRole,sample:ResourceSample,admission:inout AdmissionPolicy,
                binding:(String)->WorkerDispatchBinding?,nativeCapacityProven:Bool,now:Int64,uptime:Int64) throws -> [String:Any] {
        guard role == .task,role.allows(request.operation),let token=request.payload["owner"] as? String else {throw TaskCommandError.unauthorized}
        let owner=try TaskOwner(token:token,peerUID:peerUID).hash
        let value=request.payload
        func exact(_ fields:Set<String>) throws {guard Set(value.keys)==fields.union(["owner"]) else {throw TaskCommandError.invalid_request}}
        switch request.operation {
        case .jobStatus,.jobRenew,.jobCancel:
            try exact(["job"])
            guard let id=value["job"] as? String else {throw TaskCommandError.invalid_request}
            _=try owned(id,owner)
            if request.operation == .jobRenew {try journal.renewJob(id:id,ownerHash:owner,now:now)}
            if request.operation == .jobCancel {uploads.removeValue(forKey:id);mailbox.discard(job:id);try tasks.cancel(id:id,owner:owner,now:now,uptime:uptime)}
            var result=status(try owned(id,owner))
            result["unresolved_managed_requests"]=try journal.unresolvedCount(job:id)
            if let outcome=outcomes[id] {result["code_complete"]=outcome.codeComplete;result["exit_verified"]=outcome.exitVerified}
            if outputLost.contains(id) {result["output_lost"]=true}
            if request.operation == .jobStatus {
                do {if let event=try mailbox.pop(job:id,now:now) {result["event"]=event}}
                catch {outputLost.insert(id);try tasks.cancel(id:id,owner:owner,now:now,uptime:uptime);result["output_lost"]=true}
            }
            return result
        case .jobCreate,.modelRequest:
            guard let phase=value["phase"] as? String else {throw TaskCommandError.invalid_request}
            if request.operation == .modelRequest {
                guard phase != "begin",let id=value["job"] as? String else {throw TaskCommandError.unauthorized}
                _=try owned(id,owner)
                // End replay is status-only once input was consumed, including
                // the interval between native completion and local worker reap.
                // It must never recreate an upload or dispatch another POST.
                guard uploads[id]?.kind=="model" || (phase=="end" && uploads[id]==nil),
                      try !journal.sandboxRecords().contains(where:{$0.configuration.job==id}) else {throw TaskCommandError.unauthorized}
            }
            if phase=="begin" {
                try exact(["phase","idempotency","kind","length","sha256","lifetime","model","image","memory","cpus"])
                guard let key=value["idempotency"] as? String,UUID(uuidString:key)?.uuidString.lowercased()==key,
                      let kind=value["kind"] as? String,["sandbox","model"].contains(kind),
                      let length=integer(value["length"]),length<=4<<20,let hash=value["sha256"] as? String,
                      let lifetime=integer(value["lifetime"]),(1...1800000).contains(lifetime),
                      let memory=integer(value["memory"]),let cpus=integer(value["cpus"]),cpus<=2 else {throw TaskCommandError.invalid_request}
                var canonical=value;canonical.removeValue(forKey:"owner");canonical.removeValue(forKey:"idempotency")
                let bytes=try JSONSerialization.data(withJSONObject:canonical,options:[.sortedKeys])
                let requestHash=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
                if let old=try journal.jobs().first(where:{$0.idempotency==key}) {
                    guard old.ownerHash==owner,old.requestHash==requestHash else {throw JournalError.conflict}
                    // Lost/replayed begin never resets a stream/deadline or
                    // reconstructs code after restart. Status only.
                    return status(old)
                }
                guard enrolled,admissionOpen() else {throw TaskCommandError.native_unsupported}
                guard uploads.count<4 else {throw TaskCommandError.resource_limit}
                let model:WorkerDispatchBinding?
                if let name=value["model"] as? String {
                    guard let allowed=binding(name),WireScalar.exactModel(allowed.canonicalModel,name),allowed.nativeCompatibilityAccepted else {throw TaskCommandError.model_unavailable}
                    model=allowed
                } else {guard value["model"] is NSNull else {throw TaskCommandError.invalid_request};model=nil}
                let transfer=try ChunkTransfer(length:Int(length),sha256:hash,created:now,kind:.input)
                let job:DurableJob
                if kind=="model" {
                    guard let model,value["image"] is NSNull,memory==0,cpus==0 else {throw TaskCommandError.invalid_request}
                    job=try tasks.reserveModelUpload(owner:owner,idempotency:key,requestHash:requestHash,binding:model,nativeCapacityProven:nativeCapacityProven,lifetime:lifetime,sample:sample,admission:&admission,now:now)
                } else {
                    guard let image=value["image"] as? String,approvedImages.contains(image) else {throw TaskCommandError.invalid_request}
                    try ModelBroker.restoreReservations(journal:journal,admission:&admission)
                    let id=UUID().uuidString.lowercased()
                    let config=try SandboxConfiguration(job:id,nonce:nonce(),image:image,memory:UInt64(memory),cpus:Int(cpus))
                    try admission.reserve(job:id,memory:config.memory,cpus:config.cpus,sample:sample,now:now)
                    let proposed=try DurableJob(id:id,idempotency:key,ownerHash:owner,requestHash:requestHash,created:now,lifetime:lifetime)
                    do {_=try journal.reserveSandbox(job:proposed,configuration:config);job=proposed}
                    catch {
                        if try !journal.sandboxRecords().contains(where:{$0.configuration.job==id}) {admission.releaseProvenAbsent(job:id)}
                        throw error
                    }
                }
                uploads[job.id]=Upload(owner:owner,hash:requestHash,kind:kind,binding:model,transfer:transfer)
                return status(job)
            }
            guard phase=="chunk" || phase=="end",let id=value["job"] as? String else {throw TaskCommandError.invalid_request}
            let job=try owned(id,owner)
            guard var upload=uploads[id],upload.owner==owner else {
                if phase=="end" {try exact(["phase","job"]);return status(job)}
                throw TaskCommandError.invalid_request
            }
            do {
                var lease=job.lease;guard lease.valid(now:now) else {throw AdmissionError.expired}
                if phase=="chunk" {
                    try exact(["phase","job","index","data"])
                    guard let index=integer(value["index"]),let data=value["data"] as? String else {throw TaskCommandError.invalid_request}
                    try upload.transfer.append(index:Int(index),base64:data,now:now);uploads[id]=upload
                } else {
                    try exact(["phase","job"])
                    // Admission can close while an input stream is in flight.
                    // Recheck before consuming input/registering any execution;
                    // the catch path revokes without proving native absence.
                    guard enrolled,admissionOpen() else {throw TaskCommandError.native_unsupported}
                    let data=try upload.transfer.finish(now:now);uploads.removeValue(forKey:id)
                    if upload.kind=="sandbox" {
                        let digest=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
                        try sandbox.register(id:id,owner:owner,source:data,inputSHA256:digest,binding:upload.binding,now:now)
                    } else {
                        try StrictJSON.validate(data,maximum:4<<20)
                        guard let context=try JSONSerialization.jsonObject(with:data) as? [[String:Any]],context.count<=1024,
                              let canonical=upload.binding?.canonicalModel,let current=binding(canonical),
                              current.profileHash==upload.binding?.profileHash,WireScalar.exactModel(current.nativeModel,upload.binding?.nativeModel),
                              current.host==upload.binding?.host,current.nativeSnapshot.endpointHash==upload.binding?.nativeSnapshot.endpointHash else {throw TaskCommandError.invalid_request}
                        let messages=try context.map {item -> ModelText in
                            guard Set(item.keys)==Set(["role","content"]),let role=item["role"] as? String,let content=item["content"] as? String else {throw TaskCommandError.invalid_request}
                            return ModelText(role:role,content:content)
                        }
                        _=try tasks.startModelUpload(id:id,owner:owner,requestHash:upload.hash,requestID:request.id,context:messages,binding:current,nativeCapacityProven:nativeCapacityProven,sample:sample,admission:&admission,now:now)
                    }
                }
                return status(try owned(id,owner))
            } catch {
                uploads.removeValue(forKey:id)
                try tasks.cancel(id:id,owner:owner,now:now,uptime:uptime)
                throw error
            }
        case .artifactRead:
            guard let phase=value["phase"] as? String else {throw TaskCommandError.invalid_request}
            if phase=="begin" {
                try exact(["phase","artifact"])
                guard let id=value["artifact"] as? String,UUID(uuidString:id)?.uuidString.lowercased()==id else {throw TaskCommandError.invalid_request}
                guard downloads.count<2,downloads[request.id]==nil else {throw TaskCommandError.resource_limit}
                try artifacts.download(request:request.id,id:id,owner:owner,now:now)
                downloads[request.id]=Download(owner:owner,created:now)
                return ["stream":request.id,"state":"pending"]
            }
            try exact(["phase","stream"])
            guard phase=="next",let id=value["stream"] as? String,var download=downloads[id],download.owner==owner else {throw TaskCommandError.unauthorized}
            guard !download.failure,now>=download.created,now-download.created<30000 else {downloads.removeValue(forKey:id);throw ArtifactError.unavailable}
            guard var stream=download.stream else {return ["stream":id,"state":"pending"]}
            let event:ArtifactDownloadEvent
            do {event=try stream.next(now:now)}
            catch {downloads.removeValue(forKey:id);throw error}
            download.stream=stream;downloads[id]=download
            switch event {
            case .begin(let artifact,let length,let hash):return ["stream":id,"type":"begin","artifact":artifact,"length":length,"sha256":hash]
            case .chunk(let index,let data):return ["stream":id,"type":"chunk","index":index,"data":data]
            case .end:downloads.removeValue(forKey:id);return ["stream":id,"type":"end"]
            }
        default:throw TaskCommandError.unauthorized
        }
    }
    func tick(now:Int64,uptime:Int64,artifactResults:[ArtifactServiceResult],output:[SandboxTaskOutput]=[],model:[String:[ModelWorkerEvent]]=[:],finished:[SandboxTaskFinished]=[]) throws {
        let allJobs=try journal.jobs()
        let retained=Set(allJobs.map(\.id));outputLost.formIntersection(retained)
        outcomes=outcomes.filter {retained.contains($0.key)}
        for result in finished where retained.contains(result.job) {outcomes[result.job]=result}
        var rejected=Set(mailbox.expire(now:now,retained:retained))
        for item in output where !outputLost.contains(item.job) && !rejected.contains(item.job) {
            do {try mailbox.append(job:item.job,fields:["type":"output","stream":item.stream,"data":item.data.base64EncodedString()],now:now)}
            catch {rejected.insert(item.job);mailbox.discard(job:item.job)}
        }
        for (id,events) in model where !outputLost.contains(id) {
            for event in events {
                if rejected.contains(id) {break}
                let fields:[String:Any]
                switch event {
                case .text(let kind,let content):fields=["type":"model.text","kind":kind,"content":content]
                case .complete:fields=["type":"model.done","status":"complete"]
                case .failed:fields=["type":"model.done","status":"failed"]
                case .interrupted:fields=["type":"model.done","status":"interrupted"]
                case .usage,.dispatched,.activity:continue
                }
                do {try mailbox.append(job:id,fields:fields,now:now)}
                catch {rejected.insert(id);mailbox.discard(job:id)}
            }
        }
        for id in rejected {
            outputLost.insert(id);mailbox.discard(job:id)
            if let job=allJobs.first(where:{$0.id==id}) {try tasks.cancel(id:id,owner:job.ownerHash,now:now,uptime:uptime)}
        }
        for id in Array(uploads.keys) {
            guard var upload=uploads[id] else {continue}
            do {try upload.transfer.validate(now:now);uploads[id]=upload}
            catch {uploads.removeValue(forKey:id);try tasks.cancel(id:id,owner:upload.owner,now:now,uptime:uptime)}
        }
        for result in artifactResults {
            guard var download=downloads[result.request] else {continue}
            if case .success(.download(let stream))=result.result {download.stream=stream}
            else {download.failure=true}
            downloads[result.request]=download
        }
        for id in Array(downloads.keys) {
            if let stream=downloads[id],now<stream.created || now-stream.created>=30000 {downloads.removeValue(forKey:id)}
        }
    }
}
