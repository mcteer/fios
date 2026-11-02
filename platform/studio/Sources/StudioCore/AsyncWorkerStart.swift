import Foundation
import Darwin

enum WorkerStartFailure:Error,Sendable {case cancelled,unavailable}

// A lexical process/pipe owner. The background producer stops using it before
// publishing; the serialized manager consumes it once and owns all journal I/O.
final class StartedPythonWorker:@unchecked Sendable {
    private let process:Process
    private let input:FileHandle
    private let output:FileHandle
    private let captured:WorkerGrant?
    private var transferred=false
    init(process:Process,input:FileHandle,output:FileHandle,grant:WorkerGrant?) {
        self.process=process;self.input=input;self.output=output;captured=grant
    }
    func bind(journal:Journal,key:WorkerLaunchKey,nonce:String,started:Int64,readyAt:Int64)throws->PrivateWorker {
        guard !transferred,let captured else {throw RuntimeError.identity}
        let worker=try PrivateWorker(process:process,input:input,output:output,journal:journal,job:key.job,attempt:key.attempt,
            started:started,readyAt:readyAt,capturedGrant:captured,launchNonce:nonce)
        transferred=true
        return worker
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
    init(work:@escaping @Sendable (@Sendable ()->Bool)->Result<StartedPythonWorker,WorkerStartFailure>) {
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
