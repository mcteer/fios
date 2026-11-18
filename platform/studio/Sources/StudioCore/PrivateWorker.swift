import Foundation
import Darwin
import CoreFoundation

// Owns one already-launched, approved private Pydantic child. Factories must
// reserve512MiB and durable ownership BEFORE launching; no task supplies argv.
// Poll only from the serialized manager. No workload data enters the journal.
struct WorkerZeroPostEvidence:Sendable {
    let handoff:WorkerHandoffBinding
    let grant:WorkerGrant
    let workerMetadataVersion:Int
    fileprivate init(handoff:WorkerHandoffBinding,grant:WorkerGrant,workerMetadataVersion:Int) {self.handoff=handoff;self.grant=grant;self.workerMetadataVersion=workerMetadataVersion}
}
// Only the live, checked fixed worker can construct this local certificate.
// It is not a native close, completion, capacity or all-client observation.
struct WorkerPreparationZeroPostEvidence:Sendable {
    let preparation:WorkerPreparationBinding
    let grant:WorkerGrant
    let workerMetadataVersion:Int
    fileprivate init(preparation:WorkerPreparationBinding,grant:WorkerGrant,workerMetadataVersion:Int) {
        self.preparation=preparation;self.grant=grant;self.workerMetadataVersion=workerMetadataVersion
    }
}
final class PrivateWorker {
    private let process:Process
    private let input:FileHandle
    private let output:FileHandle
    private let journal:Journal
    private let grant:WorkerGrant
    private let job:String
    private let attempt:Int
    private let inferenceScope:InferenceScope?
    private let nativeHandoff:WorkerHandoffBinding?
    private let nativePreparation:WorkerPreparationBinding?
    private let workerMetadataVersion:Int?
    private var parser:ModelWorkerProtocol
    private var memory:WorkerMemoryGuard
    private let started:Int64
    private var lastSample:Int64
    private var lastPoll:Int64
    private var protocolBroken=false
    private var outgoing=Data(),sent=0,buffer=Data()
    private var commandAccepted=false
    private var totalRead=0
    private var eof=false,revoked=false,terminal=false,nativeComplete=false
    private var cancelAt:Int64?
    private var actualPosts:Int?
    private var dispatchRecorded=false
    private var ownsTransport=false
    private(set) var reaped=false
    private(set) var zeroPostEvidence:WorkerZeroPostEvidence?
    private(set) var zeroPostPreparationEvidence:WorkerPreparationZeroPostEvidence?
    private(set) var memorySamples=0
    var outputEOFObserved:Bool {eof}

    init(process:Process,input:FileHandle,output:FileHandle,journal:Journal,job:String,attempt:Int,started:Int64,readyAt:Int64?=nil,capturedGrant:WorkerGrant?=nil,launchNonce:String?=nil,nativeHandoff:WorkerHandoffBinding?=nil,nativePreparation:WorkerPreparationBinding?=nil,workerMetadataVersion:Int?=nil) throws {
        self.workerMetadataVersion=workerMetadataVersion
        guard process.processIdentifier>1,try journal.hasClaim(job:job,attempt:attempt) else { throw JournalError.invalid }
        grant=try capturedGrant ?? WorkerGrant.capture(pid:process.processIdentifier)
        guard grant.pid==process.processIdentifier else {throw RuntimeError.identity}
        self.process=process;self.input=input;self.output=output;self.journal=journal;self.job=job;self.attempt=attempt
        inferenceScope=try journal.inferenceScope(job:job,attempt:attempt)?.scope
        guard nativeHandoff == nil || nativePreparation == nil else {throw RuntimeError.identity}
        self.nativeHandoff=nativeHandoff;self.nativePreparation=nativePreparation
        if let nativeHandoff {
            guard let inferenceScope else {throw RuntimeError.identity}
            try nativeHandoff.validate(job:job,attempt:attempt,scope:inferenceScope)
            guard try journal.originalNativeRoot(job:job,attempt:attempt,scope:inferenceScope,peer:nativeHandoff.peer)==nativeHandoff.rootSequence else {throw RuntimeError.identity}
        }
        if let nativePreparation {
            guard let inferenceScope else {throw RuntimeError.identity}
            try nativePreparation.validateIdentity(job:job,attempt:attempt,scope:inferenceScope)
            guard try journal.originalNativeRoot(job:job,attempt:attempt,scope:inferenceScope,peer:nativePreparation.peer)==nativePreparation.rootSequence else {throw RuntimeError.identity}
        }
        let observed=readyAt ?? started
        guard observed>=started else {throw RuntimeError.invalid}
        parser=ModelWorkerProtocol(job:job,attempt:attempt);memory=try WorkerMemoryGuard(started:observed)
        self.started=started;lastSample=observed;lastPoll=observed
        guard fcntl(input.fileDescriptor,F_SETFL,O_NONBLOCK)>=0,
              fcntl(input.fileDescriptor,F_SETNOSIGPIPE,1)>=0,
              fcntl(output.fileDescriptor,F_SETFL,O_NONBLOCK)>=0 else { throw RuntimeError.launch }
        try journal.bindWorker(job:job,attempt:attempt,grant:grant,nonce:launchNonce)
        ownsTransport=true
    }
    deinit {
        // Until durable binding succeeds, StartedPythonWorker remains the
        // lexical owner. A failed initializer must not destroy its pipes.
        guard ownsTransport else {return}
        signalOwned(SIGKILL)
        try? input.close();try? output.close()
        // Durable ownership is intentionally not released by destruction.
    }
    static let maximumCommandBytes=1<<20
    func enqueue(_ command:Data,expectedModel:String,endpointHash:String,epoch:String,now:Int64) throws {
        guard !commandAccepted,!revoked,command.count<=Self.maximumCommandBytes else { throw ControlError.invalid_request }
        try StrictJSON.validate(command,maximum:Self.maximumCommandBytes)
        guard let value=try JSONSerialization.jsonObject(with:command) as? [String:Any] else { throw ControlError.invalid_request }
        func integer(_ key:String)->Int64? {
            guard let number=value[key] as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["d","f"].contains(String(cString:number.objCType)),number.int64Value>=0,
                  number.int64Value<=ActivityPolicy.maximumTimestamp else { return nil };return number.int64Value
        }
        guard (0...ActivityPolicy.maximumTimestamp).contains(now),
              Set(value.keys)==Set(["v","type","job_id","attempt","model","endpoint_hash","epoch","expires_at","context"]),
              integer("v")==1,value["type"] as? String=="run",UUID(uuidString:epoch)?.uuidString.lowercased()==epoch,
              value["job_id"] as? String==job,integer("attempt")==Int64(attempt),
              WireScalar.exactModel(value["model"] as? String,expectedModel),value["endpoint_hash"] as? String==endpointHash,
              value["epoch"] as? String==epoch,let expiry=integer("expires_at"),
              expiry>now,expiry-now<=5000 else { throw ControlError.invalid_request }
        if let inferenceScope {
            let state=try journal.inferenceScope(job:job,attempt:attempt)?.state
            if nativeHandoff != nil || nativePreparation != nil {
                guard state == .dispatched else {throw ControlError.invalid_request}
                dispatchRecorded=true // Native identity was durably bound before this launch.
            } else {guard state == .reserved else {throw ControlError.invalid_request}}
            guard WireScalar.exactModel(inferenceScope.nativeModel,expectedModel),
                  inferenceScope.endpointHash==endpointHash,inferenceScope.managerEpoch==epoch else {throw ControlError.invalid_request}
        }
        let size=UInt32(command.count)
        outgoing=Data([UInt8(size>>24),UInt8((size>>16)&255),UInt8((size>>8)&255),UInt8(size&255)])
        outgoing.append(command);commandAccepted=true
    }
    private func signalOwned(_ signal:Int32) {
        guard process.isRunning,(try? HostBoot.identity())==grant.boot,
              (try? WorkerResources.startIdentifier(pid:grant.pid))==grant.start else {return}
        kill(grant.pid,signal)
    }
    func cancel(now:Int64,immediate:Bool=false) throws {
        if revoked {if immediate {signalOwned(SIGKILL)};return}
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else { throw WorkerResourceError.invalid }
        revoked=true;cancelAt=now;outgoing.removeAll();sent=0
        // Claim and launch ownership are already durable. Signal before
        // potentially slow journal I/O; failure retains the unresolved row.
        // Neither signal nor local reap supplies native completion proof.
        signalOwned(immediate ? SIGKILL:SIGTERM)
        try? input.close()
        if !nativeComplete { try retainNativeUncertainty() }
    }
    private func retainNativeUncertainty()throws {
        if let inferenceScope,let record=try journal.inferenceScope(job:job,attempt:attempt) {
            guard try record.scope.encoded()==inferenceScope.encoded() else {throw JournalError.conflict}
            if [.complete,.not_sent].contains(record.state) {nativeComplete=true;return}
        }
        try journal.markUncertain(job:job,attempt:attempt)
    }
    private func resolve(_ outcome:InferenceState) throws {
        if nativeHandoff != nil || nativePreparation != nil {
            // A zero-POST/local child outcome does not close the independently
            // registered native parent. Keep its claim for native reconciliation.
            try retainNativeUncertainty();return
        }
        if let inferenceScope {
            try journal.resolveInference(job:job,attempt:attempt,scope:inferenceScope,outcome:outcome)
        }else {
            // Unbound claims exist only in the separate low-level fixtures.
            // The composed ModelBroker always supplies persistent scope.
            try journal.complete(job:job,attempt:attempt)
        }
        nativeComplete=true
    }
    func poll(now:Int64,authorized:Bool) throws -> [ModelWorkerEvent] {
        guard !reaped else { return [] }
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else { try cancel(now:started);throw WorkerResourceError.invalid }
        if now<lastPoll {
            try cancel(now:now,immediate:true)
        }
        lastPoll=max(lastPoll,now)
        if !authorized || now<started || now-started>=180000 { try cancel(now:now) }
        if process.isRunning && (memorySamples==0 || now-lastSample>=1000) {
            let resident=try? WorkerResources.residentBytes(pid:process.processIdentifier)
            let action=try memory.observe(resident:resident,now:now);lastSample=now;memorySamples+=1
            let oversized=resident.map {$0>512<<20} ?? false
            if action != .continueRunning {
                try cancel(now:now,immediate:oversized || action == .kill || action == .cleanupOverdue)
            }
        }
        // Ordinary cancellation keeps0.5s TERM grace. A hard RSS breach
        // kills immediately, leaving the2s budget for exact local reap and
        // durable acknowledgement. Native uncertainty remains independent.
        if let cancelAt,now-cancelAt>=500,process.isRunning {signalOwned(SIGKILL)}
        if !revoked && sent<outgoing.count {
            if now-started>=10000 { try cancel(now:now) }
            else {
                if !dispatchRecorded {
                    if inferenceScope != nil {try journal.markDispatched(job:job,attempt:attempt)}
                    dispatchRecorded=true
                }
                let count=outgoing.withUnsafeBytes { Darwin.write(input.fileDescriptor,$0.baseAddress!.advanced(by:sent),$0.count-sent) }
                if count>0 {
                    sent+=count
                    if sent==outgoing.count { outgoing.removeAll();sent=0 }
                }
                else if count<0 && errno != EAGAIN && errno != EINTR { try cancel(now:now) }
            }
        }
        var bytes=[UInt8](repeating:0,count:65536)
        let count=Darwin.read(output.fileDescriptor,&bytes,bytes.count)
        if count>0 {
            totalRead+=count
            guard totalRead<=8<<20,buffer.count+count<=512<<10 else { try cancel(now:now);throw RuntimeError.outputLimit }
            buffer.append(contentsOf:bytes.prefix(count))
        } else if count==0 { eof=true }
        else if errno != EAGAIN && errno != EINTR { try cancel(now:now);eof=true }
        var events:[ModelWorkerEvent]=[]
        var handled=0
        do {
            if protocolBroken { buffer.removeAll() }
            while buffer.count>=4 && handled<64 {
                handled+=1
                let length=buffer.prefix(4).reduce(0){($0<<8)|Int($1)}
                guard length>0,length<=256<<10 else { throw ModelProtocolError.invalid }
                if buffer.count<length+4 { break }
                let event=try parser.accept(buffer.subdata(in:4..<length+4));buffer=Data(buffer.dropFirst(length+4))
                switch event {
                case .complete:
                    terminal=true
                    if !revoked {
                        if inferenceScope != nil {
                            // HTTP/Pydantic completion supplies output, not a
                            // correlated native/device terminal receipt.
                            try retainNativeUncertainty()
                        }else {
                            // Separate unbound low-level protocol fixtures.
                            try resolve(.complete)
                        }
                        events.append(event)
                    }
                case .interrupted,.failed:
                    terminal=true
                    if !nativeComplete { try retainNativeUncertainty() }
                    events.append(event)
                case .text:
                    if !revoked { events.append(event) }
                case .usage(let posts,_):actualPosts=posts;events.append(event)
                default:events.append(event)
                }
            }
            if eof && !buffer.isEmpty && handled<64 { throw ModelProtocolError.invalid }
        } catch { protocolBroken=true;buffer.removeAll();try cancel(now:now);throw error }
        // Terminal output is not permission to retain a dangling private
        // child. Bound its cleanup independently of native ownership proof.
        if terminal && !revoked { try cancel(now:now) }
        if eof && !process.isRunning {
            // Never block the serialized manager on Foundation exit delivery.
            // Missing kernel proof retains the slot; publish local reap only
            // after the exact absence check and durable marker both succeed.
            guard (try? grant.provenGone())==true else {return events}
            try journal.recordWorkerGone(job:job,attempt:attempt,grant:grant)
            reaped=true
            // This supplies the local no-POST input only. A registered native
            // root additionally requires its exact unconsumed cancellation;
            // neither child exit nor this summary releases that native hold.
            if !protocolBroken && terminal && actualPosts==0 && !nativeComplete {
                if let nativeHandoff,!nativeComplete,let workerMetadataVersion,[2,3].contains(workerMetadataVersion) {
                    zeroPostEvidence=WorkerZeroPostEvidence(handoff:nativeHandoff,grant:grant,workerMetadataVersion:workerMetadataVersion)
                }
                if let nativePreparation,workerMetadataVersion==3 {
                    zeroPostPreparationEvidence=WorkerPreparationZeroPostEvidence(preparation:nativePreparation,grant:grant,workerMetadataVersion:3)
                }
                // Preserve the once-produced local certificate even if the
                // independent native-hold write encounters storage failure.
                try resolve(.not_sent)
            }
            if !terminal && !nativeComplete { try retainNativeUncertainty() }
        }
        return events
    }
}
