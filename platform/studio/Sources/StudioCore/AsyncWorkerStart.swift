import Foundation
import Darwin

enum WorkerStartFailure:Error,Sendable {
    case cancelled,unavailable
    case neverSpawned(WorkerNeverSpawnedEvidence)
}

// A lexical process/pipe owner. The background producer stops using it before
// publishing; the serialized manager consumes it once and owns all journal I/O.
final class StartedPythonWorker:@unchecked Sendable {
    private let process:Process
    private let input:FileHandle
    private let output:FileHandle
    private let captured:WorkerGrant?
    private let handoff:WorkerHandoffBinding?
    private let preparation:WorkerPreparationBinding?
    private var transferred=false
    init(process:Process,input:FileHandle,output:FileHandle,grant:WorkerGrant?,handoff:WorkerHandoffBinding?=nil,preparation:WorkerPreparationBinding?=nil) {
        self.process=process;self.input=input;self.output=output;captured=grant;self.handoff=handoff;self.preparation=preparation
    }
    func bind(journal:Journal,key:WorkerLaunchKey,nonce:String,started:Int64,readyAt:Int64)throws->PrivateWorker {
        guard !transferred,let captured else {throw RuntimeError.identity}
        let worker=try PrivateWorker(process:process,input:input,output:output,journal:journal,job:key.job,attempt:key.attempt,
            started:started,readyAt:readyAt,capturedGrant:captured,launchNonce:nonce,nativeHandoff:handoff,nativePreparation:preparation)
        transferred=true
        return worker
    }
    func revokeUnbound() {
        guard !transferred,let captured,process.processIdentifier==captured.pid,process.isRunning,
              (try? HostBoot.identity())==captured.boot,
              (try? WorkerResources.startIdentifier(pid:captured.pid))==captured.start else {return}
        // Retain pipes and original captured identity for later durable local
        // binding/reaping. No permission bytes have been enqueued.
        kill(captured.pid,SIGKILL)
    }
    deinit {
        if !transferred {
            try? input.close();try? output.close()
            if process.isRunning {kill(process.processIdentifier,SIGKILL)}
            // No local/native ownership release; durable intent stays retained.
        }
    }
}

// One operation/result slot, queue0. No SQLite or permission-byte write is
// possible in the factory's Sendable work closure. Cancel never waits for I/O.
final class PendingPythonWorker:@unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    private var result:Result<StartedPythonWorker,WorkerStartFailure>?
    init(initiallyCancelled:Bool=false,work:@escaping @Sendable (@Sendable ()->Bool)->Result<StartedPythonWorker,WorkerStartFailure>) {
        cancelled=initiallyCancelled
        Thread.detachNewThread { [self] in
            let value=work { [self] in lock.lock();defer {lock.unlock()};return cancelled }
            lock.lock();result=value;lock.unlock()
        }
    }
    func cancel() {lock.lock();cancelled=true;lock.unlock()}
    func take()->Result<StartedPythonWorker,WorkerStartFailure>? {
        lock.lock();defer {lock.unlock()}
        let value=result;result=nil;return value
    }
}
