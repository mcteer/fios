import Foundation
import Darwin
import CryptoKit

struct SandboxTaskOutput {let job:String;let stream:String;let data:Data}
struct SandboxTaskFinished {let job:String;let codeComplete:Bool;let exitVerified:Bool}
struct SandboxTaskUpdates {
    var output:[SandboxTaskOutput]=[]
    var model:[String:[ModelWorkerEvent]]=[:]
    var finished:[SandboxTaskFinished]=[]
    var artifactResults:[ArtifactServiceResult]=[]
}

// Trusted serialized composition. Public admission/upload and reviewed host
// enrollment precede register; neither sandbox frames nor model text can call
// register or select runtime/model policy. No automatic task restart/resume.
final class SandboxTaskController {
    private struct Session {
        let owner:String
        let binding:WorkerDispatchBinding?
        let stream:SandboxTaskSession
        var attach:DockerAttach?
        var modelRegistered=false
        var renewed:Int64
        var codeComplete=false
    }
    private let journal:Journal
    private let jobs:JobController
    private let tasks:TaskController
    private let artifacts:AsyncArtifacts
    private let socket:String
    private let endpointPolicy:RuntimeEndpointPolicy?
    private let peerUID:uid_t
    private var sessions:[String:Session]=[:]
    private var pendingExports:[String:(job:String,id:String)]=[:]
    init(journal:Journal,jobs:JobController,tasks:TaskController,artifacts:AsyncArtifacts,socket:String,peerUID:uid_t,endpointPolicy:RuntimeEndpointPolicy?=nil) {
        self.journal=journal;self.jobs=jobs;self.tasks=tasks;self.artifacts=artifacts;self.socket=socket;self.peerUID=peerUID;self.endpointPolicy=endpointPolicy
    }
    func register(id:String,owner:String,source:Data,inputSHA256:String,binding:WorkerDispatchBinding?,now:Int64) throws {
        guard source.count<=4<<20,sessions.count<2,sessions[id]==nil,
              let job=try journal.jobs().first(where:{$0.id==id}),job.ownerHash==owner,[.reserved,.creating].contains(job.state),
              let record=try journal.sandboxRecords().first(where:{$0.configuration.job==id}),!record.startIssued,!record.removalProven,
              SHA256.hash(data:source).map({String(format:"%02x",$0)}).joined()==inputSHA256 else {throw ControlError.unauthorized}
        sessions[id]=Session(owner:owner,binding:binding,stream:try SandboxTaskSession(source:source,deadline:job.lease.deadline,now:now),renewed:now)
    }
    private func revoke(id:String,now:Int64,uptime:Int64) throws {
        if let session=sessions[id],let attach=session.attach {session.stream.revoke(attach:attach)}
        if let job=try journal.jobs().first(where:{$0.id==id}),![.revoking,.stopping,.removing,.removed].contains(job.state),let session=sessions[id] {
            try tasks.cancel(id:id,owner:session.owner,now:now,uptime:uptime)
        }
    }
    func tick(now:Int64,uptime:TimeInterval,sample:ResourceSample,admission:inout AdmissionPolicy,
              source:(String)->WorkerDispatchBinding?,nativeCapacityProven:Bool) throws -> SandboxTaskUpdates {
        guard uptime.isFinite,uptime>=0,uptime<Double(Int64.max/1000) else {throw ControlError.invalid_request}
        let clock=Int64(uptime*1000)
        var updates=SandboxTaskUpdates()
        for result in artifacts.drain() {
            guard let export=pendingExports.removeValue(forKey:result.request) else {updates.artifactResults.append(result);continue}
            switch result.result {
            case .success(.published(let id)):
                do {try sessions[export.job]?.stream.saved(id:export.id,artifactID:id)}
                catch {try revoke(id:export.job,now:now,uptime:clock)}
            default:try revoke(id:export.job,now:now,uptime:clock)
            }
        }
        let events=try tasks.tick(now:now,uptime:clock,admission:&admission,source:source)
        let sandboxIDs=Set(try journal.sandboxRecords().map(\.configuration.job))
        updates.model=events.filter {!sandboxIDs.contains($0.key)}
        for (id,frames) in try tasks.sandboxModelData(events) {
            guard let session=sessions[id],!session.stream.terminal,!session.stream.revoked else {continue}
            do {for frame in frames {try session.stream.response(frame)}}
            catch {try revoke(id:id,now:now,uptime:clock)}
        }
        for id in Array(sessions.keys) {
            guard var session=sessions[id],let job=try journal.jobs().first(where:{$0.id==id}),
                  let record=try journal.sandboxRecords().first(where:{$0.configuration.job==id}) else {throw JournalError.storage}
            if job.state == .removed {
                // Local cleanup proof is not native inference completion.
                if !pendingExports.values.contains(where:{$0.job==id}) {
                    updates.finished.append(SandboxTaskFinished(job:id,codeComplete:session.codeComplete,exitVerified:jobs.exitProof[id]==true))
                    session.attach?.close();sessions.removeValue(forKey:id)
                }
                continue
            }
            if [.revoking,.stopping,.removing,.reconciling].contains(job.state) {
                if let attach=session.attach {session.stream.revoke(attach:attach)}
                continue
            }
            do {
                if session.attach==nil,let runtimeID=record.runtimeID {
                    session.attach=try DockerAttach(socketPath:socket,configuration:record.configuration,savedID:runtimeID,peerUID:peerUID,now:uptime,endpointPolicy:endpointPolicy)
                }
                guard let attach=session.attach else {continue}
                if job.state == .running,!session.modelRegistered,let binding=session.binding {
                    try tasks.registerSandbox(id:id,owner:session.owner,runtimeID:record.runtimeID ?? "",binding:binding)
                    session.modelRegistered=true
                }
                if now-session.renewed>=10000,!session.stream.terminal,session.stream.uploaded {
                    var lease=job.lease
                    guard lease.valid(now:now) else {throw AdmissionError.expired}
                    try session.stream.renew();session.renewed=now
                }
                // Persist only controller metadata before handling callbacks;
                // code/output never becomes a lifecycle operation/host tool.
                sessions[id]=session
                for event in try session.stream.poll(attach:attach,started:job.state == .running,now:now,uptime:uptime) {
                    switch event {
                    case .model(let data):
                        guard session.modelRegistered,let binding=source(id),let runtimeID=record.runtimeID else {throw ControlError.unauthorized}
                        try tasks.sandboxModelFrame(id:id,runtimeID:runtimeID,data:data,binding:binding,nativeCapacityProven:nativeCapacityProven,sample:sample,admission:&admission,now:now,uptime:clock)
                    case .output(let stream,_,let data):updates.output.append(SandboxTaskOutput(job:id,stream:stream,data:data))
                    case .artifact(let exportID,let bytes):
                        guard pendingExports.count<2 else {throw ArtifactServiceFailure.capacity}
                        let request=UUID().uuidString.lowercased()
                        try artifacts.publish(request:request,job:id,owner:session.owner,data:bytes,now:now)
                        pendingExports[request]=(id,exportID)
                    case .done(let success):
                        session.codeComplete=success;sessions[id]=session
                        try tasks.cancel(id:id,owner:session.owner,now:now,uptime:clock)
                    case .revoked:try revoke(id:id,now:now,uptime:clock)
                    }
                }
            } catch {try revoke(id:id,now:now,uptime:clock)}
        }
        try jobs.tick(now:now,sample:sample,admission:&admission,transportReady:{id in self.sessions[id]?.attach?.ready==true},cancelModel:{id in
            if let job=try self.journal.jobs().first(where:{$0.id==id}) {try self.tasks.cancel(id:id,owner:job.ownerHash,now:now,uptime:clock)}
        })
        return updates
    }
}
