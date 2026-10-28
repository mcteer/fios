import Foundation
import Darwin
import CoreFoundation

// Owns one already-launched, approved private Pydantic child. Factories must
// reserve512MiB and durable ownership BEFORE launching; no task supplies argv.
// Poll only from the serialized manager. No workload data enters the journal.
final class PrivateWorker {
    private let process:Process
    private let input:FileHandle
    private let output:FileHandle
    private let journal:Journal
    private let grant:WorkerGrant
    private let job:String
    private let attempt:Int
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
    private(set) var reaped=false
    private(set) var memorySamples=0

    init(process:Process,input:FileHandle,output:FileHandle,journal:Journal,job:String,attempt:Int,started:Int64) throws {
        guard process.processIdentifier>1,try journal.hasClaim(job:job,attempt:attempt) else { throw JournalError.invalid }
        grant=try WorkerGrant.capture(pid:process.processIdentifier)
        self.process=process;self.input=input;self.output=output;self.journal=journal;self.job=job;self.attempt=attempt
        parser=ModelWorkerProtocol(job:job,attempt:attempt);memory=try WorkerMemoryGuard(started:started)
        self.started=started;lastSample=started;lastPoll=started
        guard fcntl(input.fileDescriptor,F_SETFL,O_NONBLOCK)>=0,
              fcntl(input.fileDescriptor,F_SETNOSIGPIPE,1)>=0,
              fcntl(output.fileDescriptor,F_SETFL,O_NONBLOCK)>=0 else { throw RuntimeError.launch }
        try journal.bindWorker(job:job,attempt:attempt,grant:grant)
    }
    deinit {
        try? input.close();try? output.close()
        if process.isRunning { kill(process.processIdentifier,SIGKILL) }
        // Durable ownership is intentionally not released by destruction.
    }
    func enqueue(_ command:Data,expectedModel:String,endpointHash:String,epoch:String,now:Int64) throws {
        guard !commandAccepted,!revoked,command.count<=1<<20 else { throw ControlError.invalid_request }
        try StrictJSON.validate(command,maximum:1<<20)
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
        let size=UInt32(command.count)
        outgoing=Data([UInt8(size>>24),UInt8((size>>16)&255),UInt8((size>>8)&255),UInt8(size&255)])
        outgoing.append(command);commandAccepted=true
    }
    func cancel(now:Int64) throws {
        guard !revoked else { return }
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else { throw WorkerResourceError.invalid }
        revoked=true;cancelAt=now;outgoing.removeAll();sent=0
        defer {
            try? input.close()
            if process.isRunning { process.terminate() }
        }
        if !nativeComplete { try journal.markUncertain(job:job,attempt:attempt) }
    }
    func poll(now:Int64,authorized:Bool) throws -> [ModelWorkerEvent] {
        guard !reaped else { return [] }
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else { try cancel(now:started);throw WorkerResourceError.invalid }
        if now<lastPoll {
            try cancel(now:now)
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
        }
        lastPoll=max(lastPoll,now)
        if !authorized || now<started || now-started>=180000 { try cancel(now:now) }
        if process.isRunning && now-lastSample>=1000 {
            let resident=try? WorkerResources.residentBytes(pid:process.processIdentifier)
            let action=try memory.observe(resident:resident,now:now);lastSample=now;memorySamples+=1
            if action != .continueRunning { try cancel(now:now) }
            if action == .kill || action == .cleanupOverdue { kill(process.processIdentifier,SIGKILL) }
        }
        if let cancelAt,now-cancelAt>=1000,process.isRunning { kill(process.processIdentifier,SIGKILL) }
        if !revoked && sent<outgoing.count {
            if now-started>=10000 { try cancel(now:now) }
            else {
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
                    if !revoked { try journal.complete(job:job,attempt:attempt);nativeComplete=true;events.append(event) }
                case .interrupted,.failed:
                    terminal=true
                    if !nativeComplete { try journal.markUncertain(job:job,attempt:attempt) }
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
            process.waitUntilExit();reaped=true
            try journal.recordWorkerGone(job:job,attempt:attempt,grant:grant)
            // A trustworthy once-only zero-POST summary plus correlated
            // terminal and fully reaped child proves non-dispatch. Neither
            // cancellation nor child exit alone supplies this evidence.
            if !protocolBroken && terminal && actualPosts==0 && !nativeComplete {
                try journal.complete(job:job,attempt:attempt);nativeComplete=true
            }
            if !terminal && !nativeComplete { try journal.markUncertain(job:job,attempt:attempt) }
        }
        return events
    }
}
